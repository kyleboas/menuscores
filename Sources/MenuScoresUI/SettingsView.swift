import SwiftUI
import ScoreKit

/// Two tabs: which leagues to show in full, and which teams to follow
/// wherever they play.
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
                .tabItem { Label("Teams", systemImage: "star") }
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
                    ForEach(groups, id: \.title) { group in
                        Text(group.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, group.title == groups.first?.title ? 0 : 6)
                        ForEach(group.leagues) { league in
                            Toggle(isOn: binding(for: league)) {
                                HStack(spacing: 8) {
                                    Crest(url: league.badge(dark: colorScheme == .dark), size: 16)
                                    Text(league.displayName)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    /// Club soccer, national teams, then everything else, so the twenty-odd
    /// entries read as three short lists.
    private var groups: [(title: String, leagues: [League])] {
        let all = League.defaults
        return [
            ("Club soccer", all.filter { $0.sport == "soccer" && !$0.isInternational }),
            ("International", all.filter(\.isInternational)),
            ("Other sports", all.filter { $0.sport != "soccer" }),
        ]
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
            Toggle("Show only teams I follow", isOn: $store.preferences.favoritesOnly)
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
            } else {
                Text("A starred team's games show in every competition it plays in — cups, Europe, friendlies — even ones not enabled under Leagues.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.title) { group in
                            Section {
                                ForEach(group.teams, id: \.id) { team in
                                    TeamToggleRow(store: store, team: team)
                                }
                            } header: {
                                Text(group.title)
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
        .padding(18)
        .task { await store.loadTeams() }
        // Enabling a league in the other tab should pull its teams in too.
        .onChange(of: store.preferences.enabledLeagueIDs) { _, _ in
            Task { await store.loadTeams() }
        }
    }

    /// One entry per team, however many competitions list it: England is in
    /// friendlies, the Nations League and qualifying, but is one team to
    /// follow. Followed teams first, then clubs, national teams, and each
    /// other sport's league.
    private var groups: [(title: String, teams: [Team])] {
        func matches(_ t: Team) -> Bool {
            search.isEmpty || t.name.localizedCaseInsensitiveContains(search)
        }
        var placed = Set<String>()
        var out: [(title: String, teams: [Team])] = []
        func add(_ title: String, _ teams: [Team]) {
            let list = teams.filter { matches($0) && placed.insert($0.id).inserted }
                            .sorted { $0.name < $1.name }
            if !list.isEmpty { out.append((title, list)) }
        }
        add("Following", store.followedTeams)
        let leagues = store.preferences.leagues
        func teams(_ ls: [League]) -> [Team] {
            ls.flatMap { store.teamsByLeague[$0.id] ?? [] }
        }
        let national = teams(leagues.filter(\.isInternational))
        let clubs = teams(leagues.filter { $0.sport == "soccer" && !$0.isInternational })
        add("Clubs", clubs)
        add("National teams", national)
        for l in leagues where l.sport != "soccer" {
            add(l.name, store.teamsByLeague[l.id] ?? [])
        }
        return out
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
