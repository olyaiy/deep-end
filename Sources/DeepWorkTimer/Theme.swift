import SwiftUI

// MARK: Phase palette

extension Phase {
    var colors: [Color] {
        switch self {
        case .idle, .work:
            [Color(red: 0.58, green: 0.43, blue: 1.00), Color(red: 0.31, green: 0.47, blue: 1.00)]
        case .shortBreak:
            [Color(red: 0.22, green: 0.86, blue: 0.66), Color(red: 0.13, green: 0.64, blue: 0.92)]
        case .longBreak:
            [Color(red: 1.00, green: 0.72, blue: 0.30), Color(red: 0.98, green: 0.44, blue: 0.42)]
        }
    }

    var tint: Color { colors[0] }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var symbol: String {
        switch self {
        case .idle: "scope"
        case .work: "brain.head.profile"
        case .shortBreak: "cup.and.saucer.fill"
        case .longBreak: "figure.walk"
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

// MARK: Button styles

struct PrimaryButtonStyle: ButtonStyle {
    var phase: Phase

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(phase.gradient, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: phase.tint.opacity(hovered ? 0.55 : 0.32), radius: hovered ? 14 : 9, y: 4)
                .brightness(hovered ? 0.04 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// Round icon button. `prominent` fills it with the phase gradient.
struct CircleButtonStyle: ButtonStyle {
    var phase: Phase
    var size: CGFloat = 44
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.85)))
                .frame(width: size, height: size)
                .background {
                    if prominent {
                        Circle().fill(phase.gradient)
                            .shadow(color: phase.tint.opacity(hovered ? 0.6 : 0.38), radius: hovered ? 14 : 10, y: 4)
                    } else {
                        Circle().fill(Color.primary.opacity(hovered ? 0.13 : 0.07))
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(prominent ? 0.22 : 0), lineWidth: 0.5))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .contentShape(Circle())
        }
    }
}

/// Small borderless icon button for the header.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovered ? 0.09 : 0)))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
        }
    }
}

/// Capsule chip, used for duration presets and ±5 min.
struct ChipButtonStyle: ButtonStyle {
    var phase: Phase
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        Hoverable { hovered in
            configuration.label
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? AnyShapeStyle(phase.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(selected ? phase.tint.opacity(0.16) : Color.primary.opacity(hovered ? 0.1 : 0.06)))
                .overlay(Capsule().strokeBorder(selected ? phase.tint.opacity(0.45) : .clear, lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .contentShape(Capsule())
        }
    }
}

// MARK: Toggle

struct SwitchStyle: ToggleStyle {
    var tint: Color = Phase.work.tint

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? AnyShapeStyle(Phase.work.gradient) : AnyShapeStyle(Color.primary.opacity(0.16)))
                        .frame(width: 34, height: 20)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Stepper

struct ValueStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus") { value = max(range.lowerBound, value - step) }
                .disabled(value <= range.lowerBound)
            Text(format(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 56)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            stepButton("plus") { value = min(range.upperBound, value + step) }
                .disabled(value >= range.upperBound)
        }
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

// MARK: Layout helpers

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}
