# Xonora Alpha Build - Release Notes

## Version: Alpha 1.0
**Release Date:** January 8, 2026  
**Build Type:** Unsigned Development Build

---

## 🎵 What is Xonora?

Xonora (formerly MusicAssistantPlayer) is an iOS music streaming app that connects to Music Assistant servers and streams high-quality audio via the Sendspin protocol.

---

## ✨ What's New in Alpha 1.0

### 🎨 Branding & Design
- **New Name:** Rebranded from MusicAssistantPlayer to Xonora
- **New Logo:** Beautiful resonance rings design with purple-to-cyan gradient
- **Color Scheme:** Complete UI refresh with Xonora brand colors
  - Purple (#6B46C1) → Blue (#3B82F6) → Cyan (#06B6D4)
  - Dark mode optimized
  - Gradient accents throughout the app

### 🚀 Performance Improvements
- **Threading Optimization:** Eliminated UI blocking during audio operations
- **Smooth Playback:** No more stuttering when switching tabs or searching
- **Instant Controls:** Play/pause responds immediately (no server delay)
- **Accurate Progress:** Progress bar only advances when audio is actually playing

### 🐛 Bug Fixes
- Fixed audio stuttering during UI interactions
- Fixed 3-5 second delay when resuming playback
- Fixed progress bar counting before audio starts
- Fixed Now Playing artwork not displaying
- Fixed network connection errors causing gesture timeouts
- Fixed Sendspin connection race conditions

### 🎛️ Audio Enhancements
- Optimized audio buffer (20ms, 10 chunks)
- Enhanced audio session management
- Better interruption handling (calls, alarms)
- Auto-restart on audio engine failure
- Improved route change detection (headphones, Bluetooth)

### 📱 UI Improvements
- Removed audiobooks section (focusing on core music features)
- Updated tab bar: Library, Search, Now Playing, Settings
- Gradient backgrounds in Now Playing view
- Xonora-themed server setup screen

---

## 📦 Installation

**⚠️ Important:** This is an **unsigned development build**. To install:

1. **Using AltStore/SideStore:**
   - Install AltStore or SideStore on your device
   - Open the IPA file with AltStore/SideStore
   - Follow the on-screen instructions

2. **Using Xcode:**
   - Connect your device
   - Drag the IPA to Xcode's Devices window
   - Install to your device

3. **Using iOS App Signer:**
   - Sign the IPA with your own certificate
   - Install via iTunes or Xcode

---

## 🔧 Requirements

- **iOS:** 15.0 or later
- **Music Assistant Server:** Required (with Sendspin enabled)
- **Network:** Local network access for server connection

---

## 🎯 Known Limitations

- **Unsigned Build:** Requires sideloading (not from App Store)
- **7-Day Expiry:** Free Apple Developer accounts expire after 7 days
- **CarPlay:** May require additional setup
- **Background Playback:** Fully supported

---

## 🔗 Setup Instructions

1. Launch Xonora
2. Enter your Music Assistant server URL (e.g., `http://192.168.1.100:8095`)
3. Enter your access token (create in Music Assistant UI)
4. Tap "Connect"
5. Browse your library and enjoy!

---

## 📝 Technical Details

### Audio Configuration
- Sample Rate: 48000 Hz
- Channels: 2 (stereo)
- Bit Depth: 16-bit PCM
- Buffer Duration: 20ms
- Player Buffer: 10 chunks

### Threading Architecture
- Dedicated audio thread (QoS: .userInteractive)
- Network queue for server communication
- Background queues for search and library loading
- Main thread reserved for UI updates only

---

## 🐛 Reporting Issues

Found a bug? Please report it on GitHub with:
- Device model and iOS version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

---

## 🙏 Credits

Built with ❤️ for the Music Assistant community

**Technologies:**
- SwiftUI
- AVFoundation
- Sendspin Protocol
- Music Assistant API

---

## 📄 License

See LICENSE file for details.

---

**Enjoy your music with Xonora! 🎶**
