import SwiftUI

/// White and red, modeled on Apple's Clock timer.
enum Theme {
    static let red = Color(red: 1.0, green: 0.231, blue: 0.188) // systemRed (light)
    static let fill = Color.black.opacity(0.055)
    static let fillHover = Color.black.opacity(0.09)
    static let track = Color.black.opacity(0.07)
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
                withAnimation(.easeOut(duration: 0.12)) { hover.isHovered = hovering }
            }
    }
}

// MARK: Buttons

/// The round Cancel / Start / Pause buttons from the Clock app: a filled circle
/// inside a thin ring of the same color.
struct ClockButtonStyle: ButtonStyle {
    enum Kind { case primary, tinted, neutral }
    var kind: Kind
    var size: CGFloat = 58

    func makeBody(configuration: Configuration) -> some View {
        ClockButtonBody(configuration: configuration, kind: kind, size: size)
    }

    private struct ClockButtonBody: View {
        let configuration: Configuration
        let kind: Kind
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let fill: Color = switch kind {
            case .primary: Theme.red
            case .tinted: Theme.red.opacity(0.12)
            case .neutral: Theme.fill
            }
            let foreground: Color = switch kind {
            case .primary: .white
            case .tinted: Theme.red
            case .neutral: .primary
            }
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .padding(3)
                .overlay(Circle().strokeBorder(fill, lineWidth: 1.5))
                .contentShape(Circle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .opacity(isEnabled ? 1 : 0.35)
                .animation(.easeOut(duration: 0.15), value: kind)
        }
    }
}

/// Small capsule buttons for secondary actions (−5 min, Skip…).
struct PillButtonStyle: ButtonStyle {
    var tinted = false

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tinted ? Theme.red : Color.primary.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(tinted ? Theme.red.opacity(hovered ? 0.16 : 0.1) : (hovered ? Theme.fillHover : Theme.fill)))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

/// Borderless icon button.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovered ? Theme.fill : .clear))
                .contentShape(Circle())
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

// MARK: Segmented control

/// An Apple-style segmented control, drawn in SwiftUI.
struct SegmentedControl<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fill))
    }
}
