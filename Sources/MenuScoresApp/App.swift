import SwiftUI
import AppKit
import ScoreKit
import MenuScoresUI

/// Diagnostics go to stderr, which is unbuffered, so they survive being
/// redirected to a file when the bundle is launched from a terminal.
func diag(_ message: String) {
    FileHandle.standardError.write(Data(("[MenuScores] " + message + "\n").utf8))
}

/// An explicit NSStatusItem + NSPopover rather than SwiftUI's `MenuBarExtra`.
///
/// `MenuBarExtra` gives no way to confirm the item was created or where it
/// landed, which makes "I can't find it" impossible to diagnose. Owning the
/// status item means the icon, the title and the popover are all under our
/// control, and the item's frame can be logged at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ScoreStore()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var titleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            // An icon means the item stays findable even when the title is
            // short, and identifiable among a crowded menu bar.
            button.image = NSImage(systemSymbolName: "sportscourt.fill",
                                   accessibilityDescription: "MenuScores")
            button.imagePosition = .imageLeading
            button.title = " " + MenuBarTitle.loading
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "MenuScores — click for today's games"
        }

        let popover = NSPopover()
        popover.behavior = .transient          // closes when you click away
        popover.animates = false
        let hosting = NSHostingController(rootView: DropdownView(store: store))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover

        diag("launched; starting refresh")
        store.start()
        startTitleUpdates()

        // Proof the item exists and where it is, for diagnosing a menu bar
        // that looks empty.
        if let frame = item.button?.window?.frame {
            let screen = NSScreen.main?.frame ?? .zero
            diag("status item at x=\(Int(frame.origin.x)) y=\(Int(frame.origin.y)) "
                 + "w=\(Int(frame.width)) visible=\(item.isVisible) "
                 + "screen=\(Int(screen.width))x\(Int(screen.height))")
        } else {
            diag("WARNING: status item has no button window — the menu bar may be full")
        }

        if ProcessInfo.processInfo.environment["MENUSCORES_SELFTEST"] == "1" {
            runSelfTest()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [store] _ in
            MainActor.assumeIsolated { store.start() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        titleTimer?.invalidate()
        store.stop()
    }

    /// Drives the item the way a click would and reports what happened, so a
    /// menu bar that "does nothing" can be diagnosed without a human clicking.
    private func runSelfTest() {
        Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                diag("title now: \"\(self.statusItem?.button?.title ?? "nil")\"")
                diag("sections: \(self.store.sections.count), "
                     + "games: \(self.store.sections.reduce(0) { $0 + $1.games.count })")
                self.togglePopover(nil)
                diag("popover shown after click: \(self.popover?.isShown ?? false)")
                if let size = self.popover?.contentViewController?.view.fittingSize {
                    diag("popover content size: \(Int(size.width))x\(Int(size.height))")
                }
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// The title tracks the pinned game. A one-second tick is cheap and avoids
    /// tying menu bar text to the observation graph.
    private func startTitleUpdates() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let button = self.statusItem?.button else { return }
                let text = MenuBarTitle.text(for: self.store.pinned,
                                             zone: self.store.zone,
                                             hasLoaded: self.store.hasLoaded)
                if button.title != " " + text { button.title = " " + text }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }
}

@main
struct MenuScoresApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The status item is created by the delegate; this scene stays empty
        // so no window is ever shown.
        Settings { EmptyView() }
    }
}
