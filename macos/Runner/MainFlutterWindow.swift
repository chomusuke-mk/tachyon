import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowStateChannel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  private var windowObservers: [NSObjectProtocol] = []

  private var isMinimizedState = false
  private var isFocusedState = true
  private var isHiddenToTrayState = false

  private var trayIsPlaying = false
  private var trayIsShuffled = false
  private var trayHasTrack = false
  private var trayTooltip = "Tachyon"
  private var trayPlayLabel = "Play"
  private var trayPauseLabel = "Pause"
  private var trayNextLabel = "Next track"
  private var trayPreviousLabel = "Previous track"
  private var trayShuffleLabel = "Shuffle"
  private var trayShowAppLabel = "Show Tachyon"
  private var trayQuitLabel = "Quit"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupWindowStateChannel(flutterViewController)
    observeWindowNotifications()

    super.awakeFromNib()
  }

  deinit {
    for observer in windowObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    removeTrayItem()
  }

  private func setupWindowStateChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "dev.chomusuke.tachyon/window_state",
      binaryMessenger: controller.engine.binaryMessenger
    )
    windowStateChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getWindowState":
        result(self.buildWindowStateMap())
      case "isMinimized":
        result(self.isMinimizedState)
      case "minimize":
        self.miniaturize(nil)
        result(nil)
      case "toggleMaximize":
        self.zoom(nil)
        result(nil)
      case "closeWindow":
        self.removeTrayItem()
        (NSApp.delegate as? AppDelegate)?.isHiddenToTray = false
        self.performClose(nil)
        result(nil)
      case "startWindowDrag":
        if let event = NSApp.currentEvent {
          self.performDrag(with: event)
        }
        result(nil)
      case "enterBackgroundMode":
        self.isHiddenToTrayState = true
        (NSApp.delegate as? AppDelegate)?.isHiddenToTray = true
        self.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        self.emitWindowStateChanged()
        result(nil)
      case "restoreFromBackground":
        self.isHiddenToTrayState = false
        self.isMinimizedState = false
        self.isFocusedState = true
        (NSApp.delegate as? AppDelegate)?.isHiddenToTray = false
        NSApp.setActivationPolicy(.regular)
        if self.isMiniaturized {
          self.deminiaturize(nil)
        }
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.emitWindowStateChanged()
        result(nil)
      case "updateTrayState":
        if let args = call.arguments as? [String: Any] {
          self.updateTray(args)
        }
        result(nil)
      case "setBackgroundButtonTooltip":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func observeWindowNotifications() {
    let center = NotificationCenter.default
    windowObservers.append(
      center.addObserver(
        forName: NSWindow.didMiniaturizeNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        guard let self = self, !self.isHiddenToTrayState else { return }
        self.isMinimizedState = true
        self.emitWindowStateChanged()
      }
    )
    windowObservers.append(
      center.addObserver(
        forName: NSWindow.didDeminiaturizeNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        guard let self = self, !self.isHiddenToTrayState else { return }
        self.isMinimizedState = false
        self.emitWindowStateChanged()
      }
    )
    windowObservers.append(
      center.addObserver(
        forName: NSWindow.didBecomeKeyNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        guard let self = self, !self.isHiddenToTrayState else { return }
        self.isFocusedState = true
        self.emitWindowStateChanged()
      }
    )
    windowObservers.append(
      center.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        guard let self = self, !self.isHiddenToTrayState else { return }
        self.isFocusedState = false
        self.emitWindowStateChanged()
      }
    )
  }

  private func buildWindowStateMap() -> [String: Any] {
    return [
      "hasNativeHeaderBar": false,
      "hasSystemDecorations": false,
      "isMinimized": isMinimizedState,
      "isFocused": isFocusedState,
      "isMaximized": isZoomed,
      "isHiddenToTray": isHiddenToTrayState,
    ]
  }

  private func emitWindowStateChanged() {
    windowStateChannel?.invokeMethod(
      "onWindowStateChanged",
      arguments: buildWindowStateMap()
    )
  }

  private func emitTrayAction(_ action: String) {
    windowStateChannel?.invokeMethod("onTrayAction", arguments: action)
  }

  private func updateTray(_ args: [String: Any]) {
    let visible = (args["visible"] as? Bool) ?? false
    trayIsPlaying = (args["isPlaying"] as? Bool) ?? false
    trayIsShuffled = (args["isShuffled"] as? Bool) ?? false
    trayHasTrack = (args["hasTrack"] as? Bool) ?? false
    if let s = args["tooltip"] as? String, !s.isEmpty { trayTooltip = s }
    if let s = args["playLabel"] as? String, !s.isEmpty { trayPlayLabel = s }
    if let s = args["pauseLabel"] as? String, !s.isEmpty { trayPauseLabel = s }
    if let s = args["nextLabel"] as? String, !s.isEmpty { trayNextLabel = s }
    if let s = args["previousLabel"] as? String, !s.isEmpty {
      trayPreviousLabel = s
    }
    if let s = args["shuffleLabel"] as? String, !s.isEmpty {
      trayShuffleLabel = s
    }
    if let s = args["showAppLabel"] as? String, !s.isEmpty {
      trayShowAppLabel = s
    }
    if let s = args["quitLabel"] as? String, !s.isEmpty { trayQuitLabel = s }

    if !visible {
      removeTrayItem()
      return
    }

    let item: NSStatusItem
    if let existing = statusItem {
      item = existing
    } else {
      item = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.squareLength
      )
      if let button = item.button {
        if let appIcon = NSApp.applicationIconImage?.copy() as? NSImage {
          appIcon.size = NSSize(width: 18, height: 18)
          button.image = appIcon
        } else {
          button.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Tachyon"
          )
        }
        button.target = self
        button.action = #selector(onTrayButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      }
      statusItem = item
    }

    item.button?.toolTip = trayTooltip
  }

  private func removeTrayItem() {
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
    }
  }

  @objc private func onTrayButtonClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else {
      emitTrayAction("restore")
      return
    }
    if event.type == .rightMouseUp {
      showTrayMenu()
    } else {
      emitTrayAction("restore")
    }
  }

  private func showTrayMenu() {
    guard let item = statusItem else { return }
    let menu = NSMenu()

    let playPauseTitle = trayIsPlaying ? trayPauseLabel : trayPlayLabel
    let playPauseItem = NSMenuItem(
      title: playPauseTitle,
      action: #selector(onMenuPlayPause),
      keyEquivalent: ""
    )
    playPauseItem.target = self
    playPauseItem.isEnabled = trayHasTrack
    menu.addItem(playPauseItem)

    let nextItem = NSMenuItem(
      title: trayNextLabel,
      action: #selector(onMenuNext),
      keyEquivalent: ""
    )
    nextItem.target = self
    nextItem.isEnabled = trayHasTrack
    menu.addItem(nextItem)

    let prevItem = NSMenuItem(
      title: trayPreviousLabel,
      action: #selector(onMenuPrevious),
      keyEquivalent: ""
    )
    prevItem.target = self
    prevItem.isEnabled = trayHasTrack
    menu.addItem(prevItem)

    let shuffleTitle = trayIsShuffled
      ? "• \(trayShuffleLabel)"
      : trayShuffleLabel
    let shuffleItem = NSMenuItem(
      title: shuffleTitle,
      action: #selector(onMenuShuffle),
      keyEquivalent: ""
    )
    shuffleItem.target = self
    shuffleItem.state = .off
    menu.addItem(shuffleItem)

    menu.addItem(NSMenuItem.separator())

    let showItem = NSMenuItem(
      title: trayShowAppLabel,
      action: #selector(onMenuShowApp),
      keyEquivalent: ""
    )
    showItem.target = self
    menu.addItem(showItem)

    let quitItem = NSMenuItem(
      title: trayQuitLabel,
      action: #selector(onMenuQuit),
      keyEquivalent: ""
    )
    quitItem.target = self
    menu.addItem(quitItem)

    item.menu = menu
    item.button?.performClick(nil)
    item.menu = nil
  }

  @objc private func onMenuPlayPause() { emitTrayAction("playPause") }
  @objc private func onMenuNext() { emitTrayAction("next") }
  @objc private func onMenuPrevious() { emitTrayAction("previous") }
  @objc private func onMenuShuffle() { emitTrayAction("toggleShuffle") }
  @objc private func onMenuShowApp() { emitTrayAction("restore") }
  @objc private func onMenuQuit() { emitTrayAction("quit") }
}
