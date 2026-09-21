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
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      super.scene(scene, openURLContexts: URLContexts)
      return
    }

    var unhandled: Set<UIOpenURLContext> = []
    var handledAny = false
    for context in URLContexts {
      if appDelegate.appendSharedPayload(url: context.url) {
        handledAny = true
      } else {
        unhandled.insert(context)
      }
    }
    if handledAny {
      appDelegate.emitSharedPayloadUpdated()
    }
    if !unhandled.isEmpty {
      super.scene(scene, openURLContexts: unhandled)
    }
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
