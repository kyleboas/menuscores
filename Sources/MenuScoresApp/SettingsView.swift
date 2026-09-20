import SwiftUI
import ScoreKit

struct SettingsView: View {
    @Bindable var store: ScoreStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leagues").font(.headline)
            ForEach(League.defaults) { league in
                Toggle(league.name, isOn: binding(for: league))
                    .toggleStyle(.checkbox)
            }

            Divider()

            Toggle("Show only my favorite teams", isOn: $store.preferences.favoritesOnly)
                .toggleStyle(.checkbox)

            if store.preferences.favoritesOnly {
                Text(favoritesSummary)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }

            Text("Click a team in the list to favorite it.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var favoritesSummary: String {
        let n = store.preferences.favoriteTeamIDs.count
        return n == 0 ? "No favorites yet — everything is hidden."
                      : "\(n) team\(n == 1 ? "" : "s") favorited."
    }

    private func binding(for league: League) -> Binding<Bool> {
        Binding(
            get: { store.preferences.enabledLeagueIDs.contains(league.id) },
            set: { on in
                if on { store.preferences.enabledLeagueIDs.insert(league.id) }
                else { store.preferences.enabledLeagueIDs.remove(league.id) }
            }
        )
    }
}
