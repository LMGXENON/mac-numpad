import Foundation

/// One input engine: takes touch frames plus the Control state, decides which region each
/// finger is in, and emits actions (type a digit, change a level) and UI state (PRD).
final class PadEngine {
    let state: AppState
    let volume: VolumeController
    let brightness: BrightnessController

    private struct SliderDrag {
        enum Target { case volume, brightness }
        let target: Target
        var lastY: Double
    }

    private var sliderFingers: [Int32: SliderDrag] = [:]
    private var currentFingers: [Int32: (x: Double, y: Double)] = [:]
    private var landingOrder: [Int32] = []   // first landed → most recent landed
    // Short-lived positions kept after a finger lifts, for housekeeping sanity only.
    private var recentTouches: [Int32: (x: Double, y: Double, at: Date)] = [:]
    private let recentTouchTTL = 0.35
    /// A finger types at most once while it stays down: the touch landing fires the key,
    /// and the mouse event that follows the same touch (real click or synthesized tap)
    /// does not fire again.
    private var firedKeyForFinger: [Int32: PadKey] = [:]
    private var lastFrame = Date.distantPast
    var framesReceived = 0

    /// Faster touch frames produce smaller capped deltas; the cap stops a stray blast.
    let sliderSensitivity = 1.0
    let maxDeltaPerFrame = 0.05

    init(state: AppState, volume: VolumeController, brightness: BrightnessController) {
        self.state = state
        self.volume = volume
        self.brightness = brightness
        state.volumeAvailable = volume.availability()
        state.brightnessAvailable = brightness.availability()
        if let v = volume.getVolume() { state.volume = v }
        if let b = brightness.getBrightness() { state.brightness = b }
    }

    // MARK: Touch frames

    func handleFrame(_ touches: [MultitouchAdapter.Touch]) {
        framesReceived += 1
        if framesReceived <= 2 {
            let detail = touches.map { "id=\($0.id) x=\(String(format: "%.3f", $0.x)) y=\(String(format: "%.3f", $0.y))" }.joined(separator: ", ")
            log("touch frame #\(framesReceived): [\(detail)]")
        }
        lastFrame = Date()

        for touch in touches {
            recentTouches[touch.id] = (touch.x, touch.y, Date())
        }
        for touch in touches where currentFingers[touch.id] == nil {
            landingOrder.append(touch.id)
            switch PadLayout.region(x: touch.x, y: touch.y) {
            case .brightness:
                sliderFingers[touch.id] = SliderDrag(target: .brightness, lastY: touch.y)
            case .volume:
                sliderFingers[touch.id] = SliderDrag(target: .volume, lastY: touch.y)
            default:
                // Touch-sensitive keys (FR3): contact on a key types at once — no
                // click needed, and tap-to-click just works since a tap is a touch.
                if state.isControlHeld, state.running,
                   case .key(let key) = PadLayout.region(x: touch.x, y: touch.y) {
                    firedKeyForFinger[touch.id] = key
                    pressKey(key)
                }
            }
        }

        if state.isControlHeld && state.running {
            for touch in touches {
                guard var drag = sliderFingers[touch.id] else { continue }
                // FR5/FR6: change by distance moved; a touch alone changes nothing.
                let delta = (touch.y - drag.lastY) * sliderSensitivity
                drag.lastY = touch.y
                sliderFingers[touch.id] = drag
                applySlider(drag.target, delta: delta)
            }
        }

        let seen = Set(touches.map { $0.id })
        for id in currentFingers.keys where !seen.contains(id) {
            sliderFingers[id] = nil
            landingOrder.removeAll { $0 == id }
            firedKeyForFinger[id] = nil
        }
        currentFingers = Dictionary(uniqueKeysWithValues: touches.map { ($0.id, (x: $0.x, y: $0.y)) })
        // Keep only live fingers in landing order, so `last` is the most recently
        // landed one when a click arrives (PRD: click uses that finger).
        landingOrder = landingOrder.filter { seen.contains($0) }
        let stale = Date().addingTimeInterval(-recentTouchTTL * 2)
        for id in recentTouches.keys.sorted() {
            if let entry = recentTouches[id], entry.at < stale {
                recentTouches[id] = nil
            }
        }
        // Keep mirror highlighting fresh without per-frame churn.
        updateMirrorUnderFinger()
    }

