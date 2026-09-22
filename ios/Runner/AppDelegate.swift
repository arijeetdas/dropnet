import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  static let appGroupId = "group.com.dropnet.shared"
  private static let shareExtensionDefaultsKey = "pendingShareExtensionItems"

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

    // Defensive: the Share Extension normally hands off via the dropnet://
    // URL scheme (see SceneDelegate), but a cold launch straight from the
    // Share Sheet's "Open DropNet" flow can also deliver the App Group data
    // without ever routing through that URL, so it's checked here too.
    _ = importFromShareExtension()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Reads whatever the Share Extension staged in the App Group container
  /// (see ShareExtension/ShareViewController.swift), merges it into the same
  /// pending list URL-based sharing uses, and clears it so it isn't imported
  /// twice. Returns whether anything was found.
  @discardableResult
  func importFromShareExtension() -> Bool {
    guard let defaults = UserDefaults(suiteName: Self.appGroupId) else {
      return false
    }
    guard
      let payload = defaults.dictionary(forKey: Self.shareExtensionDefaultsKey),
      !payload.isEmpty
    else {
      return false
    }
    defaults.removeObject(forKey: Self.shareExtensionDefaultsKey)

    var changed = false
    for path in (payload["files"] as? [String] ?? []) {
      if appendSharedFilePath(path) {
        changed = true
      }
    }
    for text in (payload["texts"] as? [String] ?? []) {
      appendSharedText(text)
      changed = true
    }
    return changed
  }

  /// The Share Extension's staging directory inside the App Group container,
  /// so Dart's cache-cleanup sweep can treat it exactly like any other
  /// transient temp/cache location instead of it accumulating forever.
  static func shareExtensionInboxPath() -> String? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
      .appendingPathComponent("share_inbox", isDirectory: true)
      .path
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
      case "getShareExtensionInboxPath":
        result(AppDelegate.shareExtensionInboxPath())
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
      return appendSharedFilePath(url.path)
    }
    appendSharedText(url.absoluteString)
    return true
  }

  @discardableResult
  private func appendSharedFilePath(_ rawPath: String) -> Bool {
    let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
      return false
    }
    if !pendingSharedFilePaths.contains(path) {
      pendingSharedFilePaths.append(path)
    }
    return true
  }

  private func appendSharedText(_ rawText: String) {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !pendingSharedTexts.contains(text) else {
      return
    }
    pendingSharedTexts.append(text)
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
