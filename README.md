# 🚀 DropNet

<p align="center">
  <img src="assets/icon/app_icon.png" width="140" height="140" style="border-radius: 32px; box-shadow: 0 12px 30px rgba(0,0,0,0.25);" alt="DropNet App Icon" />
</p>

<h3 align="center">DropNet</h3>

<p align="center">
  <strong>Blazing fast, zero-trust local peer-to-peer file and text streaming wrapped in a highly responsive, glassmorphic Material 3 interface.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-v3.19%2B-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-v3.10%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Architecture-Clean%20Architecture-009688?style=for-the-badge" alt="Clean Architecture" />
  <img src="https://img.shields.io/badge/UI/UX-Material%203%20Expressive-f39c12?style=for-the-badge" alt="Material 3" />
  <img src="https://img.shields.io/badge/Platform-Cross%20Platform-blueviolet?style=for-the-badge" alt="Platform" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License" />
</p>

---

## 📖 Project Overview

**DropNet** is a high-performance cross-platform local sharing utility built to showcase production-grade application architecture and network engineering. Instead of relying on centralized cloud endpoints, DropNet establishes direct, secure socket pipes over local area networks (LANs), allowing immediate transfers at maximum wireless hardware interface speeds.

### Key Capabilities
*   **Encrypted Transmission:** Native point-to-point network tunnels utilizing raw TCP sockets wrapped in a secure **TLS 1.3** pipeline.
*   **Dual-Discovery Subsystem:** Combines Multicast DNS (mDNS) with an automated high-availability UDP Datagram Broadcast socket to guarantee robust connectivity across complex local networks.
*   **Zero-Install Web Portal:** An embedded micro-web server allowing any guest device (iOS, macOS, Linux, etc.) to securely upload and download files via a local, PIN-gated browser dashboard without installing the client application.
*   **Dynamic UX Framework:** A sleek, animated Material 3 user interface featuring dynamic theme color seeds, responsive glassmorphism, and seamless concurrency.

---

## ⚙️ Core Architecture & Distributed System Design

DropNet operates entirely within a Local Area Network, demonstrating how low-level systems programming can be seamlessly integrated into cross-platform application frameworks.

### 1. Hybrid Network Discovery (mDNS & UDP Broadcasts)
Establishing peer-to-peer relationships on local subnets requires solid discovery logic. Because local subnets have diverse firewall layouts, DropNet employs a redundant, dual-channel presence daemon:
*   **mDNS Channel (Multicast):** On supportive runtimes, DropNet uses multicast DNS records via **Bonsoir** to announce and resolve service records over multicast address `224.0.0.251:5353`.
*   **UDP Fallback Socket (Unicast/Broadcast):** To bypass aggressive desktop sandbox rules (like Windows firewall policies), DropNet runs a concurrent socket listener using `RawDatagramSocket` on port `45454`. It broadcasts structured, cryptographically hashed JSON presence records to `255.255.255.255`.
*   **Presence Lifecycle:** Discovered peers are held in an in-memory registry. A continuous background prune daemon sweeps the table every 3 seconds, removing nodes that have not refreshed their heartbeat within a 12-second clock-skew window.

### 2. Encrypted Transmission Pipe & Custom Binary Framing
Once peers agree to a transfer, DropNet spins up a raw `SecureServerSocket` binding dynamically over port `45455`.
*   **Packet Fragmentation Mitigation:** Because TCP streams are continuous byte pipes with no native boundary indicators, reading raw JSON headers directly can result in fragmentation failures. To resolve this, DropNet implements a custom binary framing protocol:
    ```
    ┌─────────────────────────┬─────────────────────────┬─────────────────────────┬─────────────────────────┐
    │  Frame Length (4 Bytes) │     IV (16 Bytes)       │  SHA-256 Hash (32 Bytes)│ Ciphertext (Variable)   │
    │  (Big-Endian uint32)    │   (AES Initial Vector)  │   (Plaintext Integrity) │  (Encrypted Payload)    │
    └─────────────────────────┴─────────────────────────┴─────────────────────────┴─────────────────────────┘
    ```
