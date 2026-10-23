import Foundation
import CoreGraphics
import CoreAudio

func log(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    let url = URL(fileURLWithPath: "/tmp/TouchPadKeypad.log")
    let text = line
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(text.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.data(using: .utf8)!.write(to: url)
    }
}

// MARK: - Keyboard (FR3, FR4)

/// Posts keyboard events with the character set directly and all modifier flags cleared,
/// so the held Control never turns a digit into Control+digit and non-US keyboard
/// layouts still get the right character.
enum KeyboardTyper {
    static func press(_ key: PadKey) {
        if let character = key.typedCharacter {
            postUnicode(character)
        } else {
            switch key {
            case .backspace:
                postVirtualKey(0x33) // kVK_Delete
            case .ret:
                postVirtualKey(0x24) // kVK_Return
            default:
                break
            }
        }
    }

    private static func postUnicode(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        var chars = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        down.flags = []
        up.flags = []
        down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postVirtualKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

// MARK: - Volume (CoreAudio main volume on the default output device)

final class VolumeController {
    // Standard hardware/software output volume selector ('volv'). The previous
    // 'vvol' selector does not exist on most outputs, which made the volume strip dead.
    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func availability() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = volumeAddress
        let hasProperty = AudioObjectHasProperty(device, &address)
        guard hasProperty else { return false }
        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(device, &address, &settable)
        return settable.boolValue
    }

    func getVolume() -> Double? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = volumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr, size == MemoryLayout<Float32>.size else {
            return osascriptLevel()
        }
        return Double(value)
    }

    func setVolume(_ level: Double) {
        guard let device = defaultOutputDevice() else { return }
        var address = volumeAddress
        var value = Float32(max(0, min(1, level)))
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if status != noErr {
            // AppleScript fallback for outputs that lack hardware volume properties.
            runOSA("set volume output volume \(Int(value * 100))")
        }
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    private func osascriptLevel() -> Double? {
        let output = runOSA("output volume of (get volume settings)")?.trimmingCharacters(in: .whitespaces)
        guard let output, let percent = Int(output) else { return nil }
        return Double(percent) / 100.0
    }

    @discardableResult
    private func runOSA(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Input (microphone) volume — third strip in the reference design

final class InputVolumeController {
    private var workingElement: AudioObjectPropertyElement?

    private func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    private func address(for device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        if let element = workingElement {
            return AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
        }
        for element in [kAudioObjectPropertyElementMain, AudioObjectPropertyElement(1)] {
            var candidate = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &candidate) {
                workingElement = element
                return candidate
            }
        }
        return nil
    }

    func availability() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        guard var address = address(for: device) else { return false }
        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(device, &address, &settable)
        return settable.boolValue
    }

    func getVolume() -> Double? {
        guard let device = defaultInputDevice(), var address = address(for: device) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr, size == MemoryLayout<Float32>.size else { return nil }
        return Double(value)
    }

    func setVolume(_ level: Double) {
        guard let device = defaultInputDevice(), var address = address(for: device) else { return }
        var value = Float32(max(0, min(1, level)))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}

// MARK: - Brightness (private DisplayServices framework, built-in display only)

final class BrightnessController {
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightnessFn: GetBrightnessFn?
    private var setBrightnessFn: SetBrightnessFn?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let lib = dlopen(path, RTLD_LAZY) else { return }
        if let ptr = dlsym(lib, "DisplayServicesGetBrightness") {
            getBrightnessFn = unsafeBitCast(ptr, to: GetBrightnessFn.self)
        }
        if let ptr = dlsym(lib, "DisplayServicesSetBrightness") {
            setBrightnessFn = unsafeBitCast(ptr, to: SetBrightnessFn.self)
        }
    }

    func availability() -> Bool {
        guard getBrightnessFn != nil, setBrightnessFn != nil else { return false }
        return getBrightness() != nil
    }

    func getBrightness() -> Double? {
        guard let fn = getBrightnessFn else { return nil }
        var value = Float(0)
        let status = fn(CGMainDisplayID(), &value)
        guard status == 0 else { return nil }
        return Double(max(0, min(1, value)))
    }

    func setBrightness(_ level: Double) {
        guard let fn = setBrightnessFn else { return }
        _ = fn(CGMainDisplayID(), Float(max(0, min(1, level))))
    }
}
