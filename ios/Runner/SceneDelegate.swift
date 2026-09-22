import Flutter
import UIKit

// Required by iOS 26+/27's UIScene lifecycle enforcement. AppDelegate no
// longer receives application(_:open:), application(_:continue:…) or
// application(_:performActionFor:…) once a scene delegate is registered —
// those events land here instead, per Flutter's migration guide:
// https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // A cold launch straight from the Share Extension's hand-off delivers its
    // URL here, as part of the initial connection, rather than through
    // openURLContexts below (that's only for a URL arriving while the scene
    // is already connected).
    _ = handleURLContexts(connectionOptions.urlContexts)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    let unhandled = handleURLContexts(URLContexts)
    if !unhandled.isEmpty {
      super.scene(scene, openURLContexts: unhandled)
    }
  }

  /// Returns whichever contexts weren't recognized as either the Share
  /// Extension's hand-off signal or an importable file/link, so the caller
  /// can still forward those to Flutter/other plugins.
  private func handleURLContexts(_ contexts: Set<UIOpenURLContext>) -> Set<UIOpenURLContext> {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return contexts
    }

    var unhandled: Set<UIOpenURLContext> = []
    var handledAny = false
    for context in contexts {
      let url = context.url
      if url.scheme == "dropnet", url.host == "share-extension-import" {
        if appDelegate.importFromShareExtension() {
          handledAny = true
        }
        continue
      }
      if appDelegate.appendSharedPayload(url: url) {
        handledAny = true
      } else {
        unhandled.insert(context)
      }
    }
    if handledAny {
      appDelegate.emitSharedPayloadUpdated()
    }
    return unhandled
  }

  override func scene(
    _ scene: UIScene,
    continue userActivity: NSUserActivity
  ) {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = userActivity.webpageURL,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate,
      appDelegate.appendSharedPayload(url: url) {
      appDelegate.emitSharedPayloadUpdated()
      return
    }
    super.scene(scene, continue: userActivity)
  }

  override func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    let appDelegate = UIApplication.shared.delegate as? AppDelegate
    appDelegate?.shortcutsChannel?.invokeMethod("shortcutTapped", arguments: shortcutItem.type)
    completionHandler(true)
  }
}
