import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Registered here, not in AppDelegate.applicationDidFinishLaunching: this
    // runs at the same point every other plugin channel does (as part of NIB
    // loading, before Dart's own bootstrap starts making platform channel
    // calls). Setting it up later meant the very first
    // consumePendingSharedPayload call on every cold launch failed with
    // MissingPluginException, since the channel didn't exist yet.
    ShareIntentBridge.shared.setUp(binaryMessenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
