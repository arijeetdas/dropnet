import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var shareChannel: FlutterMethodChannel?
  private var pendingSharedFilePaths: [String] = []
  private var pendingSharedTexts: [String] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if let flutterViewController = NSApp.windows.first?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "dropnet/share_intent", binaryMessenger: flutterViewController.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "consumePendingSharedPayload":
          let files = self?.pendingSharedFilePaths ?? []
          let texts = self?.pendingSharedTexts ?? []
          self?.pendingSharedFilePaths.removeAll()
          self?.pendingSharedTexts.removeAll()
          result([
            "files": files,
            "texts": texts,
          ])
        case "consumePendingSharedFiles":
          let files = self?.pendingSharedFilePaths ?? []
          self?.pendingSharedFilePaths.removeAll()
          result(files)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      shareChannel = channel
    }
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    var changed = false
    for file in filenames {
      let path = file.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !path.isEmpty else {
        continue
      }
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
        if !pendingSharedFilePaths.contains(path) {
          pendingSharedFilePaths.append(path)
          changed = true
        }
      }
    }
    if changed {
      emitSharedPayloadUpdated()
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    var changed = false
    for url in urls {
      if url.isFileURL {
        let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
          continue
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
          if !pendingSharedFilePaths.contains(path) {
            pendingSharedFilePaths.append(path)
            changed = true
          }
        }
        continue
      }

      let text = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty {
        continue
      }
      if !pendingSharedTexts.contains(text) {
        pendingSharedTexts.append(text)
        changed = true
      }
    }
    if changed {
      emitSharedPayloadUpdated()
    }
  }

  private func emitSharedPayloadUpdated() {
    guard !pendingSharedFilePaths.isEmpty || !pendingSharedTexts.isEmpty else {
      return
    }
    shareChannel?.invokeMethod(
      "sharedPayloadUpdated",
      arguments: [
        "files": pendingSharedFilePaths,
        "texts": pendingSharedTexts,
      ]
    )
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
