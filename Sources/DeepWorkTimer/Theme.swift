import SwiftUI

/// White and red, with Liquid Glass controls.
enum Theme {
    static let red = Color(red: 1.0, green: 0.231, blue: 0.188) // systemRed (light)
    static let redLight = Color(red: 1.0, green: 0.42, blue: 0.36)
    static let redGradient = LinearGradient(colors: [redLight, red], startPoint: .top, endPoint: .bottom)
    static let fill = Color.black.opacity(0.05)
    static let track = Color.black.opacity(0.07)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.7)
    static let morph = Animation.bouncy(duration: 0.45, extraBounce: 0.05)
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
                    .background(Capsule().fill(Theme.redGradient).opacity(prominent ? (hovered ? 1 : 0.92) : 0))
                    .contentShape(Capsule())
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID(glassID, in: namespace)
                    .scaleEffect(hovered ? 1.035 : 1)
                    .shadow(color: prominent ? Theme.red.opacity(hovered ? 0.35 : 0.18) : .clear, radius: hovered ? 10 : 6, y: 3)
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
