import Foundation
import Combine
import SendspinKit
import UIKit

// Facade for SendspinKit to match the app's expectation
// Adapts the modern SendspinKit actor-based client to the app's ObservableObject requirements

@MainActor
class SendspinClient: ObservableObject {
    @Published var isConnected = false
    @Published var isBuffering = false
    @Published var bufferProgress: Double = 0.0
    @Published var connectionError: String?
    @Published var playerName: String = "iOS Sendspin"
    
    // Internal client from SendspinKit
    private var client: SendspinKit.SendspinClient?
    private var eventTask: Task<Void, Never>?
    
    static let shared = SendspinClient()
    
    private init() {
        // Initialize logic if needed
    }
    
    func connect(to host: String, port: UInt16 = 8927, scheme: String = "ws", accessToken: String? = nil) {
        let urlString = "\(scheme)://\(host):\(port)/sendspin"
        print("[SendspinClient] Connecting to: \(urlString)")
        print("[SendspinClient] Access token provided: \(accessToken != nil)")
        print("[SendspinClient] Access token length: \(accessToken?.count ?? 0)")

        guard let url = URL(string: urlString) else {
            self.connectionError = "Invalid URL: \(urlString)"
            print("[SendspinClient] ERROR: Invalid URL")
            return
        }

        disconnect()

        // Create configuration for the client
        // Only advertise 48kHz support to force server-side resampling if needed
        let playerConfig = PlayerConfiguration(
            bufferCapacity: 2 * 1024 * 1024, // 2MB buffer
            supportedFormats: [
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48000, bitDepth: 16),
                AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 48000, bitDepth: 16)
            ]
        )

        let clientName = UIDevice.current.name
        let clientId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        print("[SendspinClient] Client ID: \(clientId)")
        print("[SendspinClient] Client Name: \(clientName)")

        let client = SendspinKit.SendspinClient(
            clientId: clientId,
            name: "iOS Player (\(clientName))",
            roles: [.playerV1],
            playerConfig: playerConfig,
            accessToken: accessToken
        )

        self.client = client

        // Start listening to events
        eventTask = Task {
            for await event in client.events {
                handleEvent(event)
            }
        }

        Task {
            do {
                print("[SendspinClient] Starting connection...")
                try await client.connect(to: url)
                print("[SendspinClient] Connection initiated successfully")
            } catch {
                print("[SendspinClient] Connection error: \(error)")
                self.connectionError = "Connection failed: \(error.localizedDescription)"
                self.isConnected = false
            }
        }
    }
    
    func disconnect() {
        eventTask?.cancel()
        Task {
            await client?.disconnect()
            self.client = nil
        }
        isConnected = false
        isBuffering = false
    }
    
    private func handleEvent(_ event: ClientEvent) {
        print("[SendspinClient] Event received: \(event)")
        switch event {
        case .serverConnected(let info):
            print("[SendspinClient] Connected to \(info.name)")
            self.isConnected = true
            self.connectionError = nil

        case .streamStarted(let format):
            print("[SendspinClient] Stream started: \(format)")
            self.isBuffering = true
            // Simulate buffering progress for UI
            Task {
                for i in 1...10 {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    self.bufferProgress = Double(i) / 10.0
                }
                self.isBuffering = false
            }

        case .streamEnded:
            print("[SendspinClient] Stream ended")
            self.isBuffering = false
            self.bufferProgress = 0.0

        case .error(let msg):
            print("[SendspinClient] Error: \(msg)")
            self.connectionError = msg

        default:
            print("[SendspinClient] Unhandled event: \(event)")
            break
        }
    }
    
    // Playback controls (proxied to client if supported, or handled via server commands)
    // Note: Sendspin is a passive player. "Resume" usually means "Unmute" or "Start Engine" locally.
    // The Kit handles the engine automatically on stream start.
    
    func pausePlayback() {
        Task {
            await client?.pausePlayback()
        }
    }
    
    func resumePlayback() {
        Task {
            await client?.resumePlayback()
        }
    }
    
    func stopPlayback() {
        // Stop is usually server side, but we can mute locally
        Task {
            await client?.disconnect() // Or just mute? Old client stopped engine.
            // Reconnect logic might be needed if we disconnect.
            // Better to just let the stream end event handle it.
        }
    }
}
