// ABOUTME: AVAudioEngine-based audio player with simple buffer scheduling
// ABOUTME: Replaces AudioQueue with modern AVAudioEngine for reliable playback

import AVFoundation
import Accelerate
import Foundation

/// Audio player using AVAudioEngine for playback
/// Thread-safe using dedicated DispatchQueue (AVAudioEngine is not Sendable)
public final class AudioPlayer: @unchecked Sendable {
    // Audio engine components (accessed only on audioThread)
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    // Decoder (accessed only on audioThread)
    private var decoder: AudioDecoder?
    private var currentFormat: AudioFormatSpec?

    // Playback state
    private var _isPlaying: Bool = false
    private var _volume: Float = 1.0
    private var _muted: Bool = false

    // Buffer management
    private var audioBuffer = Data()
    private let bufferLock = NSLock()
    private var chunksInNode = 0
    private let maxChunksInNode = 10
    private var isPlaybackStarted = false

    // Scheduling
    private var scheduleTimer: DispatchSourceTimer?

    // Configuration
    private let engineSampleRate: Double = 48000
    private let scheduleChunkSeconds: Double = 0.1  // 100ms chunks
    private let initialBufferSeconds: Double = 0.3  // Buffer 300ms before starting

    // Dedicated audio thread
    private let audioThread: DispatchQueue

    // Public state accessors (thread-safe)
    public var isPlaying: Bool {
        audioThread.sync { _isPlaying }
    }

    public var volume: Float {
        audioThread.sync { _volume }
    }

    public var muted: Bool {
        audioThread.sync { _muted }
    }

    public init() {
        audioThread = DispatchQueue(
            label: "com.sendspinkit.audiothread",
            qos: .userInteractive
        )
        setupNotifications()
    }

    deinit {
        scheduleTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.audioThread.async {
                self?.handleInterruption(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.audioThread.async {
                self?.handleRouteChange(notification)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.audioThread.async {
                self?.handleMediaServicesReset()
            }
        }
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setPreferredIOBufferDuration(0.02)  // 20ms buffer
            try session.setActive(true)
            print("[AudioPlayer] Audio session configured")
        } catch {
            print("[AudioPlayer] Audio session error: \(error)")
        }
    }

    private func setupEngine() {
        guard engine == nil else { return }

        let newEngine = AVAudioEngine()
        let newPlayerNode = AVAudioPlayerNode()

        newEngine.attach(newPlayerNode)

        // Connect with standard Float32 format at engine sample rate
        if let format = AVAudioFormat(
            standardFormatWithSampleRate: engineSampleRate,
            channels: 2
        ) {
            newEngine.connect(newPlayerNode, to: newEngine.mainMixerNode, format: format)
        }

        engine = newEngine
        playerNode = newPlayerNode

        print("[AudioPlayer] Audio engine created")
    }

    private func startEngine() {
        guard let engine = engine, !engine.isRunning else { return }

        do {
            try engine.start()
            playerNode?.play()
            print("[AudioPlayer] Audio engine started")
        } catch {
            print("[AudioPlayer] Engine start error: \(error)")
        }
    }

    private func stopEngine() {
        playerNode?.stop()
        engine?.stop()
    }

    private func teardownEngine() {
        stopEngine()
        engine = nil
        playerNode = nil
        decoder = nil
        currentFormat = nil
    }

    // MARK: - Public Interface

    /// Start playback with specified format
    public func start(format: AudioFormatSpec, codecHeader: Data?) throws {
        try audioThread.sync {
            // Don't restart if already playing with same format
            if _isPlaying, currentFormat == format {
                return
            }

            // Stop existing playback
            stopInternal()

            // Create decoder for codec
            decoder = try AudioDecoderFactory.create(
                codec: format.codec,
                sampleRate: format.sampleRate,
                channels: format.channels,
                bitDepth: format.bitDepth,
                header: codecHeader
            )
            currentFormat = format

            // Setup audio
            setupAudioSession()
            setupEngine()
            startEngine()
            startScheduleTimer()

            _isPlaying = true
            print("[AudioPlayer] Started with format: \(format.codec) \(format.sampleRate)Hz \(format.channels)ch \(format.bitDepth)bit")
        }
    }

    /// Decode compressed audio and buffer for playback
    public func decode(_ data: Data) throws -> Data {
        return try audioThread.sync {
            guard let decoder = decoder else {
                throw AudioPlayerError.notStarted
            }
            return try decoder.decode(data)
        }
    }

    /// Add decoded PCM data to buffer for playback
    public func playPCM(_ pcmData: Data) {
        bufferLock.lock()
        audioBuffer.append(pcmData)
        bufferLock.unlock()
    }

    /// Stop playback and clean up
    public func stop() {
        audioThread.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        scheduleTimer?.cancel()
        scheduleTimer = nil

        teardownEngine()

        bufferLock.lock()
        audioBuffer.removeAll(keepingCapacity: true)
        chunksInNode = 0
        isPlaybackStarted = false
        bufferLock.unlock()

        _isPlaying = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[AudioPlayer] Stopped")
    }

    /// Set volume (0.0 to 1.0)
    public func setVolume(_ volume: Float) {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            let clamped = max(0.0, min(1.0, volume))
            self._volume = clamped
            self.playerNode?.volume = self._muted ? 0.0 : clamped
        }
    }

