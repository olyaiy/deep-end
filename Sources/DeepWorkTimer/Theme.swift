import SwiftUI

/// White and red (charcoal and red in dark mode), with Liquid Glass controls.
enum Theme {
    static let red = dynamic(light: 0xFF3B30, dark: 0xFF453A)
    static let redLight = dynamic(light: 0xFF6B5C, dark: 0xFF7066)
    static let redGradient = LinearGradient(colors: [redLight, red], startPoint: .top, endPoint: .bottom)
    static let green = dynamic(light: 0x24A148, dark: 0x30D158)
    static let knob = dynamic(light: 0xFFFFFF, dark: 0xF5F5F7)
    static let fill = Color.primary.opacity(0.06)
    static let track = Color.primary.opacity(0.08)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.7)
    static let morph = Animation.bouncy(duration: 0.45, extraBounce: 0.05)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

extension Phase {
    var label: String {
        switch self {
        case .idle, .work: "Focus"
        case .shortBreak: "Break"
        case .longBreak: "Long Break"
        }
    }
}

// MARK: Hover

/// Hover tracking without @State (its macro plugin needs full Xcode; we build with the CLT).
final class HoverState: ObservableObject {
    @Published var isHovered = false
}

struct Hoverable<Content: View>: View {
    @StateObject private var hover = HoverState()
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(hover.isHovered)
            .onHover { hovering in
                withAnimation(Theme.spring) { hover.isHovered = hovering }
            }
    }
}

// MARK: Glass buttons

/// Shrinks slightly while pressed. Pairs with GlassButton, which handles hover.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A Liquid Glass button. `prominent` tints it red for the primary action.
/// Give it a `glassID` to morph between layouts inside a GlassEffectContainer.
struct GlassButton<Label: View>: View {
    enum Shape { case capsule, circle }

    var prominent = false
    /// Colour of a prominent button. Defaults to red.
    var tint: Color?
    var shape: Shape = .capsule
    var height: CGFloat = 36
    var horizontalPadding: CGFloat = 16
    var expands = false
    var glassID: String?
    var namespace: Namespace.ID
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            Hoverable { hovered in
                label()
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, shape == .circle ? 0 : horizontalPadding)
                    .frame(width: shape == .circle ? height : nil, height: height)
                    .frame(maxWidth: expands ? .infinity : nil)
                    // A solid red base keeps the primary action red even when the
                    // window is inactive (macOS greys out tinted glass there).
                    .background(Capsule().fill(tint.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Theme.redGradient))
                        .opacity(prominent ? (hovered ? 1 : 0.92) : 0))
                    .contentShape(Capsule())
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID(glassID, in: namespace)
                    .scaleEffect(hovered ? 1.035 : 1)
                    .shadow(color: prominent ? (tint ?? Theme.red).opacity(hovered ? 0.35 : 0.18) : .clear, radius: hovered ? 10 : 6, y: 3)
            }
        }
        .buttonStyle(PressStyle())
    }
}

/// Borderless icon button that rotates/brightens on hover.
struct IconButton: View {
    let systemImage: String
    var hoverRotation: Double = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Hoverable { hovered in
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(hovered ? .primary : .secondary)
                    .rotationEffect(.degrees(hovered ? hoverRotation : 0))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(hovered ? Theme.fill : .clear))
                    .contentShape(Circle())
            }
        }
        .buttonStyle(PressStyle())
    }
}
