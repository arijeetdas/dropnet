import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var shareChannel: FlutterMethodChannel?
  private var pendingSharedFilePaths: [String] = []

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if let flutterViewController = NSApp.windows.first?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "dropnet/share_intent", binaryMessenger: flutterViewController.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "consumePendingSharedFiles" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let files = self?.pendingSharedFilePaths ?? []
        self?.pendingSharedFilePaths.removeAll()
        result(files)
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
      shareChannel?.invokeMethod("sharedFilesUpdated", arguments: pendingSharedFilePaths)
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
