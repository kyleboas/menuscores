import SwiftUI
import AppKit
import ScoreKit
import MenuScoresUI

// Renders the dropdown offscreen to a PNG, using real data from the feed.
// Lets the interface be checked without screen-recording permission, and
// catches layout regressions that a unit test cannot see.
//
//   swift run render-preview [out.png] [light|dark]

@MainActor
func run() async -> Int32 {
    let args = CommandLine.arguments.dropFirst()
    let out = args.first.map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: "dropdown.png")
    let dark = !(args.dropFirst().first == "light")

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let store = ScoreStore()
    print("Fetching \(store.preferences.leagues.count) league(s) for \(store.today)…")
    await store.refresh()

    if let w = store.freshness.warning() {
        print("WARNING: \(w)")
    }
    let sections = store.sections
    print("\(sections.count) league section(s), \(sections.reduce(0) { $0 + $1.games.count }) game(s)")

    // Pre-warm every crest and badge so the synchronous render draws them.
    var urls: [URL] = []
    for s in sections {
        if let b = s.league.badge(dark: dark) { urls.append(b) }
        for g in s.games {
            if let c = g.home.crest { urls.append(c) }
            if let c = g.away.crest { urls.append(c) }
        }
    }
    var seen = Set<URL>()
    let unique = urls.filter { seen.insert($0).inserted }
    print("Loading \(unique.count) image(s)…")
    for u in unique {
        await ImageCache.shared.load(u)
    }

    // Composed without the scroll containers: ImageRenderer does not lay out
    // ScrollView content, so rendering DropdownView directly yields a blank
    // middle. This mirrors what the real dropdown shows, fully expanded.
    let view = SectionList(store: store)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    .frame(width: 340)
    .environment(\.colorScheme, dark ? .dark : .light)
    .background(dark ? Color(white: 0.08) : Color(white: 0.97))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("RENDER FAILED")
        return 1
    }
    do {
        try png.write(to: out)
    } catch {
        print("WRITE FAILED: \(error)")
        return 1
    }
    print("Wrote \(out.path) — \(Int(image.size.width))x\(Int(image.size.height)) pt")
    return 0
}

exit(await run())