*   **Flow Control:** Files are read and written sequentially in optimized **64KB byte chunks**. This prevents massive file payloads from overwhelming device memory, keeping buffer thresholds stable.

### 3. Asynchronous Concurrency & Thread Isolation
Dart operates on a single-threaded **Event Loop** architecture. Performing high-throughput disk reads, SHA-256 integrity hashing, and cryptographic decryption on the main loop would immediately starve the graphics pipeline, resulting in noticeable UI frame drops.
*   **Non-blocking I/O:** Sockets utilize low-level OS multiplexers (like `epoll` on Linux/Android and `kqueue` on iOS/macOS) to process events asynchronously without blocking execution.
*   **Multi-Threaded Isolates:** Heavy CPU computations—such as dynamic ZIP packaging, high-speed disk writes, and large block AES cryptosystems—are dynamically offloaded to dedicated Dart **Isolates**. These isolates run on separate OS threads with independent memory heaps, communicating back to the main UI thread via message passing (`SendPort`/`ReceivePort`).

### 4. Zero-Trust Security & Trust Framework
To guarantee absolute immunity from local eavesdropping or malicious client spoofing, DropNet enforces a decentralized trust framework:
*   **Dynamic TLS on LAN:** On boot, the `LocalTlsCertificateService` generates an ephemeral 2048-bit RSA key pair and a self-signed X.509 certificate specifying dynamic Subject Alternative Names (SANs) bound to the device's current active local network adapters.
*   **Fingerprint Pinning:** During the initial discovery exchange, peers advertise the SHA-256 fingerprint of their local X.509 certificate. When a socket connection is formed, the app intercepts the TLS handshake and programmatically verifies the peer's certificate against the advertised fingerprint. Mismatched connections are terminated instantly.
*   **Zero-Trust Pairing Codes:** Establishing trusted pairings utilizes a 6-digit interactive challenge code. Once verified, files are encrypted with **AES-CBC-256** using an ephemeral session key wrapped securely and transmitted via the TLS-secured socket.

### 5. Finite State Machine (FSM) Lifecycle
State changes follow a rigorous, mathematical state machine. Decoupled from visual render trees, it prevents race conditions (e.g., trying to write to a closed socket):

```
       ┌───────────────┐
       │     Idle      │
       └───────┬───────┘
               │ Discovery Triggered
               ▼
       ┌───────────────┐
       │  Connecting   │
       └───────┬───────┘
               │ Handshake & Fingerprint Match
               ▼
       ┌───────────────┐
       │    Pairing    │ <──────── (Pairing Code & Secret Verification)
       └───────┬───────┘
               │ Handshake Accepted
               ▼
       ┌───────────────┐
       │    Active     │ <──────── (Chunked flow-controlled byte streams)
       └───────┬───────┘
               ├─────────────────────────┐
               ▼ (Payload OK & Verified)   ▼ (Timeout / Integrity Fail / Cancel)
       ┌───────────────┐         ┌───────────────┐
       │   Completed   │         │    Failed     │
       └───────────────┘         └───────────────┘
               │                         │
               └───────────┬─────────────┘
                           ▼
               ┌───────────────────────┐
               │ Socket GC & Cleanup   │ (Sockets closed, files closed, memory freed)
               └───────────────────────┘
```

---

## 🛠 Tech Stack & Decoupled Rationale

DropNet’s tech stack is carefully curated to achieve optimal speed, UI response, and strict type safety:

