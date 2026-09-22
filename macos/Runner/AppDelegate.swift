import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    var changed = false
    for file in filenames {
      if ShareIntentBridge.shared.addFile(file) {
        changed = true
      }
    }
    if changed {
      ShareIntentBridge.shared.emitUpdate()
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    var changed = false
    for url in urls {
      if url.isFileURL {
        if ShareIntentBridge.shared.addFile(url.path) {
          changed = true
        }
        continue
      }

      ShareIntentBridge.shared.addText(url.absoluteString)
      changed = true
    }
    if changed {
      ShareIntentBridge.shared.emitUpdate()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
