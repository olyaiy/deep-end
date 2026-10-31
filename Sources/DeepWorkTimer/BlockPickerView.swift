import SwiftUI

/// Choose what gets blocked during focus: built-in categories (with per-site
/// opt-outs), your own categories, and one-off sites.
struct BlockPickerView: View {
    @ObservedObject var blocker = SiteBlocker.shared
    @StateObject private var ui = BlockPickerUI()

    var body: some View {
        VStack(spacing: 0) {
            header
            if !blocker.helperInstalled { setupBanner }
            if let error = blocker.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Categories")
                    ForEach(BlockCategory.builtIn) { CategoryRow(category: $0, ui: ui) }

                    SectionLabel("Your categories").padding(.top, 10)
                    ForEach(blocker.settings.customCategories) { CategoryRow(category: $0, ui: ui) }
                    newCategoryRow

                    SectionLabel("Your sites").padding(.top, 10)
                    SiteField(placeholder: "Add a site, e.g. reddit.com", text: $ui.newSite) { blocker.add(site: $0) }
                    if !blocker.settings.customSites.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(blocker.settings.customSites, id: \.self) { site in
                                SiteChip(site: site, isOn: true, tint: Theme.red, onRemove: { blocker.remove(site: site) })
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .disabled(!blocker.settings.enabled)
                .opacity(blocker.settings.enabled ? 1 : 0.45)
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 330)
        .tint(Theme.red)
        .animation(Theme.spring, value: ui.expanded)
        .animation(Theme.spring, value: blocker.settings.customCategories.count)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.redGradient)
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Block distractions").font(.system(size: 14, weight: .semibold))
                Text(summary).font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Toggle("Block distractions", isOn: $blocker.settings.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var summary: String {
        guard blocker.settings.enabled else { return "Off" }
        let n = blocker.blockedSites.count
        return n == 1 ? "1 site, during focus sessions" : "\(n) sites, during focus sessions"
    }

    private var setupBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("One-time setup").font(.system(size: 12, weight: .semibold))
                Text("macOS asks for your password once so the timer can block sites.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Set Up…") { blocker.installHelper() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.red.opacity(0.08)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var newCategoryRow: some View {
        if ui.addingCategory {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus").foregroundStyle(.secondary).frame(width: 26)
                TextField("Category name", text: $ui.newCategoryName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(createCategory)
                    .onExitCommand { ui.addingCategory = false; ui.newCategoryName = "" }
                Button("Add", action: createCategory)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(ui.newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.fill))
        } else {
            Hoverable { hovered in
                Button { ui.addingCategory = true } label: {
                    Label("New category", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(hovered ? Theme.red : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func createCategory() {
        guard let category = blocker.addCategory(named: ui.newCategoryName) else { return }
        ui.newCategoryName = ""
        ui.addingCategory = false
        ui.expanded.insert(category.id)
    }
}

/// UI-only state (no @State: its macro needs full Xcode).
final class BlockPickerUI: ObservableObject {
    @Published var expanded: Set<String> = []
    @Published var newSite = ""
    @Published var newCategoryName = ""
    @Published var addingCategory = false
    @Published var categoryInputs: [String: String] = [:]
}

// MARK: Rows

private struct CategoryRow: View {
    let category: BlockCategory
    @ObservedObject var ui: BlockPickerUI
    @ObservedObject var blocker = SiteBlocker.shared

    private var isOn: Bool { blocker.isOn(category) }
    private var isExpanded: Bool { ui.expanded.contains(category.id) }
    private var tint: Color { Self.tints[category.id] ?? .gray }

    static let tints: [String: Color] = [
        "social": .blue, "video": .red, "news": .orange, "shopping": .purple,
        "games": .green, "sports": .teal, "chat": .indigo,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hoverable { hovered in
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient)
                        Image(systemName: category.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 26, height: 26)
                    .saturation(isOn ? 1 : 0.2)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(category.name).font(.system(size: 13, weight: .medium))
                        Text(countText).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    CheckToggle(isOn: isOn, tint: Theme.red) { blocker.toggle(category) }
                        .accessibilityLabel("Block \(category.name)")
                }
                .padding(.horizontal, 8)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovered || isExpanded ? Theme.fill : .clear))
                .contentShape(Rectangle())
                .onTapGesture {
                    if isExpanded { ui.expanded.remove(category.id) } else { ui.expanded.insert(category.id) }
                }
            }

            if isExpanded {
                expandedContent
                    .padding(.leading, 44)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var countText: String {
        let total = category.domains.count
        if total == 0 { return "No sites yet" }
        let active = blocker.activeCount(in: category)
        if !isOn { return total == 1 ? "1 site" : "\(total) sites" }
        return active == total ? "All \(total) blocked" : "\(active) of \(total) blocked"
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !category.domains.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(category.domains, id: \.self) { domain in
                        if category.isCustom {
                            SiteChip(site: domain, isOn: isOn, tint: Theme.red, onRemove: { blocker.remove(site: domain, from: category.id) })
                        } else {
                            SiteChip(site: domain, isOn: isOn && !blocker.settings.excludedDomains.contains(domain), tint: Theme.red,
                                     onTap: { blocker.toggle(domain: domain) })
                        }
                    }
                }
            }
            if category.isCustom {
                SiteField(placeholder: "Add a site to \(category.name)", text: Binding(
                    get: { ui.categoryInputs[category.id] ?? "" },
                    set: { ui.categoryInputs[category.id] = $0 }
                )) { blocker.add(site: $0, to: category.id) }
                Button(role: .destructive) { blocker.deleteCategory(category) } label: {
                    Label("Delete category", systemImage: "trash").font(.system(size: 11.5))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            } else {
                Text("Click a site to allow it.").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Round checkbox: a filled red check when on.
private struct CheckToggle: View {
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A site as a capsule. Tap to toggle it, or ✕ to remove it.
private struct SiteChip: View {
    let site: String
    let isOn: Bool
    let tint: Color
    var onTap: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        Hoverable { hovered in
            HStack(spacing: 4) {
                Text(site)
                    .strikethrough(!isOn, color: .secondary)
                    .foregroundStyle(isOn ? .primary : .secondary)
                if onRemove != nil {
                    Button { onRemove?() } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(hovered ? .primary : .tertiary)
                            .frame(width: 14, height: 14)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(site)")
                }
            }
            .font(.system(size: 11.5))
            .padding(.leading, 9)
            .padding(.trailing, onRemove == nil ? 9 : 5)
            .frame(height: 24)
            .background(Capsule().fill(isOn ? tint.opacity(hovered ? 0.18 : 0.11) : Theme.fill))
            .overlay(Capsule().strokeBorder(isOn ? tint.opacity(0.25) : .clear))
            .contentShape(Capsule())
            .onTapGesture { onTap?() }
        }
    }
}

/// A text field that adds a site on Return, and shakes off bad input.
private struct SiteField: View {
    let placeholder: String
    @Binding var text: String
    let onAdd: (String) -> Bool
    @StateObject private var invalid = Flag()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").foregroundStyle(text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Theme.red))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit(submit)
                .onChange(of: text) { invalid.value = false }
            if invalid.value {
                Text("Not a website").font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(Theme.fill))
        .overlay(Capsule().strokeBorder(invalid.value ? Color.orange.opacity(0.6) : .clear))
    }

    private func submit() {
        guard !text.isEmpty else { return }
        if onAdd(text) { text = "" } else { invalid.value = true }
    }
}

final class Flag: ObservableObject { @Published var value = false }

private struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
