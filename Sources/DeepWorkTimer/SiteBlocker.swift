import AppKit
import Combine

/// A named group of sites you can block together.
struct BlockCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var domains: [String]
    var isCustom = false
}

/// What to block. Built-in categories live in code; everything else is saved.
struct BlockSettings: Codable {
    var enabled = true
    var enabledCategories: Set<String> = ["social", "video"]
    /// Sites switched off inside an otherwise-enabled category.
    var excludedDomains: Set<String> = []
    var customSites: [String] = []
    var customCategories: [BlockCategory] = []
}

extension BlockCategory {
    static let builtIn: [BlockCategory] = [
        .init(id: "social", name: "Social", symbol: "bubble.left.and.bubble.right.fill",
              domains: ["x.com", "twitter.com", "instagram.com", "facebook.com", "tiktok.com", "reddit.com",
                        "threads.net", "bsky.app", "linkedin.com", "snapchat.com"]),
        .init(id: "video", name: "Video", symbol: "play.rectangle.fill",
              domains: ["youtube.com", "netflix.com", "twitch.tv", "primevideo.com", "disneyplus.com", "hulu.com", "max.com"]),
        .init(id: "news", name: "News", symbol: "newspaper.fill",
              domains: ["news.ycombinator.com", "cnn.com", "nytimes.com", "bbc.com", "theguardian.com",
                        "washingtonpost.com", "foxnews.com", "theverge.com", "techcrunch.com", "cbc.ca"]),
        .init(id: "shopping", name: "Shopping", symbol: "bag.fill",
              domains: ["amazon.com", "amazon.ca", "ebay.com", "etsy.com", "aliexpress.com", "temu.com", "walmart.com", "bestbuy.com"]),
        .init(id: "games", name: "Games", symbol: "gamecontroller.fill",
              domains: ["store.steampowered.com", "steamcommunity.com", "roblox.com", "epicgames.com", "chess.com", "lichess.org"]),
        .init(id: "sports", name: "Sports", symbol: "sportscourt.fill",
              domains: ["espn.com", "theathletic.com", "nba.com", "nhl.com", "sportsnet.ca", "tsn.ca"]),
        .init(id: "chat", name: "Chat", symbol: "message.fill",
              domains: ["discord.com", "web.whatsapp.com", "messenger.com", "web.telegram.org"]),
    ]
}

/// Blocks sites during focus sessions by writing them into a marked section of
/// /etc/hosts. That needs root, so a tiny helper is installed once (with an
/// admin password prompt) and a sudoers rule lets this user run just that helper.
@MainActor
final class SiteBlocker: ObservableObject {
    static let shared = SiteBlocker()

    @Published var settings: BlockSettings {
        didSet {
            save()
            if isBlocking { apply() }
        }
    }
    @Published private(set) var helperInstalled = false
    @Published private(set) var lastError: String?

    nonisolated static let helperPath = "/usr/local/libexec/deepwork-block"
    private static let settingsKey = "block.settings"
    private let activeKey = "block.active"
    private var isBlocking: Bool { UserDefaults.standard.bool(forKey: activeKey) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(BlockSettings.self, from: data) {
            settings = decoded
        } else {
            settings = BlockSettings()
        }
        refreshHelperStatus()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: Derived

    var allCategories: [BlockCategory] { BlockCategory.builtIn + settings.customCategories }

    func isOn(_ category: BlockCategory) -> Bool { settings.enabledCategories.contains(category.id) }

    func activeCount(in category: BlockCategory) -> Int {
        category.domains.filter { !settings.excludedDomains.contains($0) }.count
    }

    /// Every site that will be blocked, as typed (without www./m. variants).
    var blockedSites: [String] {
        guard settings.enabled else { return [] }
        var seen = Set<String>(), out: [String] = []
        let fromCategories = allCategories.filter(isOn).flatMap(\.domains).filter { !settings.excludedDomains.contains($0) }
        for d in fromCategories + settings.customSites where seen.insert(d).inserted { out.append(d) }
        return out
    }

    // MARK: Editing

    func toggle(_ category: BlockCategory) {
        if isOn(category) { settings.enabledCategories.remove(category.id) } else { settings.enabledCategories.insert(category.id) }
    }

    func toggle(domain: String) {
        if settings.excludedDomains.contains(domain) { settings.excludedDomains.remove(domain) } else { settings.excludedDomains.insert(domain) }
    }

    /// Adds a site to your list (or to a custom category). Returns false if it isn't a valid domain.
    @discardableResult
    func add(site raw: String, to categoryID: String? = nil) -> Bool {
        guard let domain = Self.normalize(raw) else { return false }
        if let categoryID, let i = settings.customCategories.firstIndex(where: { $0.id == categoryID }) {
            if !settings.customCategories[i].domains.contains(domain) { settings.customCategories[i].domains.append(domain) }
        } else if !settings.customSites.contains(domain) {
            settings.customSites.append(domain)
        }
        return true
    }

    func remove(site: String, from categoryID: String? = nil) {
        if let categoryID, let i = settings.customCategories.firstIndex(where: { $0.id == categoryID }) {
            settings.customCategories[i].domains.removeAll { $0 == site }
        } else {
            settings.customSites.removeAll { $0 == site }
        }
    }

    @discardableResult
    func addCategory(named name: String) -> BlockCategory? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let category = BlockCategory(id: "custom-" + UUID().uuidString, name: name, symbol: "folder.fill", domains: [], isCustom: true)
        settings.customCategories.append(category)
        settings.enabledCategories.insert(category.id)
        return category
    }

