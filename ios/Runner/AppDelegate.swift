import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var shareChannel: FlutterMethodChannel?
  private var pendingSharedFilePaths: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "dropnet/share_intent", binaryMessenger: controller.binaryMessenger)
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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let handled = appendSharedFile(url: url)
    if handled {
      emitSharedFilesUpdated()
      return true
    }
    return super.application(app, open: url, options: options)
  }

  private func appendSharedFile(url: URL) -> Bool {
    guard url.isFileURL else {
      return false
    }
    let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
      return false
    }
    guard FileManager.default.fileExists(atPath: path) else {
      return false
    }
    if !pendingSharedFilePaths.contains(path) {
      pendingSharedFilePaths.append(path)
    }
    return true
  }

  private func emitSharedFilesUpdated() {
    guard !pendingSharedFilePaths.isEmpty else {
      return
    }
    shareChannel?.invokeMethod("sharedFilesUpdated", arguments: pendingSharedFilePaths)
  }
}
