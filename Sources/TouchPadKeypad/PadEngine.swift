import Foundation
import AppKit

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
    private var landingOrder: [Int32] = []
    private var recentTouches: [Int32: (x: Double, y: Double, at: Date)] = [:]
    private let recentTouchTTL = 0.35
    private var firedKeyForFinger: [Int32: PadKey] = [:]
    
    private var lastFiredAt: [PadKey: Date] = [:]
    private let keyCooldown: TimeInterval = 0.25
    private var lastSliderSoundTime = Date.distantPast

    // Preloaded cached sounds for instant zero-latency feedback
    private static let clickSound: NSSound? = {
        let s = NSSound(named: "Tink")
        s?.volume = 0.7
        return s
    }()

    private static let popSound: NSSound? = {
        let s = NSSound(named: "Pop")
        return s
    }()

    private var lastFrame = Date.distantPast
    var framesReceived = 0
    private var touchWatchdog: Timer?

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

        // Active watchdog: instantly clears stuck hover states when Apple's touch driver goes silent on finger lift
        touchWatchdog = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.checkTouchTimeout()
        }
    }

    deinit {
        touchWatchdog?.invalidate()
    }

    private func checkTouchTimeout() {
        if !currentFingers.isEmpty, Date().timeIntervalSince(lastFrame) > 0.05 {
            currentFingers.removeAll()
            landingOrder.removeAll()
            sliderFingers.removeAll()
            firedKeyForFinger.removeAll()
            if state.keyUnderFinger != nil {
                state.keyUnderFinger = nil
            }
            if state.flashedKey != nil {
                state.flashedKey = nil
            }
        }
    }

    func handleFrame(_ touches: [MultitouchAdapter.Touch]) {
        framesReceived += 1
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
                if state.isControlHeld, state.running,
                   case .key(let key) = PadLayout.region(x: touch.x, y: touch.y),
                   firedKeyForFinger[touch.id] == nil {
                    
                    let now = Date()
                    if let lastTime = lastFiredAt[key], now.timeIntervalSince(lastTime) < keyCooldown {
                        break
                    }
                    
                    lastFiredAt[key] = now
                    firedKeyForFinger[touch.id] = key
                    pressKey(key)
                }
            }
        }

        if state.isControlHeld && state.running {
            for touch in touches {
                guard var drag = sliderFingers[touch.id] else { continue }
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
        landingOrder = landingOrder.filter { seen.contains($0) }
        updateMirrorUnderFinger()
    }

    private func applySlider(_ target: SliderDrag.Target, delta: Double) {
        let capped = max(-maxDeltaPerFrame, min(maxDeltaPerFrame, delta))
        guard capped != 0 else { return }
        
        let now = Date()
        if now.timeIntervalSince(lastSliderSoundTime) > 0.045 {
            if let sound = PadEngine.popSound {
                sound.stop()
                let speedFactor = Float(abs(capped) / maxDeltaPerFrame)
                if capped < 0 {
                    sound.volume = max(0.05, speedFactor * 0.25)
                } else {
                    sound.volume = max(0.15, speedFactor * 0.55)
                }
                sound.play()
            }
            lastSliderSoundTime = now
        }

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

    func handleControlChanged(_ held: Bool) {
        state.isControlHeld = held
        if !held {
            sliderFingers.removeAll()
            landingOrder.removeAll()
            firedKeyForFinger.removeAll()
            lastFiredAt.removeAll()
            currentFingers.removeAll()
            state.keyUnderFinger = nil
            state.flashedKey = nil
        }
    }

    func handlePrimaryClick() {
        guard state.isControlHeld, state.running else { return }
        guard let id = landingOrder.last,
              sliderFingers[id] == nil,
              firedKeyForFinger[id] == nil,
              let position = currentFingers[id] else { return }
        if case .key(let key) = PadLayout.region(x: position.x, y: position.y) {
            let now = Date()
            if let lastTime = lastFiredAt[key], now.timeIntervalSince(lastTime) < keyCooldown {
                return
            }
            lastFiredAt[key] = now
            firedKeyForFinger[id] = key
            pressKey(key)
        }
    }

    private func pressKey(_ key: PadKey) {
        KeyboardTyper.press(key)
        
        if let sound = PadEngine.clickSound {
            sound.stop()
            sound.play()
        }

        state.lastKey = key
        state.flashedKey = key
        // Ultra-short 0.03s flash so the border vanishes instantly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak state] in
            if state?.flashedKey == key { state?.flashedKey = nil }
        }
    }

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

    func housekeeping() {
        if Date().timeIntervalSince(lastFrame) > 0.05 {
            if state.keyUnderFinger != nil { state.keyUnderFinger = nil }
            if state.flashedKey != nil { state.flashedKey = nil }
            if !currentFingers.isEmpty {
                currentFingers.removeAll()
                landingOrder.removeAll()
                sliderFingers.removeAll()
                firedKeyForFinger.removeAll()
            }
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