    private func applySlider(_ target: SliderDrag.Target, delta: Double) {
        let capped = max(-maxDeltaPerFrame, min(maxDeltaPerFrame, delta))
        guard capped != 0 else { return }
        switch target {
        case .volume:
            guard state.volumeAvailable else { return }
            let next = max(0, min(1, state.volume + capped))
            if next != state.volume {
                volume.setVolume(next)
                state.volume = next
            }
        case .brightness:
            guard state.brightnessAvailable else { return }
            let next = max(0, min(1, state.brightness + capped))
            if next != state.brightness {
                brightness.setBrightness(next)
                state.brightness = next
            }
        }
    }

    // MARK: Control + clicks

    func handleControlChanged(_ held: Bool) {
        state.isControlHeld = held
        if !held {
            // Releasing Control mid-gesture cancels any slider drag and fires no key (PRD).
            sliderFingers.removeAll()
            landingOrder.removeAll()
            firedKeyForFinger.removeAll()
        }
    }

    /// Backup path: macOS only synthesizes a click when a touch was registered, so the
    /// touch landing normally fires the key. A click still types when Control was already
    /// held while the finger rested on the key (that landing happened while inactive).
    func handlePrimaryClick() {
        guard state.isControlHeld, state.running else { return }
        guard let id = landingOrder.last,
              sliderFingers[id] == nil,      // a strip finger can never press keys
              firedKeyForFinger[id] == nil,  // this touch already typed
              let position = currentFingers[id] else { return }
        if case .key(let key) = PadLayout.region(x: position.x, y: position.y) {
            firedKeyForFinger[id] = key
            pressKey(key)
        }
    }

    // MARK: Key presses

    private func pressKey(_ key: PadKey) {
        fire(key)
        log("key \(key.sentText)")
    }

    /// Fires a key into the frontmost app with no modifiers attached (FR3, FR4).
    private func fire(_ key: PadKey) {
        KeyboardTyper.press(key)
        state.lastKey = key
        state.flashedKey = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak state] in
            if state?.flashedKey == key { state?.flashedKey = nil }
        }
    }

    // MARK: Mirror + housekeeping

    /// Highlights the key under a finger; writes only on change so sixty-per-second
    /// touch frames never churn SwiftUI (this is what kept clicks feeling delayed).
    private func updateMirrorUnderFinger() {
        var found: PadKey?
        if state.running {
            for id in landingOrder.reversed() {
                guard sliderFingers[id] == nil, let pos = currentFingers[id] else { continue }
                if case .key(let key) = PadLayout.region(x: pos.x, y: pos.y) {
                    found = key
                    break
                }
            }
        }
        if state.keyUnderFinger != found {
            state.keyUnderFinger = found
        }
    }

    /// Called on a timer: clears stale mirror highlights if touch frames stopped arriving,
    /// and follows the real system levels when they change by other means.
    func housekeeping() {
        if Date().timeIntervalSince(lastFrame) > 0.6 {
            if state.keyUnderFinger != nil { state.keyUnderFinger = nil }
            recentTouches.removeAll()
        }
        refreshLevels()
    }

    private func refreshLevels() {
        let volumeDragActive = sliderFingers.values.contains { $0.target == .volume }
        let brightnessDragActive = sliderFingers.values.contains { $0.target == .brightness }

        if !volumeDragActive, let v = volume.getVolume() {
            let clamped = max(0, min(1, v))
            if abs(clamped - state.volume) > 0.0005 || !state.volumeAvailable {
                state.volume = clamped
            }
            state.volumeAvailable = true
        } else if !volumeDragActive {
            state.volumeAvailable = false
        }

        if !brightnessDragActive, let b = brightness.getBrightness() {
            let clamped = max(0, min(1, b))
            if abs(clamped - state.brightness) > 0.0005 || !state.brightnessAvailable {
                state.brightness = clamped
            }
            state.brightnessAvailable = true
        } else if !brightnessDragActive {
            state.brightnessAvailable = false
        }
    }
}
