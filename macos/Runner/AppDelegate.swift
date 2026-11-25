import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var isHiddenToTray: Bool = false

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    return !isHiddenToTray
  }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool {
    return true
  }
}
