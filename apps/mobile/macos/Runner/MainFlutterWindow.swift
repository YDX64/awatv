import Cocoa
import FlutterMacOS

/// Initial size when the app boots before Hive-saved geometry kicks in.
/// Matches the default in `desktop_window.dart` so the visible jump is
/// minimal: native shows the window at 1280x800, Flutter then optionally
/// resizes to whatever was persisted.
private let kDefaultWidth: CGFloat = 1280
private let kDefaultHeight: CGFloat = 800

/// Minimum window size — anything narrower hides the side rail without
/// the adaptive shell looking great. 800x600 is the floor we tested.
private let kMinWidth: CGFloat = 800
private let kMinHeight: CGFloat = 600

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // Configure the window before mounting Flutter so the very first
    // frame Flutter paints already sits behind the hidden titlebar with
    // the traffic-light buttons inset.
    self.styleMask = [
      .titled,
      .closable,
      .miniaturizable,
      .resizable,
      .fullSizeContentView,
    ]
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = false
    self.minSize = NSSize(width: kMinWidth, height: kMinHeight)

    // Inset the traffic-light buttons so they line up vertically with
    // our 32pt chrome bar and feel "tucked in" rather than floating in
    // the corner.
    let buttons: [NSWindow.ButtonType] = [
      .closeButton,
      .miniaturizeButton,
      .zoomButton,
    ]
    for button in buttons {
      if let view = self.standardWindowButton(button) {
        view.translatesAutoresizingMaskIntoConstraints = true
        // Move each button 4pt right and 8pt down from the system
        // default (which is flush with top-left at ~7pt).
        var frame = view.frame
        frame.origin.x += 4
        frame.origin.y -= 4
        view.frame = frame
      }
    }

    // Kick the initial size to 1280x800 centered on the active screen.
    if let screen = self.screen ?? NSScreen.main {
      let rect = NSRect(
        x: screen.frame.midX - kDefaultWidth / 2,
        y: screen.frame.midY - kDefaultHeight / 2,
        width: kDefaultWidth,
        height: kDefaultHeight
      )
      self.setFrame(rect, display: true)
    } else {
      var frame = self.frame
      frame.size = NSSize(width: kDefaultWidth, height: kDefaultHeight)
      self.setFrame(frame, display: true)
    }

    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
