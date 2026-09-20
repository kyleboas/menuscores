import SwiftUI
import ScoreKit

struct DropdownView: View {
    @Bindable var store: ScoreStore
    @State private var showingSettings = false
    /// Drives the "updated N seconds ago" line without re-fetching anything.
    @State private var tick = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GameSection(title: "Live", games: store.live, zone: store.zone, emptyNote: nil)
                    GameSection(title: "Today", games: store.today, zone: store.zone,
                            emptyNote: store.live.isEmpty ? "No games today" : nil)

                    if !store.upcoming.isEmpty {
                        SectionHeader("Next 7 Days")
                        ForEach(store.upcoming, id: \.day) { entry in
                            Text(Format.dayHeading(entry.day, zone: store.zone, now: tick))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
                            ForEach(entry.games) { GameRow(game: $0, zone: store.zone) }
                        }
                    } else {
                        SectionHeader("Next 7 Days")
                        Text("Nothing scheduled")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 420)

            Divider()
            footer
        }
        .frame(width: 300)
        .onReceive(ticker) { tick = $0 }
        .task { store.start() }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, isPresented: $showingSettings)
        }
    }

    // Freshness is part of the chrome, not an afterthought: it is always on
    // screen, so a cached score can never read as a live one.
    private var header: some View {
        HStack(spacing: 6) {
            if let warning = store.freshness.warning(now: tick) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.system(size: 10))
                Text(warning).font(.system(size: 10)).foregroundStyle(.orange)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(store.freshness.ageDescription(now: tick))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
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
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { showingSettings = true }
                .buttonStyle(.plain).font(.system(size: 11))
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }
}

struct SectionHeader: View {
    let title: String
    init(_ t: String) { title = t }
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }
}

struct GameSection: View {
    let title: String
    let games: [Game]
    let zone: TimeZone
    let emptyNote: String?

    var body: some View {
        if !games.isEmpty {
            SectionHeader(title)
            ForEach(games) { GameRow(game: $0, zone: zone) }
        } else if let note = emptyNote {
            SectionHeader(title)
            Text(note).font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 4)
        }
    }
}

struct GameRow: View {
    let game: Game
    let zone: TimeZone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.compactLine)
                    .font(.system(size: 12, weight: game.isLive ? .semibold : .regular))
                    .monospacedDigit()
                Text(game.league.name)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Text(trailing)
                .font(.system(size: 10))
                .foregroundStyle(trailingColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
    }

    private var trailing: String {
        switch game.state {
        case .live:      return game.statusDetail.isEmpty ? "LIVE" : game.statusDetail
        case .postponed: return "Postponed"
        case .canceled:  return "Canceled"
        case .final:     return game.statusDetail.isEmpty ? "Final" : game.statusDetail
        case .scheduled: return Format.clock(game.start)
        case .unknown:   return game.statusDetail.isEmpty ? "Status unknown" : game.statusDetail
        }
    }

    private var trailingColor: Color {
        switch game.state {
        case .live: return .green
        case .postponed, .canceled, .unknown: return .orange
        default: return .secondary
        }
    }
}
