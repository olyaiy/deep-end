import Combine
import SwiftUI

/// The menu bar item and its window. Built on NSStatusItem rather than
/// SwiftUI's MenuBarExtra so the window can be opened from code (MenuBarExtra
/// has no API for that), e.g. when a timer finishes.
@MainActor
final class MenuBarController: NSObject {
    static private(set) var shared: MenuBarController?

    private let timer: TimerModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: MenuPanel
    private var clickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    var isOpen: Bool { panel.isVisible }

    init(timer: TimerModel) {
        self.timer = timer
        let host = NSHostingController(rootView:
            MenuContentView()
                .environmentObject(timer)
                .background(VisualEffectBackground())
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        host.sizingOptions = .preferredContentSize
        panel = MenuPanel(contentViewController: host)
        super.init()
        Self.shared = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        updateButton()

        // objectWillChange fires before the change lands, so read on the next turn.
        timer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        // Keep the window pinned under the menu bar if its content changes height.
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: panel)
            .sink { [weak self] _ in self?.position() }
            .store(in: &cancellables)
    }

    // MARK: Opening and closing

    /// Shows the window. `focus: false` shows it without taking the keyboard
    /// from whatever you're typing in (used when a timer finishes on its own).
    func show(focus: Bool = true) {
        position()
        if focus {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        statusItem.button?.highlight(true)
        MusicController.shared.setVisible(true)
        guard clickMonitor == nil else { return }
        // Close on a click anywhere else, like a menu.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        MusicController.shared.setVisible(false)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    func toggle() {
        isOpen ? close() : show()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            close()
            showContextMenu()
        } else {
            toggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Deep Work Timer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() { SettingsWindow.show() }

    /// Just under the status item, kept on screen.
    private func position() {
        guard let buttonFrame = statusItem.button?.window?.frame,
              let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: buttonFrame.minY - 6))
    }

    // MARK: Status item

    private func updateButton() {
        guard let button = statusItem.button else { return }
        if timer.phase == .idle {
            let image = NSImage(systemSymbolName: timer.pendingBreak == nil ? "timer" : "cup.and.saucer",
                                accessibilityDescription: "Deep Work Timer")
            image?.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = MenuBarIcon.ring(remaining: 1 - timer.progress, paused: timer.isPaused)
            button.title = UserDefaults.standard.bool(forKey: Prefs.Key.showTimeInMenuBar) ? " " + timer.displayTime : ""
        }
    }
}

/// A borderless panel that can take keyboard input (for the task field and
/// shortcuts) without making the app take over the screen.
private final class MenuPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }

    /// Escape closes it, like a menu.
    override func cancelOperation(_ sender: Any?) {
        MainActor.assumeIsolated { MenuBarController.shared?.close() }
    }
}

/// The frosted menu material behind the popover.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
