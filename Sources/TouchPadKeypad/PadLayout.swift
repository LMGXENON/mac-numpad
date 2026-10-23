import Foundation

/// A key on the pad. Calculator style with operators, digits, decimal, backspace, and return.
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
        case .multiply: return "*"
        case .divide: return "/"
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
            x >= x0 && x <= x1 && y >= y0 && y <= y1
        }

        var width: Double { x1 - x0 }
        var height: Double { y1 - y0 }
    }

    struct KeySpec {
        let key: PadKey
        let col: Int, row: Int, colSpan: Int, rowSpan: Int
    }

    // Grid configuration defined first so sliders can precisely match button column widths
    static let grid          = Rect(x0: 0.38, x1: 0.97, y0: 0.05, y1: 0.95)
    static let gridColumns = 4
    static let gridRows = 5

    // Slider width matches a single button column width exactly (~0.1475)
    static let brightnessStrip = Rect(x0: 0.04, x1: 0.1875, y0: 0.06, y1: 0.94)
    static let volumeStrip     = Rect(x0: 0.2075, x1: 0.355, y0: 0.06, y1: 0.94) // Spaced from brightness
    
    // Narrower dead zone bringing sliders closer to the numbers
    static let deadZone        = Rect(x0: 0.355, x1: 0.38, y0: 0.0,  y1: 1.0)

    enum Region: Equatable {
        case brightness, volume, deadZone, outside
        case key(PadKey)
    }

    /// Full calculator layout including division, operators, digits, and action keys.
    static let keySpecs: [KeySpec] = [
        // Row 0: Operators (Division included) & Backspace
        KeySpec(key: .divide,   col: 0, row: 0, colSpan: 1, rowSpan: 1),
        KeySpec(key: .multiply, col: 1, row: 0, colSpan: 1, rowSpan: 1),
        KeySpec(key: .subtract, col: 2, row: 0, colSpan: 1, rowSpan: 1),
        KeySpec(key: .backspace,col: 3, row: 0, colSpan: 1, rowSpan: 1),

        // Row 1: Digits 7, 8, 9 + Tall Plus key on the right
        KeySpec(key: .digit(7), col: 0, row: 1, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(8), col: 1, row: 1, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(9), col: 2, row: 1, colSpan: 1, rowSpan: 1),
        KeySpec(key: .add,      col: 3, row: 1, colSpan: 1, rowSpan: 2),

        // Row 2: Digits 4, 5, 6
        KeySpec(key: .digit(4), col: 0, row: 2, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(5), col: 1, row: 2, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(6), col: 2, row: 2, colSpan: 1, rowSpan: 1),

        // Row 3: Digits 1, 2, 3 + Tall Return key on the right
        KeySpec(key: .digit(1), col: 0, row: 3, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(2), col: 1, row: 3, colSpan: 1, rowSpan: 1),
        KeySpec(key: .digit(3), col: 2, row: 3, colSpan: 1, rowSpan: 1),
        KeySpec(key: .ret,      col: 3, row: 3, colSpan: 1, rowSpan: 2),

        // Row 4: Wide 0 key & Decimal point
        KeySpec(key: .digit(0), col: 0, row: 4, colSpan: 2, rowSpan: 1),
        KeySpec(key: .decimal,  col: 2, row: 4, colSpan: 1, rowSpan: 1)
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