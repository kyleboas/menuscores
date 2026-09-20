import SwiftUI
import ScoreKit

/// Two tabs: which leagues to follow, and which teams are favourites.
/// Shown in the standard macOS Settings window, not as a sheet over the
/// popover — a sheet presented from a popover-hosted view never appeared.
public struct SettingsView: View {
    @Bindable var store: ScoreStore
    public init(store: ScoreStore) { self.store = store }

    public var body: some View {
        TabView {
            LeaguesTab(store: store)
                .tabItem { Label("Leagues", systemImage: "list.bullet") }
            FavoritesTab(store: store)
                .tabItem { Label("Favorites", systemImage: "star") }
        }
        .frame(width: 420, height: 440)
    }
}

struct LeaguesTab: View {
    @Bindable var store: ScoreStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leagues to follow")
                .font(.headline)
            Text("The dropdown shows a section for each of these that has games today.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(League.defaults) { league in
                        Toggle(isOn: binding(for: league)) {
                            HStack(spacing: 8) {
                                Crest(url: league.badge(dark: colorScheme == .dark), size: 16)
                                Text(league.displayName)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
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

struct FavoritesTab: View {
    @Bindable var store: ScoreStore
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show only my favorite teams", isOn: $store.preferences.favoritesOnly)
                .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search teams", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if store.loadingTeams && store.teamsByLeague.isEmpty {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading teams…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.preferences.leagues.isEmpty {
                Text("Enable a league first, on the Leagues tab.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(store.preferences.leagues) { league in
                            let teams = filtered(league)
                            if !teams.isEmpty {
                                Section {
                                    ForEach(teams, id: \.id) { team in
                                        TeamToggleRow(store: store, team: team)
                                    }
                                } header: {
                                    Text(league.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4)
                                        .background(.background)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .task { await store.loadTeams() }
        // Enabling a league in the other tab should pull its teams in too.
        .onChange(of: store.preferences.enabledLeagueIDs) { _, _ in
            Task { await store.loadTeams() }
        }
    }

    private func filtered(_ league: League) -> [Team] {
        let teams = store.teamsByLeague[league.id] ?? []
        guard !search.isEmpty else { return teams }
        return teams.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

struct TeamToggleRow: View {
    @Bindable var store: ScoreStore
    let team: Team

    var body: some View {
        Button {
            store.toggleFavorite(team)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: store.isFavorite(team) ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(store.isFavorite(team) ? .yellow : .secondary)
                Crest(url: team.crest, size: 16)
                Text(team.name).font(.system(size: 12))
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
