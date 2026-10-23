import SwiftUI
import AppKit

// MARK: - Mirror panel (non-activating, never key: must not steal typed digits)

final class MirrorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class MirrorWindowController {
    private let panel: MirrorPanel

    init(state: AppState) {
        panel = MirrorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 356),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        let view = NSHostingView(rootView: MirrorView(state: state))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
    }

    func show(onScreen screen: NSScreen? = NSScreen.main) {
        guard let screen else { panel.orderFrontRegardless(); return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 20,
            y: visible.maxY - size.height - 20
        ))
        panel.orderFrontRegardless()
    }
}

// MARK: - Frosted glass background (reference-design look)

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.masksToBounds = true
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        view.layer?.borderWidth = 1
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Root view

struct MirrorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            PadMirrorView(state: state)
                .aspectRatio(1.5, contentMode: .fit)
            HStack(alignment: .center, spacing: 12) {
                InstructionsBar()
                StatusPill(state: state)
                    .fixedSize()
            }
        }
        .padding(12)
        .background(GlassBackground())
        .preferredColorScheme(.dark)
    }
}

private struct InstructionsBar: View {
    var body: some View {
        Text("Hold ⌃ Control — tap or click the **keypad** to type, **drag** a strip to change **brightness** / **volume**. Release Control for the normal trackpad.")
            .font(.caption)
            .foregroundColor(.white.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }
}

// MARK: - Pad mirror

struct PadMirrorView: View {
    @ObservedObject var state: AppState

    private func map(_ rect: PadLayout.Rect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.x0 * size.width,
            y: (1 - rect.y1) * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                    )

                sliderStrip(region: PadLayout.brightnessStrip,
                            symbol: "sun.max",
                            level: state.brightnessAvailable ? state.brightness : nil,
                            active: state.isControlHeld,
                            in: size)
                sliderStrip(region: PadLayout.volumeStrip,
                            symbol: "speaker.wave.2",
                            level: state.volumeAvailable ? state.volume : nil,
                            active: state.isControlHeld,
                            in: size)

                ForEach(PadLayout.allKeySpecs, id: \.key) { spec in
                    keyCell(spec, in: size)
                }
            }
        }
    }

    private func sliderStrip(region: PadLayout.Rect, symbol: String, level: Double?, active: Bool, in size: CGSize) -> some View {
        let rect = map(region, in: size)
        let fillFraction = min(1, level ?? 0)
        let unavailable = level == nil

        return VStack(spacing: 4) {
            Text(unavailable ? "—" : "\(Int(round(fillFraction * 100)))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(unavailable ? .gray.opacity(0.8) : .white.opacity(0.95))
                .fixedSize()

            GeometryReader { tg in
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.13))
                    if !unavailable && fillFraction > 0.01 {
                        Capsule()
                            .fill(active ? Color.white.opacity(0.95) : Color.white.opacity(0.6))
                            .frame(height: tg.size.height * fillFraction)
                            .animation(.easeOut(duration: 0.08), value: fillFraction)
                    }
                }
            }
            .overlay {
                if unavailable {
                    Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }

            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(unavailable ? .gray.opacity(0.6) : .white.opacity(0.9))
                .fixedSize()
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }

    private func keyCell(_ spec: PadLayout.KeySpec, in size: CGSize) -> some View {
        let rect = map(PadLayout.keyRect(spec), in: size).insetBy(dx: 3.5, dy: 3.5)
        let key = spec.key
        let isFlashed = state.flashedKey == key
        let underFinger = state.isControlHeld && state.keyUnderFinger == key

        return ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(
                    isFlashed ? Color.white.opacity(0.95) :
                    underFinger ? Color.white.opacity(0.38) :
                    Color.white.opacity(0.16)
                )
            Text(key.label)
                .font(.system(size: 16,
                              weight: .semibold,
                              design: .rounded))
                .foregroundColor(isFlashed ? Color(white: 0.12) : .white.opacity(0.92))
        }
        .frame(width: rect.width, height: rect.height)
        .overlay {
            if isFlashed || underFinger {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
            }
        }
        .position(x: rect.midX, y: rect.midY)
        .animation(.easeOut(duration: 0.1), value: isFlashed)
        .allowsHitTesting(false)
    }
}

// MARK: - Status pill

struct StatusPill: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            if state.permissionsMissing {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("Permission needed")
                    .font(.caption)
                    .foregroundColor(.white)
                if !state.accessibilityGranted {
                    pillButton("Accessibility") {
                        NSWorkspace.shared.open(URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )!)
                    }
                }
                if !state.inputMonitoringGranted {
                    pillButton("Input Monitoring") {
                        NSWorkspace.shared.open(URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
                        )!)
                    }
                }
            } else if !state.isEnabled {
                labeledPill("Paused", color: .orange)
            } else if state.suspendedBySystem {
                labeledPill("Sleeping", color: .orange)
            } else if state.isControlHeld {
                labeledPill("Active", color: .green)
            } else {
                labeledPill("Idle", color: .gray)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    private func labeledPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundColor(.white.opacity(0.85))
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .controlSize(.mini)
            .buttonStyle(.borderedProminent)
            .tint(.red)
    }
}