| Technology | Role | Rationale |
| :--- | :--- | :--- |
| **Flutter** | Cross-Platform UI | Enables a single, high-performance C++ engine compiled codebase rendering at 60/120fps with absolute design consistency across mobile, desktop, and web. |
| **Dart** | Asynchronous Logic | Out-of-the-box support for Event-Driven loops, non-blocking asynchronous socket I/O, Streams, and robust Ahead-of-Time (AOT) compiler target compilation. |
| **Riverpod** | State Management | Ensures compile-safe, unidirectional data flows and modular reactive state binding across complex peer connections, active socket streams, and configurations. |
| **mDNS / Bonsoir** | Peer Discovery | Utilizes Zero-Configuration networking (ZeroConf) over multicast DNS (RFC 6762) to scan, resolve, and connect local devices automatically without IP entry. |
| **TCP Sockets** | Transfer Engine | Implements raw, point-to-point raw TCP sockets (RFC 793) with chunked byte-array streaming, ensuring flow-controlled, reliable local network delivery. |
| **Web Server (Shelf)** | Web Portal Engine | Hosts a micro HTTP server directly on the host device, enabling any browser-enabled client to download and upload files without installing the DropNet app. |

---

## 🤖 AI-Assisted Development & Engineering Workflow

DropNet was developed using a modern, synergistic engineering workflow. By utilizing AI pair-programmers to accelerate boilerplate scaffolding, dynamic UI transitions, and routine package layouts, full human attention was dedicated to the critical design bottlenecks: high-performance socket streaming, cryptographic X.509 handshake pipelines, state machine invariants, and native platform bindings. This hybrid human-AI partnership showcases how modern tools can dramatically accelerate the time-to-market of sophisticated, robust software architecture.

---

## 🌟 Premium UX & System Features

*   **Fluid Sonar Pulse Radar:** A custom-painted concentric scanning sonar visualizer accompanied by rotating vector lines simulating active LAN scanning. Features a dynamic green pulsing badge indicating "Ready to Receive".
*   **Device Identity Panel:** A gorgeous glassmorphic card displaying the active platform OS (Android, iOS, Windows, etc.), custom numeric tag, device name, **Device Manufacturer** details, and the active **Local IP Address** for easy LAN diagnostic checks.
*   **Zero-Trust Pairing System:** Offers pairing-code connection verification to establish cryptographic fingerprints between devices, ensuring absolute immunity to local man-in-the-middle attacks.
*   **Floating Transfer Queue Card:** A prominent, glowing, color-shifting banner that slides into view at the top of the Receive screen when files are waiting in the queue, providing tactile feedback.
*   **shelf-Powered Web Share Portal:** Run a micro-web server from your device, display a custom QR code, and allow friends to securely download or upload files through any browser.
*   **Granular Quick Save Modes:** Toggle between three security postures: *High Security* (manual approval for all transfers), *Trusted Auto-Save* (auto-save for favorited devices), or *Open Auto-Save* (auto-save for everyone) accompanied by interactive security explanation panels.
*   **CPU ABI & Compilation Target Diagnostics (Android):** Inspects the native APK container at runtime, analyzing whether the installed executable is running as an ABI-specific split target (e.g. `arm-v8a`, `arm-v7a`) or a unified `universal` binary.

---

## 📂 Project Architecture

The codebase follows Clean Architecture principles, ensuring strict separation of concerns, high modularity, and modular testability:

```
lib/
├── core/
│   ├── encryption/      # AES-256 chunk-level encryption, IV generation, key-wrapping
│   ├── networking/      # Socket Services, Web Shelf Servers, Discovery Engines
│   ├── platform/        # Native MethodChannels, MediaStore APIs, SAF filesystems
│   ├── security/        # 2048-bit RSA self-signed TLS generation, certificate validation
│   ├── state/           # AppState structures and Riverpod state controllers
│   └── utils/           # Platform normalizers, dialog generators, theme seeding
├── features/
│   ├── analytics/       # Storage analytics and historical transfer speeds
│   ├── history/         # Transfer logs database (history listings)
│   ├── home/            # Core shell containing navigation scaffolding
│   ├── onboarding/      # Welcome flow and OS runtime permission handshakes
│   ├── receive/         # Redesigned animated sonar, local IP displays, incoming queue
│   ├── send/            # Discovered devices radar, multi-file payload buffers
│   ├── settings/        # Dynamic colors, quick save modes, CPU ABI footer
│   └── web_mode/        # Shelf micro-server console & QR dialogs
├── models/              # Immutable data models representing peers, transfers, and system logs
└── widgets/             # High-fidelity shared widgets (Expressive dialogs, progress bars)
```

