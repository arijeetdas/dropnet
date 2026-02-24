# 📄 PROJECT_SPEC_DROPNET.md

# Project Name: DropNet

### Cross-Platform LAN File Transfer App

### Tech Stack: Flutter + Pure Dart Networking

### Design: Material 3

---

# 1️⃣ PRODUCT VISION

DropNet is a cross-platform, offline, LAN-based file transfer app.

It includes:

* Everything LocalSend provides
* FTP Server mode
* Temporary local web file sharing
* Encrypted peer-to-peer transfer
* Real-time device discovery
* Folder transfer
* Large file streaming
* Cross-platform support

This is a portfolio-grade networking-heavy project demonstrating:

* Real-time networking
* Encryption
* Background services
* Embedded servers
* Advanced Flutter architecture

---

# 2️⃣ DESIGN SYSTEM

Use Material 3:

```dart
theme: ThemeData(
  useMaterial3: true,
)
```

Design rules:

* Modern minimal UI
* 16px+ rounded corners
* Animated progress bars
* Smooth device appearance animation
* Dark mode default
* Speed indicator animations
* Gradient accent highlights
* Subtle glass-like cards
* Responsive desktop layout

---

# 3️⃣ SUPPORTED PLATFORMS

* Android
* Windows
* macOS
* Linux
* iOS (limited background support)

---

# 4️⃣ CORE FEATURES (LocalSend Equivalent)

## 🔍 Device Discovery

* Auto-discover devices on same LAN
* Use:

  * mDNS (Bonjour)
  * UDP broadcast fallback
* Show:

  * Device name
  * Device type (mobile/desktop)
  * Online status
  * IP address

Discovery refresh every 3 seconds.

---

## 📤 File Sending

Support:

* Single file
* Multiple files
* Folder transfer
* Large files (no memory load)
* Streaming file chunks
* Resume capability (optional advanced)
* Pause / Cancel
* Transfer speed display
* Progress percentage

Use TCP socket for transfer.

---

## 📥 File Receiving

* Incoming request dialog
* Accept / Reject
* Choose save location
* Auto-save rules option
* Background receive support
* File overwrite protection

---

## 🔐 Encryption

All transfers must use:

* AES encryption (session-based)
* Generate random session key per transfer
* Share session key securely before transfer
* Encrypt chunks before sending

Never send raw file data.

---

# 5️⃣ ADVANCED FEATURE 1: FTP SERVER MODE

## Purpose

Allow device to act as FTP server for LAN access.

---

## FTP Mode Behavior

When enabled:

* Start FTP server
* Display:

  * Local IP
  * Port (default 2121)
  * Username
  * Password
* Toggle:

  * Anonymous mode
  * Read-only mode

Example display:

```
ftp://192.168.1.24:2121
Username: dropnet
Password: ********
```

Other devices connect via:

* FileZilla
* Windows Explorer
* Finder
* Linux file manager

---

## FTP Requirements

* Support upload & download
* Configurable root directory
* Show active connections
* Show transfer logs
* Ability to stop server anytime

---

# 6️⃣ ADVANCED FEATURE 2: TEMPORARY LOCAL WEBSITE

## Embedded HTTP Server

Start local web server:

* Default port: 8080
* Generate access URL
* Generate QR code

Example:

```
http://192.168.1.24:8080
```

---

## Website Capabilities

Web interface allows:

* Drag & drop upload
* File download
* File preview (image/video)
* Upload progress bar
* Mobile-friendly UI

---

## Security

* Generate random session token
* Add token in URL:

```
http://192.168.1.24:8080/?token=XYZ123
```

* Optional expiry timer:

  * 10 min
  * 30 min
  * 1 hour
  * Manual stop

---

# 7️⃣ EXTRA ADVANCED FEATURES

## 📜 Transfer History

Store locally:

* File name
* Size
* Date
* Device name
* Status
* Duration

---

## 🚀 Speed Optimization

* Adjustable buffer size
* Parallel chunk sending
* Speed limiter option
* Show:

  * Current speed
  * Average speed
  * Estimated time remaining

---

## 📁 Smart Auto Save Rules

Rules:

