import AppKit
import ApplicationServices
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let volume = VolumeController()
    let brightness = BrightnessController()
    lazy var engine = PadEngine(state: state, volume: volume, brightness: brightness)
    lazy var multitouch = MultitouchAdapter()
    lazy var tap = EventTapController()
    lazy var mirror = MirrorWindowController(state: state)

    var statusItem: NSStatusItem?
    var statusTimer: Timer?
    var booleanObservers: [NSObjectProtocol] = []
    var permissionsRequested = false
    var pausedByUser = false
    private var warnedNoTouchFrames = false
    private var engineRunningSince = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let problem = MultitouchAdapter.validateLayout() {
            log("ABORT: touch struct layout problem: \(problem)")
        }

        multitouch.onFrame = { [weak self] touches in self?.engine.handleFrame(touches) }
        tap.onControlChanged = { [weak self] held in self?.engine.handleControlChanged(held) }
        tap.onPrimaryClick = { [weak self] in self?.engine.handlePrimaryClick() }

        observeSystemStates()
        setupMenu()
        mirror.show()
        requestPermissionsIfNeeded()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
        log("TouchPad Keypad launched (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        tap.stop()
        multitouch.stop()
        return .terminateNow
    }

    // MARK: Engine lifecycle

    func tick() {
        // AXIsProcessTrusted as a second opinion: on some macOS builds CGPreflight
        // lags after a grant is made in System Settings.
        let ax = CGPreflightPostEventAccess() || AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        if ax != state.accessibilityGranted || im != state.inputMonitoringGranted {
            log("Permission state: accessibility=\(ax) inputMonitoring=\(im)")
        }
        state.accessibilityGranted = ax
        state.inputMonitoringGranted = im

        let engineRunning = tap.started && multitouch.started
        let shouldRun = state.running && !pausedByUser

        if shouldRun && !engineRunning {
            tap.isPaused = false
            let tapStarted = tap.start()
            let touchStarted = multitouch.start()
            warnedNoTouchFrames = false
            engineRunningSince = Date()
            engine.framesReceived = 0
            if tapStarted && touchStarted {
                log("Engine running: event tap + touch frames active")
            } else {
                log("Engine start incomplete: tap=\(tapStarted) touch=\(touchStarted) (grant permissions and I will retry)")
            }
        } else if !shouldRun && engineRunning {
            tap.stop()
            multitouch.stop()
            log("Engine stopped (paused or permissions missing)")
        }
        tap.isPaused = pausedByUser || state.suspendedBySystem || !state.isEnabled

        if engineRunning, engine.framesReceived == 0,
           Date().timeIntervalSince(engineRunningSince) > 4, !warnedNoTouchFrames {
            warnedNoTouchFrames = true
            log("WARNING: 4s since start and no touch frames received — MultitouchSupport stream silent")
        }

        engine.housekeeping()
    }

    func requestPermissionsIfNeeded() {
        guard !permissionsRequested else { return }
        permissionsRequested = true
        
        // Force the native macOS Accessibility system prompt dialog for new users
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(options)
        if !axTrusted {
            log("Accessibility not granted — system prompt triggered")
        }
        
        // Force the native macOS Input Monitoring system prompt dialog
        if !CGPreflightListenEventAccess() {
            log("Input Monitoring not granted — requesting")
            CGRequestListenEventAccess()
        }
    }

    // MARK: Sleep, wake, lock (safety: the app pauses itself)

    private func observeSystemStates() {
        let center = NSWorkspace.shared.notificationCenter
        booleanObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.state.suspendedBySystem = true })
        booleanObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.state.suspendedBySystem = false })
        booleanObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.state.suspendedBySystem = true })
        booleanObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.state.suspendedBySystem = false })
    }

    // MARK: Menu bar (FR8)

    func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "hand.point.up.left",
            accessibilityDescription: "TouchPad Keypad"
        )
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "TouchPad Keypad", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit TouchPad Keypad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc func togglePause() {
        pausedByUser.toggle()
        state.isEnabled = !pausedByUser
        if let toggle = statusItem?.menu?.items.first(where: { $0.action == #selector(togglePause) }) {
            toggle.title = pausedByUser ? "Resume" : "Pause"
        }
        tick()
        log(pausedByUser ? "App paused from menu bar" : "App resumed from menu bar")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()