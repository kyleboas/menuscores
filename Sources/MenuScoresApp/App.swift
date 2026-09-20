import SwiftUI
import AppKit
import ScoreKit

/// The store is owned by the app delegate, not by the dropdown.
///
/// With `.menuBarExtraStyle(.window)` the dropdown's content view is not
/// created until the user actually opens it. Starting the refresh loop from
/// that view therefore meant nothing was ever fetched until the first click,
/// and the menu bar sat on its placeholder. Polling has to begin at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ScoreStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()

        // Waking from sleep leaves whatever we last fetched on screen, which
        // may be hours old. Refresh immediately rather than waiting out the
        // remainder of the poll interval.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [store] _ in
            MainActor.assumeIsolated {
                store.selectedDay = CivilDay.today(in: store.zone)
                store.start()       // restart the cadence from now
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}

@main
struct MenuScoresApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: delegate.store)
        } label: {
            Text(MenuBarTitle.text(for: delegate.store.pinned,
                                   zone: delegate.store.zone,
                                   hasLoaded: delegate.store.hasLoaded))
        }
        .menuBarExtraStyle(.window)
    }
}
