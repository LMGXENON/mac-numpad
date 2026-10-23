import Foundation

/// A key on the pad. Calculator style with 7 8 9 on top and a 0 key that spans two
/// columns, matching the reference design. The bottom-right holds Backspace and a
/// tall Return (FR9), so a typed search can be corrected and submitted.
enum PadKey: Equatable, Hashable {
    case digit(Int)
    case decimal
    case add, subtract, multiply, divide, percent
    case backspace
    case ret

    var label: String {
        switch self {
        case .digit(let d): return String(d)
        case .decimal: return "."
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        case .percent: return "%"
        case .backspace: return "⌫"
        case .ret: return "⏎"
        }
    }

    /// What the key sends into the frontmost app.
    var typedCharacter: String? {
        switch self {
        case .digit(let d): return String(d)
        case .decimal: return "."
        case .add: return "+"
        case .subtract: return "-"
        case .multiply: return "×"
        case .divide: return "÷"
        case .percent: return "%"
        case .backspace, .ret: return nil      // sent as virtual keys
        }
    }

    /// Text recorded in the input strip for what was actually sent.
    var sentText: String {
        typedCharacter ?? label
    }
}

/// Trackpad map in normalized coordinates: x runs 0→1 left→right, y runs 0→1 bottom→top.
enum PadLayout {
    struct Rect {
        let x0: Double, x1: Double, y0: Double, y1: Double

        func contains(x: Double, y: Double) -> Bool {
            x >= x0 && x <= x1 && y >= y0 && y <= y1 && y >= y0
        }

        var width: Double { x1 - x0 }
        var height: Double { y1 - y0 }
    }

    struct KeySpec {
        let key: PadKey
        let col: Int, row: Int, colSpan: Int, rowSpan: Int
    }

    // Two slider strips at the left edge (brightness, volume).
    static let brightnessStrip = Rect(x0: 0.03, x1: 0.115, y0: 0.06, y1: 0.94)
    static let volumeStrip = Rect(x0: 0.15, x1: 0.235, y0: 0.06, y1: 0.94)
    // Gap that keeps slider drags off the keys.
    static let deadZone = Rect(x0: 0.235, x1: 0.33, y0: 0.0, y1: 1.0)
    // Calculator keypad filling the rest.
    static let grid = Rect(x0: 0.33, x1: 0.975, y0: 0.05, y1: 0.95)
    static let gridColumns = 4
    static let gridRows = 5

    enum Region: Equatable {
        case brightness, volume, deadZone, outside
        case key(PadKey)
    }

    /// Reference-design keypad: operator row on top, digits 7 8 9 down to 0,
    /// a tall Return spanning the 4/5/6 and 1/2/3 rows, Backspace bottom-right.
    static let keySpecs: [KeySpec] = [
        KeySpec(key: .add, col: 0, row: 0, colSpan: 1, rowSpan: 1),
        KeySpec(key: .multiply, col: 1, row: 0, colSpan: 1, rowSpan: 1),
        KeySpec(key: .subtract, col: 2, row: 0, colSpan: 1, rowSpan: 1),
        KeySpec(key: .divide, col: 3, row: 0, colSpan: 1, rowSpan: 1),

        KeySpec(key: .digit(7), col: 0, row: 1, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(8), col: 1, row: 1, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(9), col: 2, row: 1, colSpan: 1, rowSpan: 1),
        KeySpec(key: .percent, col: 3, row: 1, colSpan: 1, rowSpan: 1),

        KeySpec(key: .digit(4), col: 0, row: 2, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(5), col: 1, row: 2, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(6), col: 2, row: 2, colSpan: 1, rowSpan: 1),
        KeySpec(key: .ret, col: 3, row: 2, colSpan: 1, rowSpan: 2),

        KeySpec(key: .digit(1), col: 0, row: 3, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(2), col: 1, row: 3, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(3), col: 2, row: 3, colSpan: 1, rowSpan: 1),

        KeySpec(key: .digit(0), col: 0, row: 4, colSpan: 2, rowSpan: 1),
        KeySpec(key: .decimal, col: 2, row: 4, colSpan: 1, rowSpan: 1),
        KeySpec(key: .backspace, col: 3, row: 4, colSpan: 1, rowSpan: 1)
    ]

    static func keyRect(_ spec: KeySpec) -> Rect {
        let cellWidth = grid.width / Double(gridColumns)
        let cellHeight = grid.height / Double(gridRows)
        let x0 = grid.x0 + Double(spec.col) * cellWidth
        let x1 = x0 + Double(spec.colSpan) * cellWidth
        let y1 = grid.y1 - Double(spec.row) * cellHeight
        let y0 = y1 - Double(spec.rowSpan) * cellHeight
        return Rect(x0: x0, x1: x1, y0: y0, y1: y1)
    }

    static func region(x: Double, y: Double) -> Region {
        if brightnessStrip.contains(x: x, y: y) { return .brightness }
        if volumeStrip.contains(x: x, y: y) { return .volume }
        if deadZone.contains(x: x, y: y) { return .deadZone }
        for spec in keySpecs where keyRect(spec).contains(x: x, y: y) {
            return .key(spec.key)
        }
        return .outside
    }

    static let allKeySpecs = keySpecs
}
