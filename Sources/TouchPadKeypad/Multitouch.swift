import Foundation

/// Adapter around Apple's private MultitouchSupport framework (PRD technical approach).
/// Kept small on purpose: if a macOS update changes the framework, only this file changes.
///
/// Verified ABI (Nathan Vander Wilt's TouchSynthesis MultitouchSupport.h, the standard
/// reference for this private framework): devices receive contact frames only after
/// MTRegisterContactFrameCallback, and MTDeviceStart(dev, 0) — NOT a callback argument —
/// starts delivery. Records are 96 bytes; normalized x/y live at bytes 32/36 and the
/// persistent finger ID at byte 24.
final class MultitouchAdapter {
    struct Touch {
        let id: Int32
        let x: Double   // normalized 0…1, left→right
        let y: Double   // normalized 0…1, bottom→top
    }

    // Swift-side model of the C MTTouch record, used to validate the byte offsets
    // we read touches from. The callback itself receives raw memory because
    // @convention(c) cannot take a pointer to a Swift-defined struct.
    private struct MTTouch {
        var frame: Int32        // 0
        var padding: Int32      // 4 (alignment gap before the double)
        var timestamp: Double   // 8
        var pathIndex: Int32    // 16
        var state: UInt32       // 20 (MTTouchState: 4 = touching)
        var fingerID: Int32     // 24 — the persistent identity we track
        var handID: Int32       // 28
        var normalizedX: Float  // 32
        var normalizedY: Float  // 36
        var normalizedVX: Float // 40
        var normalizedVY: Float // 44
        var zTotal: Float       // 48
        var field9: Int32       // 52
        var angle: Float        // 56
        var majorAxis: Float    // 60
        var minorAxis: Float    // 64
        var absoluteX: Float    // 68
        var absoluteY: Float    // 72
        var absoluteVX: Float   // 76
        var absoluteVY: Float   // 80
        var field14: Int32      // 84
        var field15: Int32      // 88
        var zDensity: Float     // 92
    }

    private static let recordSize = 96

    static weak var shared: MultitouchAdapter?

    var onFrame: (([Touch]) -> Void)?

    private var libHandle: UnsafeMutableRawPointer?
    private var device: UnsafeMutableRawPointer?
    private(set) var started = false

    init() {
        MultitouchAdapter.shared = self
    }

    deinit {
        stop()
    }

    /// Struct sanity: the offsets we read must match the MTTouch layout this is built for.
    static func validateLayout() -> String? {
        guard MemoryLayout<MTTouch>.size == recordSize else {
            return "MTTouch size is \(MemoryLayout<MTTouch>.size), expected \(recordSize)"
        }
        guard MemoryLayout<MTTouch>.offset(of: \.fingerID) == 24 else { return "fingerID offset mismatch" }
        guard MemoryLayout<MTTouch>.offset(of: \.normalizedX) == 32 else { return "normalizedX offset mismatch" }
        guard MemoryLayout<MTTouch>.offset(of: \.normalizedY) == 36 else { return "normalizedY offset mismatch" }
        return nil
    }

    func start() -> Bool {
        guard !started else { return true }

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        libHandle = dlopen(path, RTLD_LAZY)
        guard let lib = libHandle else {
            log("MultitouchSupport failed to load")
            return false
        }

        guard let create = symbol(lib, "MTDeviceCreateDefault", MTDeviceCreateDefaultFn.self),
              let registerCb = symbol(lib, "MTRegisterContactFrameCallback", MTRegisterContactFrameCallbackFn.self),
              let startFn = symbol(lib, "MTDeviceStart", MTDeviceStartFn.self),
              let stopFn = symbol(lib, "MTDeviceStop", MTDeviceStopFn.self),
              let releaseFn = symbol(lib, "MTDeviceRelease", MTDeviceReleaseFn.self) else {
            log("MultitouchSupport symbols missing")
            return false
        }

        guard let dev = create() else {
            log("MTDeviceCreateDefault returned nil (no built-in trackpad?)")
            return false
        }
        device = dev
        // The framework only delivers frames to callbacks registered here; passing
        // the callback to MTDeviceStart does nothing (its second argument is a mode).
        registerCb(dev, callback)
        startFn(dev, 0)
        started = true
        _ = stopFn
        _ = releaseFn
        log("MultitouchSupport started on built-in trackpad")
        return true
    }

    func stop() {
        guard started, let lib = libHandle, let dev = device else { return }
        if let stopFn = symbol(lib, "MTDeviceStop", MTDeviceStopFn.self) { stopFn(dev) }
        if let releaseFn = symbol(lib, "MTDeviceRelease", MTDeviceReleaseFn.self) { releaseFn(dev) }
        device = nil
        started = false
    }

    // void (*)(MTDeviceRef device, MTTouch touches[], size_t numTouches,
    //          double timestamp, size_t frame)
    private typealias MTContactCallback = @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafeMutableRawPointer?,   // touches array, 96-byte records
        Int,
        Double,
        Int
    ) -> Void

    private typealias MTDeviceCreateDefaultFn = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias MTRegisterContactFrameCallbackFn = @convention(c) (UnsafeMutableRawPointer?, MTContactCallback?) -> Void
    private typealias MTDeviceStartFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
    private typealias MTDeviceStopFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
    private typealias MTDeviceReleaseFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, _ type: T.Type) -> T? {
        guard let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: type)
    }
}

// Context-free global function: @convention(c) conversion needs a plain function,
// and the framework must be able to call it from another thread.
private func callback(
    _ device: UnsafeMutableRawPointer?,
    _ touches: UnsafeMutableRawPointer?,
    _ count: Int,
    _ timestamp: Double,
    _ frame: Int
) -> Void {
    guard let adapter = MultitouchAdapter.shared else { return }
    guard let touches, count > 0 else {
        // Empty frame (every finger lifted). Clear the mirror dots; housekeeping
        // would also catch this if the framework never delivers empty frames.
        DispatchQueue.main.async { adapter.onFrame?([]) }
        return
    }
    var list: [MultitouchAdapter.Touch] = []
    list.reserveCapacity(count)
    for i in 0..<count {
        let base = touches + (i * 96)
        let id = base.load(fromByteOffset: 24, as: Int32.self)
        let x = base.load(fromByteOffset: 32, as: Float.self)
        let y = base.load(fromByteOffset: 36, as: Float.self)
        list.append(MultitouchAdapter.Touch(id: id, x: Double(x), y: Double(y)))
    }
    DispatchQueue.main.async { adapter.onFrame?(list) }
}
