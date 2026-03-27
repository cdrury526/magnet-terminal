import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(
      x: self.frame.origin.x,
      y: self.frame.origin.y,
      width: 1200,
      height: 800
    )
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    // Full-size content view: Flutter content extends behind the title bar.
    // The title bar becomes transparent and the traffic light buttons overlay
    // the Flutter content. Our AppShell widget reserves space for them.
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true

    // Set a dark background to prevent white flash on launch
    self.backgroundColor = NSColor(red: 0.051, green: 0.067, blue: 0.090, alpha: 1.0)

    // Minimum window size for usable terminal
    self.minSize = NSSize(width: 480, height: 320)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