    /// Set mute state
    public func setMute(_ muted: Bool) {
        audioThread.async { [weak self] in
            guard let self = self else { return }
            self._muted = muted
            self.playerNode?.volume = muted ? 0.0 : self._volume
        }
    }

    // MARK: - Scheduling

    private func startScheduleTimer() {
        scheduleTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: audioThread)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.1)  // Every 100ms
        timer.setEventHandler { [weak self] in
            self?.scheduleBufferedAudio()
        }
        timer.resume()
        scheduleTimer = timer
    }

    private func scheduleBufferedAudio() {
        guard let format = currentFormat else { return }

        // Calculate bytes per second based on format
        let effectiveBitDepth = self.effectiveBitDepth(for: format)
        let bytesPerFrame = format.channels * (effectiveBitDepth / 8)
        let bytesPerSecond = format.sampleRate * bytesPerFrame
        let chunkBytes = Int(scheduleChunkSeconds * Double(bytesPerSecond))
        let initialBufferBytes = Int(initialBufferSeconds * Double(bytesPerSecond))

        bufferLock.lock()

        // Wait for initial buffer before starting playback
        if !isPlaybackStarted {
            if audioBuffer.count >= initialBufferBytes {
                isPlaybackStarted = true
                print("[AudioPlayer] Initial buffer ready (\(audioBuffer.count) bytes), starting playback")
            } else {
                bufferLock.unlock()
                return
            }
        }

        // Schedule chunks while we have data and room in the node
        while audioBuffer.count >= chunkBytes && chunksInNode < maxChunksInNode {
            let chunkData = Data(audioBuffer.prefix(chunkBytes))
            audioBuffer.removeFirst(chunkBytes)
            chunksInNode += 1
            bufferLock.unlock()

            scheduleChunk(chunkData, format: format)

            bufferLock.lock()
        }

        bufferLock.unlock()
    }

    private func scheduleChunk(_ data: Data, format: AudioFormatSpec) {
        guard let playerNode = playerNode,
              let engineFormat = AVAudioFormat(
                  standardFormatWithSampleRate: engineSampleRate,
                  channels: 2
              ) else {
            return
        }

        let effectiveBitDepth = self.effectiveBitDepth(for: format)
        let bytesPerFrame = format.channels * (effectiveBitDepth / 8)
        let frameCount = data.count / bytesPerFrame

        guard frameCount > 0 else { return }

        // Create buffer at engine sample rate (will resample if needed)
        let outputFrameCount: Int
        if format.sampleRate != Int(engineSampleRate) {
            outputFrameCount = Int(Double(frameCount) * engineSampleRate / Double(format.sampleRate))
        } else {
            outputFrameCount = frameCount
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engineFormat,
            frameCapacity: AVAudioFrameCount(outputFrameCount)
        ) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(outputFrameCount)

        guard let floatChannelData = buffer.floatChannelData else { return }

        // Convert based on bit depth
        if effectiveBitDepth == 16 {
            convertInt16ToFloat32(data, into: floatChannelData, frameCount: frameCount, channels: format.channels)
        } else {
            convertInt32ToFloat32(data, into: floatChannelData, frameCount: frameCount, channels: format.channels)
        }

        // Simple resampling if needed (linear interpolation)
        if format.sampleRate != Int(engineSampleRate) {
            resampleInPlace(buffer, fromRate: format.sampleRate, toRate: Int(engineSampleRate), originalFrames: frameCount)
        }

        // Ensure engine is running
        if let engine = engine, !engine.isRunning {
            startEngine()
        }

        // Schedule with completion callback for backpressure
        playerNode.scheduleBuffer(buffer) { [weak self] in
            self?.bufferLock.lock()
            self?.chunksInNode = max(0, (self?.chunksInNode ?? 1) - 1)
            self?.bufferLock.unlock()
        }
    }

    // MARK: - Format Conversion

    private func effectiveBitDepth(for format: AudioFormatSpec) -> Int {
        switch format.codec {
        case .flac, .opus:
            return 32  // These decoders always output Int32
        case .pcm:
            return format.bitDepth == 24 ? 32 : format.bitDepth
        }
    }

    private func convertInt16ToFloat32(
        _ data: Data,
        into floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channels: Int
    ) {
        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }

            if channels == 2 {
                // Stereo: deinterleave and convert
                var leftInt16 = [Int16](repeating: 0, count: frameCount)
                var rightInt16 = [Int16](repeating: 0, count: frameCount)

                for i in 0..<frameCount {
                    leftInt16[i] = int16Ptr[i * 2]
                    rightInt16[i] = int16Ptr[i * 2 + 1]
                }

                // SIMD conversion using Accelerate
                var scale: Float = 1.0 / 32768.0
                vDSP_vflt16(leftInt16, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vflt16(rightInt16, 1, floatChannelData[1], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[1], 1, &scale, floatChannelData[1], 1, vDSP_Length(frameCount))
            } else {
                // Mono: convert and duplicate to stereo
                var scale: Float = 1.0 / 32768.0
                vDSP_vflt16(int16Ptr, 1, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(floatChannelData[0], 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                // Copy to right channel
                memcpy(floatChannelData[1], floatChannelData[0], frameCount * MemoryLayout<Float>.size)
            }
        }
    }

    private func convertInt32ToFloat32(
        _ data: Data,
        into floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channels: Int
    ) {
        data.withUnsafeBytes { rawBuffer in
            guard let int32Ptr = rawBuffer.bindMemory(to: Int32.self).baseAddress else { return }

            if channels == 2 {
                // Stereo: deinterleave and convert
                var leftInt32 = [Int32](repeating: 0, count: frameCount)
                var rightInt32 = [Int32](repeating: 0, count: frameCount)

                for i in 0..<frameCount {
                    leftInt32[i] = int32Ptr[i * 2]
                    rightInt32[i] = int32Ptr[i * 2 + 1]
                }

                // Convert Int32 to Float using Accelerate
                var leftFloat = [Float](repeating: 0, count: frameCount)
                var rightFloat = [Float](repeating: 0, count: frameCount)

                vDSP_vflt32(leftInt32, 1, &leftFloat, 1, vDSP_Length(frameCount))
                vDSP_vflt32(rightInt32, 1, &rightFloat, 1, vDSP_Length(frameCount))

                // Scale to -1.0...1.0
                var scale: Float = 1.0 / Float(Int32.max)
                vDSP_vsmul(leftFloat, 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                vDSP_vsmul(rightFloat, 1, &scale, floatChannelData[1], 1, vDSP_Length(frameCount))
            } else {
                // Mono: convert and duplicate to stereo
                var floatBuffer = [Float](repeating: 0, count: frameCount)
                vDSP_vflt32(int32Ptr, 1, &floatBuffer, 1, vDSP_Length(frameCount))

                var scale: Float = 1.0 / Float(Int32.max)
                vDSP_vsmul(floatBuffer, 1, &scale, floatChannelData[0], 1, vDSP_Length(frameCount))
                memcpy(floatChannelData[1], floatChannelData[0], frameCount * MemoryLayout<Float>.size)
            }
        }
    }

    private func resampleInPlace(
        _ buffer: AVAudioPCMBuffer,
        fromRate sourceRate: Int,
        toRate targetRate: Int,
        originalFrames: Int
    ) {
        guard let floatChannelData = buffer.floatChannelData else { return }

        let targetFrames = Int(buffer.frameLength)
        let ratio = Double(sourceRate) / Double(targetRate)

        // Simple linear interpolation resampling
        for channel in 0..<2 {
            let channelData = floatChannelData[channel]
            var resampled = [Float](repeating: 0, count: targetFrames)

            for i in 0..<targetFrames {
                let sourcePos = Double(i) * ratio
                let sourceIndex = Int(sourcePos)
                let frac = Float(sourcePos - Double(sourceIndex))

                if sourceIndex + 1 < originalFrames {
                    resampled[i] = channelData[sourceIndex] * (1.0 - frac) + channelData[sourceIndex + 1] * frac
                } else if sourceIndex < originalFrames {
                    resampled[i] = channelData[sourceIndex]
                }
            }

            // Copy back
            memcpy(channelData, resampled, targetFrames * MemoryLayout<Float>.size)
        }
    }

    // MARK: - Interruption Handling

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("[AudioPlayer] Interruption began")
            playerNode?.pause()

        case .ended:
            print("[AudioPlayer] Interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        if engine?.isRunning == false {
                            try engine?.start()
                        }
                        playerNode?.play()
                        print("[AudioPlayer] Resumed after interruption")
                    } catch {
                        print("[AudioPlayer] Failed to resume: \(error)")
                    }
                }
            }

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        print("[AudioPlayer] Route change: \(reason.rawValue)")

        if reason == .oldDeviceUnavailable {
            playerNode?.pause()
        }
    }

    private func handleMediaServicesReset() {
        print("[AudioPlayer] Media services reset - reinitializing")
        let wasPlaying = _isPlaying
        let savedFormat = currentFormat
        let savedDecoder = decoder

        teardownEngine()
        setupEngine()

        if wasPlaying {
            decoder = savedDecoder
            currentFormat = savedFormat
            startEngine()
            startScheduleTimer()
            _isPlaying = true
        }
    }
}

public enum AudioPlayerError: Error {
    case notStarted
    case decodingFailed
    case bufferCreationFailed
    case unsupportedFormat
}