* Images → Pictures folder
* Videos → Videos folder
* Documents → Documents folder
* Custom folder rule

---

## 🔗 QR Direct Pairing

* Generate QR with:

  * Device IP
  * Device ID
* Scan to instantly connect

---

## 📶 Multi-Network Support

* WiFi
* Ethernet
* Hotspot
* Local LAN only (no internet servers)

---

## 🔄 Resume Interrupted Transfers

* Save partial file
* Resume from last byte
* Validate checksum

---

## 🧮 File Integrity Verification

After transfer:

* Generate SHA256 checksum
* Verify on receiver side
* Show “Verified” badge

---

## 📊 Transfer Analytics Screen

Show:

* Total files sent
* Total files received
* Total GB transferred
* Average speed
* Most active device

---

# 8️⃣ NETWORKING ARCHITECTURE

## Discovery Layer

* bonsoir (mDNS)
* UDP broadcast fallback

---

## Transfer Layer

* TCP sockets
* Stream-based
* Chunk size: configurable
* Encrypted chunk transmission

---

## FTP Layer

* Dart FTP server implementation

---

## Web Layer

Use:

* shelf
* shelf_router
* shelf_static

Embedded web UI must be included in assets folder.

---

# 9️⃣ DATA MODELS

DeviceModel:

```
{
  deviceId,
  deviceName,
  ipAddress,
  deviceType,
  isOnline
}
```

TransferModel:

```
{
  id,
  fileName,
  size,
  progress,
  speed,
  status,
  deviceName,
  startedAt
}
```

---

# 🔟 PROJECT STRUCTURE

```
lib/
 ├── main.dart
 ├── app.dart
 ├── core/
 │    ├── networking/
 │    │     ├── discovery_service.dart
 │    │     ├── tcp_transfer_service.dart
 │    │     ├── ftp_service.dart
 │    │     ├── web_server_service.dart
 │    ├── encryption/
 │    ├── utils/
 │
 ├── features/
 │    ├── home/
 │    ├── send/
 │    ├── receive/
 │    ├── ftp_mode/
 │    ├── web_mode/
 │    ├── history/
 │    ├── analytics/
 │
 ├── models/
 │    ├── device_model.dart
 │    ├── transfer_model.dart
 │
 ├── widgets/
 │    ├── device_card.dart
 │    ├── transfer_progress_card.dart
 │    ├── speed_indicator.dart
```

Architecture:

* Feature-first
* Service layer abstraction
* Stream-based state updates
* Riverpod state management

---

# 1️⃣1️⃣ DEPENDENCIES

Add to pubspec.yaml:

* flutter_riverpod
* go_router
* bonsoir
* network_info_plus
* file_picker
* path_provider
* permission_handler
* crypto
* shelf
* shelf_router
* shelf_static
* qr_flutter
* uuid
* flutter_background_service

---

# 1️⃣2️⃣ SECURITY REQUIREMENTS

* Never expose raw storage paths
* Validate file names
* Prevent directory traversal
* Limit max concurrent transfers
* Prevent unauthorized device injection
* Secure token-based web access
* Disable FTP by default

---

# 1️⃣3️⃣ PERFORMANCE REQUIREMENTS

* Must support 10GB+ transfers
* Use stream reading
* Avoid loading entire file in memory
* Handle network drop gracefully
* Retry mechanism for unstable networks

---

# 1️⃣4️⃣ UI SCREENS REQUIRED

* Home (Nearby Devices)
* Send Files
* Receive Screen
* Active Transfers
* FTP Mode
* Web Mode
* Transfer History
* Analytics Dashboard
* Settings

---

# 1️⃣5️⃣ COPILOT INSTRUCTION

Generate:

* Full Flutter project
* Networking layer
* Encryption implementation
* FTP server
* Embedded web server
* Real-time discovery
* Background support
* Fully working file transfer
* Production-ready structure
* No TODO placeholders
* Compilable project

---

# 🔥 FINAL GOAL

DropNet should demonstrate:

* Advanced networking
* Encryption
* Embedded servers
* Real-time communication
* Clean architecture
* Professional-level Flutter engineering

---
