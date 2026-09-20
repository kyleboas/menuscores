import SwiftUI
import ScoreKit

struct SettingsView: View {
    @Bindable var store: ScoreStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leagues").font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(League.defaults) { league in
                        Toggle(isOn: binding(for: league)) {
                            HStack(spacing: 7) {
                                Crest(url: league.badge, size: 15)
                                Text(league.displayName).font(.system(size: 12))
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(height: 210)

            Divider()

            Toggle("Show only my favorite teams", isOn: $store.preferences.favoritesOnly)
                .toggleStyle(.checkbox)
            Text(favoritesSummary)
                .font(.system(size: 10)).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var favoritesSummary: String {
        let n = store.preferences.favoriteTeamIDs.count
        if n == 0 {
            return store.preferences.favoritesOnly
                ? "No favorites picked yet, so nothing will show."
                : "No favorites picked yet."
        }
        return "\(n) team\(n == 1 ? "" : "s") favorited."
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
