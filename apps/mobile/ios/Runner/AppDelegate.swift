import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Strong reference to the PiP bridge so it survives the lifetime of
  /// the engine. The bridge keeps a weak reference back to the channel
  /// it registered, so dropping this property would silently disable
  /// Picture-in-Picture on iOS.
  private var mobilePipBridge: Any?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register the mobile-side PiP bridge against this engine's binary
    // messenger. iOS 14 is the minimum AVPictureInPictureController API
    // level we support; below that the bridge constructor is gated and
    // the channel simply returns false to every Dart-side call.
    if #available(iOS 14.0, *) {
      let bridge = MobilePipBridge()
      let registrar = engineBridge.pluginRegistry.registrar(
        forPlugin: "AwaTvMobilePipBridge"
      )
      if let messenger = registrar?.messenger() {
        bridge.register(with: messenger)
        self.mobilePipBridge = bridge
      }
    }
  }
}
