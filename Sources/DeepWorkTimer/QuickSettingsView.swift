import SwiftUI

/// The small settings popover from the gear in the popover's corner: the
/// things worth changing often. Everything else is in the full Settings window.
struct QuickSettingsView: View {
    @AppStorage(Prefs.Key.appearance) private var appearance = Appearance.light.rawValue
    @AppStorage(Prefs.Key.effectsEnabled) private var effectsEnabled = true
    @AppStorage(Prefs.Key.playSound) private var playSound = true
    @AppStorage(Prefs.Key.showTimeInMenuBar) private var showTimeInMenuBar = true
    @AppStorage(Prefs.Key.shortBreakMinutes) private var shortBreakMinutes = 10
    @AppStorage(Prefs.Key.dailyGoalMinutes) private var dailyGoalMinutes = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            appearancePicker

            VStack(spacing: 0) {
                row("Focus & wallpaper", symbol: "moon.fill") { Toggle("", isOn: $effectsEnabled).labelsHidden() }
                Divider().padding(.leading, 30)
                row("Sound when done", symbol: "speaker.wave.2.fill") { Toggle("", isOn: $playSound).labelsHidden() }
                Divider().padding(.leading, 30)
                row("Time in menu bar", symbol: "menubar.rectangle") { Toggle("", isOn: $showTimeInMenuBar).labelsHidden() }
            }
            .groupBox()

            VStack(spacing: 0) {
                row("Break", symbol: "cup.and.saucer.fill") {
                    MiniStepper(value: $shortBreakMinutes, range: 1...60, step: 1) { "\($0) min" }
                }
                Divider().padding(.leading, 30)
                row("Daily goal", symbol: "flag.fill") {
                    MiniStepper(value: $dailyGoalMinutes, range: 30...720, step: 30) { DailyStats.durationText(TimeInterval($0 * 60)) }
                }
            }
            .groupBox()

            HStack {
                Button("All Settings…") { SettingsWindow.show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 270)
        .toggleStyle(.switch)
        .controlSize(.mini)
        .tint(Theme.red)
    }

    /// Three tappable tiles rather than a plain segmented control, so the choice reads at a glance.
    private var appearancePicker: some View {
        HStack(spacing: 6) {
            ForEach(Appearance.allCases, id: \.self) { option in
                let selected = appearance == option.rawValue
                Hoverable { hovered in
                    Button {
                        appearance = option.rawValue
                        Appearance.apply(option)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: option.symbol).font(.system(size: 14, weight: .medium))
                            Text(option.title).font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.red) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Theme.red.opacity(0.1) : (hovered ? Theme.fill.opacity(1.6) : Theme.fill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? Theme.red.opacity(0.5) : .clear, lineWidth: 1.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(option.title) appearance")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func row<Control: View>(_ title: String, symbol: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title).font(.system(size: 12.5))
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }
}

/// "−  10 min  +" in a small capsule.
private struct MiniStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 2) {
            button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
            Text(format(value))
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 44)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .padding(2)
        .background(Capsule().fill(Theme.fill))
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

private extension View {
    func groupBox() -> some View {
        background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fill))
    }
}
