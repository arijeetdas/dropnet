import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private(set) var shareChannel: FlutterMethodChannel?
  private(set) var shortcutsChannel: FlutterMethodChannel?
  private var pendingSharedFilePaths: [String] = []
  private var pendingSharedTexts: [String] = []
  var pendingShortcut: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A cold launch via a Home Screen quick action arrives here rather than
    // through the scene delegate's shortcut callback (which only fires while
    // already running).
    if let shortcutItem = launchOptions?[UIApplication.LaunchOptionsKey.shortcutItem] as? UIApplicationShortcutItem {
      pendingShortcut = shortcutItem.type
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // UIScene lifecycle: the window/rootViewController aren't ready yet in
  // didFinishLaunchingWithOptions (SceneDelegate creates them afterwards), so
  // method channels are set up here instead, off the implicit engine's own
  // application-level messenger rather than a FlutterViewController.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let channel = FlutterMethodChannel(name: "dropnet/share_intent", binaryMessenger: messenger)
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

    let shortcutChannel = FlutterMethodChannel(name: "dropnet/app_shortcuts", binaryMessenger: messenger)
    shortcutChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "consumePendingShortcut":
        let shortcut = self?.pendingShortcut
        self?.pendingShortcut = nil
        result(shortcut)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    shortcutsChannel = shortcutChannel
  }

  // Called from SceneDelegate, which is where open-URL/user-activity events
  // land now that the app has adopted the UIScene lifecycle.
  func appendSharedPayload(url: URL) -> Bool {
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

  func emitSharedPayloadUpdated() {
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
