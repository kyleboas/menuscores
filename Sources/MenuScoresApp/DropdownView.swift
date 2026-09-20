import SwiftUI
import Combine
import ScoreKit

struct DropdownView: View {
    @Bindable var store: ScoreStore
    @State private var showingSettings = false
    /// Drives the "updated N seconds ago" line without re-fetching anything.
    @State private var tick = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            DayStrip(store: store)
            Divider().opacity(0.5)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.sections.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.sections, id: \.league.id) { section in
                            LeagueCard(store: store,
                                       league: section.league,
                                       games: section.games)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 460)

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 340)
        .onReceive(ticker) { tick = $0 }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, isPresented: $showingSettings)
        }
    }

    // Freshness is always on screen, so a cached score can never read as live.
    private var statusBar: some View {
        HStack(spacing: 6) {
            if let warning = store.freshness.warning(now: tick) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9)).foregroundStyle(.orange)
                Text(warning)
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.freshness.ageDescription(now: tick))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if store.isRefreshing {
                ProgressView().controlSize(.mini)
            } else {
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 7)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No games")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(store.preferences.leagues.isEmpty
                 ? "No leagues selected — open Settings."
                 : "Nothing scheduled on \(store.label(for: store.selectedDay).lowercased()).")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.plain).font(.system(size: 11))
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// MARK: - Day strip

/// Yesterday / Today / Tomorrow / dates, scrolled so the selection is visible.
struct DayStrip: View {
    @Bindable var store: ScoreStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(store.dayStrip, id: \.self) { day in
                        let selected = day == store.selectedDay
                        Button {
                            store.selectedDay = day
                        } label: {
                            Text(store.label(for: day))
                                .font(.system(size: 13,
                                              weight: selected ? .bold : .medium))
                                .foregroundStyle(selected ? Color.primary : Color.secondary)
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .id(day)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .onAppear { proxy.scrollTo(store.selectedDay, anchor: .center) }
            .onChange(of: store.selectedDay) { _, new in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }
}

// MARK: - League card

struct LeagueCard: View {
    @Bindable var store: ScoreStore
    let league: League
    let games: [Game]

    private var collapsed: Bool { store.preferences.isCollapsed(league) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.preferences.toggleCollapsed(league)
                }
            } label: {
                HStack(spacing: 8) {
                    Crest(url: league.badge, size: 17)
                    Text(league.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 180 : 0))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    if index > 0 {
                        Divider().opacity(0.35).padding(.leading, 12)
                    }
                    GameRow(game: game, zone: store.zone)
                }
            }
        }
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Game row

/// [status] [home name] [crest]  score/time  [crest] [away name]
struct GameRow: View {
    let game: Game
    let zone: TimeZone

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(game: game)
                .frame(width: 30, alignment: .leading)

            Text(game.home.name)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Crest(url: game.home.crest, size: 18)

            centre
                .frame(width: 54)

            Crest(url: game.away.crest, size: 18)

            Text(game.away.name)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder private var centre: some View {
        if let score = game.scoreLine {
            Text(score)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        } else if game.state == .postponed || game.state == .canceled {
            Text("—").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Text(MenuBarTitle.clock(game.start, zone: zone))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

/// Green pill while live, muted pill for a finished game, nothing before
/// kickoff, orange when the game is not going ahead.
struct StatusBadge: View {
    let game: Game

    var body: some View {
        if let text = game.badgeText {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(foreground)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(background))
        }
    }

    private var background: Color {
        switch game.state {
        case .live: return .green
        case .postponed, .canceled, .unknown: return .orange.opacity(0.85)
        default: return Color.primary.opacity(0.12)
        }
    }

    private var foreground: Color {
        switch game.state {
        case .live, .postponed, .canceled, .unknown: return .black
        default: return .secondary
        }
    }
}
