import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var shareChannel: FlutterMethodChannel?
  private var pendingSharedFilePaths: [String] = []
  private var pendingSharedTexts: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "dropnet/share_intent", binaryMessenger: controller.binaryMessenger)
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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let handled = appendSharedPayload(url: url)
    if handled {
      emitSharedPayloadUpdated()
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL,
      appendSharedPayload(url: url) {
      emitSharedPayloadUpdated()
      return true
    }

    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  private func appendSharedPayload(url: URL) -> Bool {
    if url.isFileURL {
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

    let text = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return false
    }
    if !pendingSharedTexts.contains(text) {
      pendingSharedTexts.append(text)
    }
    return true
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
}
