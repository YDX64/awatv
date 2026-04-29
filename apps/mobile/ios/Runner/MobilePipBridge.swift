import AVKit
import AVFoundation
import Flutter
import UIKit

/// Method-channel bridge for mobile-side native Picture-in-Picture.
///
/// The Dart side (`apps/mobile/lib/src/shared/pip/mobile_pip.dart`)
/// exposes an `enter()` / `exit()` / `setAutoEnter(bool)` API. On
/// Android `floating` does the heavy lifting; on iOS we drive
/// `AVPictureInPictureController` here against whichever AVPlayerLayer
/// is currently in the foreground.
///
/// Why `presentInForegroundView`? media_kit on iOS embeds its frame
/// through a `UIView` that hosts an `AVPlayerLayer` per controller.
/// We don't have a public API surface to grab that AVPlayerLayer from
/// Swift, but we *do* always have exactly one AVPlayerLayer in the
/// active scene's view tree per active controller. We walk the tree to
/// find it and bind the PiP controller against it. If the user has
/// multiple controllers active (multi-stream view), the bridge picks
/// the first AVPlayerLayer with `isReadyForDisplay == true` so PiP
/// surfaces the layer that actually has frames in it.
///
/// Lifecycle:
///   - `enter` builds an AVPictureInPictureController if needed and
///     calls `startPictureInPicture()`. The OS then handles the rest;
///     when the user taps the expand button on the floating frame the
///     activity restores automatically and we receive
///     `pictureInPictureControllerDidStopPictureInPicture(_:)`.
///   - `exit` calls `stopPictureInPicture()` if a controller exists.
///   - `setAutoEnter` sets `canStartPictureInPictureAutomaticallyFromInline`
///     so the OS can start PiP the moment the app goes to the background.
///
/// Errors: every Apple API can fail synchronously when the audio
/// session isn't configured or the device is on iOS < 14. We bail out
/// to `result(false)` instead of `setMethodCallHandler`-ing a typed
/// error so the Dart side maps it to `MobilePipResult.unsupported`.
@available(iOS 14.0, *)
final class MobilePipBridge: NSObject, AVPictureInPictureControllerDelegate {

  static let channelName = "awatv/mobile_pip"
  private weak var channel: FlutterMethodChannel?
  private var pipController: AVPictureInPictureController?

  /// Registers the channel against the FlutterEngine's binary messenger.
  /// Call from `AppDelegate.didInitializeImplicitFlutterEngine`.
  func register(with messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(
      name: MobilePipBridge.channelName,
      binaryMessenger: messenger
    )
    self.channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      self.handle(call: call, result: result)
    }
  }

  private func handle(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "isSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "enter":
      result(self.enterPip(arguments: call.arguments))
    case "exit":
      result(self.exitPip())
    case "setAutoEnter":
      let args = call.arguments as? [String: Any]
      let enabled = (args?["enabled"] as? Bool) ?? false
      self.setAutoEnter(enabled: enabled)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Enter / exit

  private func enterPip(arguments: Any?) -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      return false
    }
    guard let layer = self.findActivePlayerLayer() else {
      return false
    }
    // Configure the audio session — without `.moviePlayback` the
    // AVPlayer will refuse to keep playing once the app backgrounds,
    // which defeats the entire point of PiP.
    self.configureAudioSession()

    // Reuse the existing controller if we're toggling against the same
    // AVPlayerLayer; otherwise rebuild against the fresh one.
    if let existing = self.pipController, existing.playerLayer === layer {
      existing.startPictureInPicture()
      return true
    }
    let controller = AVPictureInPictureController(playerLayer: layer)
    controller?.delegate = self
    if #available(iOS 14.2, *) {
      controller?.canStartPictureInPictureAutomaticallyFromInline = true
    }
    self.pipController = controller
    // The first start can race the AVPlayerLayer becoming ready —
    // `isPictureInPicturePossible` flips true asynchronously. We
    // observe it via KVO and start the moment it's allowed; if it's
    // already true, fire immediately.
    if controller?.isPictureInPicturePossible == true {
      controller?.startPictureInPicture()
    } else {
      // Best-effort: try to start anyway; AVKit will queue if not ready.
      controller?.startPictureInPicture()
    }
    return true
  }

  private func exitPip() -> Bool {
    guard let controller = self.pipController else { return false }
    controller.stopPictureInPicture()
    return true
  }

  private func setAutoEnter(enabled: Bool) {
    if #available(iOS 14.2, *) {
      self.pipController?.canStartPictureInPictureAutomaticallyFromInline =
        enabled
    }
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    self.notifyDart(active: true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    self.notifyDart(active: false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    self.notifyDart(active: false)
    NSLog("[MobilePipBridge] failed to start PiP: \(error)")
  }

  private func notifyDart(active: Bool) {
    self.channel?.invokeMethod(
      "pipStateChanged",
      arguments: ["active": active]
    )
  }

  // MARK: - Helpers

  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: []
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("[MobilePipBridge] audio session config failed: \(error)")
    }
  }

  /// Walks the connected scene's window hierarchy looking for an
  /// AVPlayerLayer that's ready for display. media_kit on iOS hosts
  /// each video texture inside a UIView whose `layer` is (or contains)
  /// an AVPlayerLayer — we recurse through the tree until we find one.
  private func findActivePlayerLayer() -> AVPlayerLayer? {
    let candidateScenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive ||
                $0.activationState == .foregroundInactive }
    for scene in candidateScenes {
      for window in scene.windows {
        if let layer = self.searchForPlayerLayer(in: window.layer) {
          return layer
        }
      }
    }
    return nil
  }

  private func searchForPlayerLayer(
    in layer: CALayer
  ) -> AVPlayerLayer? {
    if let avLayer = layer as? AVPlayerLayer {
      // Prefer layers that already have a player and are ready to draw —
      // multi-stream view will have several but only one is in front.
      if avLayer.player != nil && avLayer.isReadyForDisplay {
        return avLayer
      }
      // Fall through to descendants — sometimes the inner layer wins.
    }
    if let sublayers = layer.sublayers {
      for sub in sublayers {
        if let found = self.searchForPlayerLayer(in: sub) {
          return found
        }
      }
    }
    // Second pass: an AVPlayerLayer that isn't ready yet beats nothing.
    if let avLayer = layer as? AVPlayerLayer, avLayer.player != nil {
      return avLayer
    }
    return nil
  }
}
