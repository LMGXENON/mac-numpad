import Combine
import Foundation

final class AppState: ObservableObject {
    // Mirror state (FR7)
    @Published var keyUnderFinger: PadKey?
    @Published var flashedKey: PadKey?
    @Published var lastKey: PadKey?
    @Published var volume: Double = 0              // 0…1
    @Published var brightness: Double = 0          // 0…1
    @Published var volumeAvailable = true
    @Published var brightnessAvailable = true

    // Status pill + menu bar
    @Published var isControlHeld = false           // Active / Idle
    @Published var isEnabled = true                // menu-bar pause (FR8)
    @Published var suspendedBySystem = false       // sleep or lock (safety)
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false

    var permissionsMissing: Bool { !(accessibilityGranted && inputMonitoringGranted) }
    var running: Bool { isEnabled && !suspendedBySystem && !permissionsMissing }
}
