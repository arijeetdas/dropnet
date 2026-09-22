import FlutterMacOS
import Foundation

/// Holds the dropnet/share_intent channel and pending-share state as a
/// singleton, independent of AppDelegate's own lifecycle, so it can be set up
/// from MainFlutterWindow (as early as every other plugin channel) while
/// still being reachable from AppDelegate's openFiles/open urls handlers.
final class ShareIntentBridge {
  static let shared = ShareIntentBridge()
  private init() {}

  private var channel: FlutterMethodChannel?
  private var pendingFilePaths: [String] = []
  private var pendingTexts: [String] = []

  func setUp(binaryMessenger: FlutterBinaryMessenger) {
    guard channel == nil else {
      return
    }
    let methodChannel = FlutterMethodChannel(
      name: "dropnet/share_intent",
      binaryMessenger: binaryMessenger
    )
    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "consumePendingSharedPayload":
        let files = self?.pendingFilePaths ?? []
        let texts = self?.pendingTexts ?? []
        self?.pendingFilePaths.removeAll()
        self?.pendingTexts.removeAll()
        result([
          "files": files,
          "texts": texts,
        ])
      case "consumePendingSharedFiles":
        let files = self?.pendingFilePaths ?? []
        self?.pendingFilePaths.removeAll()
        result(files)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = methodChannel
  }

  /// Returns true if `path` pointed at a real, existing file and was queued.
  func addFile(_ path: String) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return false
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      return false
    }
    if !pendingFilePaths.contains(trimmed) {
      pendingFilePaths.append(trimmed)
    }
    return true
  }

  func addText(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !pendingTexts.contains(trimmed) else {
      return
    }
    pendingTexts.append(trimmed)
  }

  func emitUpdate() {
    guard !pendingFilePaths.isEmpty || !pendingTexts.isEmpty else {
      return
    }
    channel?.invokeMethod(
      "sharedPayloadUpdated",
      arguments: [
        "files": pendingFilePaths,
        "texts": pendingTexts,
      ]
    )
  }
}