### 🔍 Key Implementation Files:
*   [tcp_transfer_service.dart](file:///d:/flutter_projects/dropnet/lib/core/networking/tcp_transfer_service.dart) - Handles all TLS sockets, dynamic file streaming, and chunk framing.
*   [discovery_service.dart](file:///d:/flutter_projects/dropnet/lib/core/networking/discovery_service.dart) - Manages UDP presence broadcasts and mDNS Bonsoir records.
*   [local_tls_certificate_service.dart](file:///d:/flutter_projects/dropnet/lib/core/security/local_tls_certificate_service.dart) - Generates self-signed certificates with dynamic Subject Alternative Names (SANs).
*   [web_server_service.dart](file:///d:/flutter_projects/dropnet/lib/core/networking/web_server_service.dart) - Houses the embedded web share server and PIN/cookie authorization.
*   [app_state.dart](file:///d:/flutter_projects/dropnet/lib/core/state/app_state.dart) - Unified Riverpod notifier orchestrating the core lifecycle.
*   [settings_screen.dart](file:///d:/flutter_projects/dropnet/lib/features/settings/settings_screen.dart) - Features settings, Quick Save modes, and native CPU ABI details.
*   [receive_screen.dart](file:///d:/flutter_projects/dropnet/lib/features/receive/receive_screen.dart) - Contains the redesigned sonar pulse, manufacturer details, and local IP diagnostics.
*   [MainActivity.kt](file:///d:/flutter_projects/dropnet/android/app/src/main/kotlin/com/dropnet/MainActivity.kt) - Houses the native Kotlin Platform MethodChannel to detect target architecture APK builds.

---

## 📦 Getting Started & Build Instructions

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.19+ recommended)
- [Dart SDK](https://dart.dev/get-started)
- Git

### 1. Clone the Repository
```bash
git clone https://github.com/arijeetdas/dropnet.git
cd dropnet
```

### 2. Fetch Dependencies
```bash
flutter pub get
```

### 3. Run Static Code Quality Check
```bash
flutter analyze
```

### 4. Run the Application
```bash
# Run in debug mode on your connected device
flutter run
```

### 5. Build for Android
```bash
# Build a universal release APK containing all ABIs
flutter build apk --release

# Build split APKS (separated by arm64-v8a, armeabi-v7a, x86_64)
flutter build apk --split-per-abi --release
```

---

## 🤝 How to Contribute & Raise Issues

Contributions make the open-source community an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

### Reporting a Bug or Suggesting a Feature
1. Navigate to the **Issues** tab of the repository.
2. Click **New Issue**.
3. Use a clear, descriptive title and provide detailed reproduction steps (for bugs) or clear system diagrams (for features).
4. Label the issue appropriately (e.g. `bug`, `enhancement`).

### Submission Workflow
1. **Fork** the Project.
2. Create your Feature Branch:
   ```bash
   git checkout -b feature/AmazingFeature
   ```
3. Commit your changes:
   ```bash
   git commit -m "feat: Add some AmazingFeature"
   ```
4. Push to the Branch:
   ```bash
   git push origin feature/AmazingFeature
   ```
5. Open a **Pull Request** targeting the main branch. Ensure all code passes `flutter analyze` with no lints or warnings.

---

## 🛡 License

Distributed under the **MIT License**. See `LICENSE` for more information.

---

## 👤 Developer & Contact

**Arijeet Das**  
*Computer Science & Engineering Undergrad*  

*   **GitHub:** [@arijeetdas](https://github.com/arijeetdas)
*   **LinkedIn:** [Arijeet Das](https://linkedin.com/in/arijeetdas)
*   **DropNet on Vibe Store:** [DropNet](https://vibe-labs.netlify.app/app.html?id=dropnet)
*   **Portfolio Website:** [Arijeet Das](https://arijeetdas-dev.vercel.app)
*   **Email:** arijeetdas900@gmail.com
