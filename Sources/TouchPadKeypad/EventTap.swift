import Foundation
import CoreGraphics

/// Active CGEventTap watching modifier changes and mouse/scroll events (PRD technical approach).
/// While Control is held it drops move, click and scroll events so the pointer freezes and
/// nothing leaks into other apps (FR2). If the tap times out it is re-enabled; if the app
/// quits the tap disappears and the trackpad behaves normally (safety).
final class EventTapController {
    static private(set) var shared: EventTapController?

    var onControlChanged: ((Bool) -> Void)?
    var onPrimaryClick: (() -> Void)?
    var onPrimaryClickUp: (() -> Void)? // Notifies when the physical click or touch lifts up

    private(set) var isControlHeld = false

    /// Called by the tap callback (same file) to record the modifier state.
    func setControlHeld(_ held: Bool) {
        isControlHeld = held
        if held {
            swallowedCount = 0
            log("Control ON — trackpad is a keypad")
        } else {
            log("Control OFF — trackpad idle (swallowed \(swallowedCount) pointer/scroll events)")
        }
        onControlChanged?(held)
    }
    private(set) var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?
    /// Set by the menu-bar Pause or by sleep/lock; paused taps pass everything through.
    var isPaused = false

    private(set) var started = false
    private(set) var swallowedCount = 0

    /// Called by the tap callback (same file) to count hidden pointer/scroll events.
    func noteSwallowed() {
        swallowedCount += 1
    }

    init() {
        EventTapController.shared = self
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard !started else { return true }
        var mask: CGEventMask = 0
        for type: CGEventType in [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel,
            .flagsChanged
        ] {
            mask |= CGEventMask(1) << type.rawValue
        }

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) else { return false }

        port = created
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)

        // macOS can switch a tap off if it is slow (PRD); keep nudging it awake.
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let port = self.port, !CFEventTapIsEnabled(port) else { return }
            CGEvent.tapEnable(tap: port, enable: true)
            log("Event tap was disabled; re-enabled")
        }
        started = true
        log("Event tap started")
        return true
    }

    func stop() {
        guard started, let tappedPort = port else { return }
        CGEvent.tapEnable(tap: tappedPort, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        runLoopSource = nil
        port = nil
        watchdog?.invalidate()
        watchdog = nil
        started = false
    }

    /// Swallowing rule: only while the feature is running and Control is held.
    func shouldSwallow() -> Bool {
        isControlHeld && !isPaused
    }
}

private func CFEventTapIsEnabled(_ port: CFMachPort) -> Bool {
    CGEvent.tapIsEnabled(tap: port)
}

private let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    guard let controller = EventTapController.shared else {
        return Unmanaged.passUnretained(event)
    }

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let port = controller.port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)

    case .flagsChanged:
        let held = event.flags.contains(.maskControl)
        if held != controller.isControlHeld {
            controller.setControlHeld(held)
        }
        return Unmanaged.passUnretained(event)

    default:
        break
    }

    if controller.shouldSwallow() {
        if type == .leftMouseDown {
            controller.onPrimaryClick?()
            controller.noteSwallowed()
        } else if type == .leftMouseUp {
            controller.onPrimaryClickUp?()
            controller.noteSwallowed()
        } else {
            controller.noteSwallowed()
        }
        // No move, click or scroll reaches another app while active.
        return nil
    }
    return Unmanaged.passUnretained(event)
}