    func deleteCategory(_ category: BlockCategory) {
        settings.customCategories.removeAll { $0.id == category.id }
        settings.enabledCategories.remove(category.id)
    }

    /// "https://www.Reddit.com/r/foo" → "reddit.com". Nil if it doesn't look like a domain.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: s.contains("://") ? s : "https://" + s), let host = url.host() { s = host }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        let label = "[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
        guard s.count <= 253, s.range(of: "^\(label)(\\.\(label))+$", options: .regularExpression) != nil else { return nil }
        return s
    }

    // MARK: Enforcement

    func apply() {
        UserDefaults.standard.set(true, forKey: activeKey)
        let sites = blockedSites
        guard helperInstalled else { return }
        // Cover the common variants a browser might hit.
        let hosts = sites.flatMap { d in d.split(separator: ".").count > 2 ? [d] : [d, "www." + d, "m." + d, "mobile." + d] }
        runHelper(sites.isEmpty ? ["clear"] : ["apply"], input: hosts.joined(separator: "\n"))
    }

    func clear() {
        let wasActive = isBlocking
        UserDefaults.standard.set(false, forKey: activeKey)
        guard wasActive, helperInstalled else { return }
        runHelper(["clear"], input: "")
    }

    private func runHelper(_ args: [String], input: String) {
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-n", Self.helperPath] + args
            let stdin = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardError = stderr
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
                stdin.fileHandleForWriting.write(Data(input.utf8))
                try stdin.fileHandleForWriting.close()
                process.waitUntilExit()
                let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let failed = process.terminationStatus != 0
                if failed { NSLog("DWT blocker %@ failed: %@", args.joined(separator: " "), message) }
                await MainActor.run { SiteBlocker.shared.lastError = failed ? "Couldn't update blocked sites." : nil }
            } catch {
                NSLog("DWT blocker couldn't run: %@", error.localizedDescription)
            }
        }
    }

    // MARK: One-time setup

    func refreshHelperStatus() {
        helperInstalled = FileManager.default.isExecutableFile(atPath: Self.helperPath)
            && FileManager.default.fileExists(atPath: "/etc/sudoers.d/deepworktimer")
    }

    /// Installs the helper and sudoers rule. macOS shows its own admin password prompt.
    func installHelper() {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = support.appendingPathComponent("DeepWorkTimer", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let helper = dir.appendingPathComponent("deepwork-block")
        let installer = dir.appendingPathComponent("install-blocker.sh")
        do {
            try Self.helperScript.write(to: helper, atomically: true, encoding: .utf8)
            try Self.installScript(user: NSUserName(), helper: helper.path).write(to: installer, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Couldn't prepare the installer."
            return
        }
        let source = "do shell script \"/bin/sh \" & quoted form of \"\(installer.path)\" with administrator privileges"
        Task.detached {
            // osascript shows the standard admin password prompt.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let stderr = Pipe()
            process.standardError = stderr
            try? process.run()
            process.waitUntilExit()
            let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let cancelled = message.contains("-128")
            let failed = process.terminationStatus != 0 && !cancelled
            if failed { NSLog("DWT blocker install failed: %@", message) }
            await MainActor.run {
                let blocker = SiteBlocker.shared
                blocker.refreshHelperStatus()
                if failed {
                    blocker.lastError = "Setup failed."
                } else if blocker.helperInstalled {
                    blocker.lastError = nil
                    if blocker.isBlocking { blocker.apply() }
                }
            }
        }
    }

    private static func installScript(user: String, helper: String) -> String {
        """
        #!/bin/sh
        set -e
        mkdir -p /usr/local/libexec
        install -o root -g wheel -m 755 '\(helper)' \(helperPath)
        rule=$(mktemp /tmp/deepworktimer-sudoers.XXXXXX)
        printf '%s ALL=(root) NOPASSWD: %s\\n' '\(user)' '\(helperPath)' > "$rule"
        # Never install a sudoers file that doesn't parse.
        visudo -cf "$rule"
        install -o root -g wheel -m 440 "$rule" /etc/sudoers.d/deepworktimer
        rm -f "$rule"
        """
    }

    /// Runs as root. Only ever writes "0.0.0.0 <domain>" lines between its own
    /// markers, and only for strings that are valid domain names.
    private static let helperScript = #"""
    #!/bin/bash
    # Deep Work Timer site blocker: deepwork-block apply|clear (domains on stdin for apply)
    set -euo pipefail
    HOSTS=/etc/hosts
    BEGIN="# >>> Deep Work Timer"
    END="# <<< Deep Work Timer"
    tmp=$(mktemp /tmp/deepwork-hosts.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$HOSTS" > "$tmp"
    case "${1:-}" in
      apply)
        echo "$BEGIN" >> "$tmp"
        count=0
        while IFS= read -r d || [ -n "$d" ]; do
          d=$(printf '%s' "$d" | tr 'A-Z' 'a-z')
          [ ${#d} -le 253 ] || continue
          [[ "$d" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || continue
          printf '0.0.0.0 %s\n:: %s\n' "$d" "$d" >> "$tmp"
          count=$((count + 1))
          [ $count -lt 5000 ] || break
        done
        echo "$END" >> "$tmp"
        ;;
      clear) ;;
      *) echo "usage: deepwork-block apply|clear" >&2; exit 2 ;;
    esac
    cat "$tmp" > "$HOSTS"
    dscacheutil -flushcache
    killall -HUP mDNSResponder 2>/dev/null || true
    """#
}
