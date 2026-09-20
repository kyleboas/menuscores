import SwiftUI
import ScoreKit

@main
struct MenuScoresApp: App {
    @State private var store = ScoreStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store)
        } label: {
            Text(MenuBarTitle.text(for: store.pinned, zone: store.zone))
        }
        .menuBarExtraStyle(.window)
    }
}

enum Format {
    static func clock(_ d: Date) -> String { MenuBarTitle.clock(d) }

    static func dayHeading(_ day: CivilDay, zone: TimeZone, now: Date = Date()) -> String {
        let today = CivilDay.today(in: zone, now: now)
        if day == today.adding(days: 1, in: zone) { return "Tomorrow" }
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "EEEE d MMM"
        return f.string(from: day.startOfDay(in: zone))
    }
}
