import SwiftUI
import AppKit

/// Crests and league badges are small, fixed CDN assets reused across every
/// row and refresh, so they are cached in memory for the life of the process.
/// Nothing is written to disk and no cookies are kept.
@MainActor
public final class ImageCache {
    public static let shared = ImageCache()
    private var images: [URL: NSImage] = [:]
    private var inFlight: Set<URL> = []

    public func cached(_ url: URL) -> NSImage? { images[url] }

    @discardableResult public func load(_ url: URL) async -> NSImage? {
        if let i = images[url] { return i }
        guard !inFlight.contains(url) else { return nil }
        inFlight.insert(url)
        defer { inFlight.remove(url) }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let image = NSImage(data: data) else { return nil }
        images[url] = image
        return image
    }
}

/// A crest that degrades to a neutral placeholder rather than collapsing the
/// row's layout when the image is missing or still loading.
@MainActor
struct Crest: View {
    let url: URL?
    let size: CGFloat

    @State private var image: NSImage?

    init(url: URL?, size: CGFloat = 18) {
        self.url = url
        self.size = size
        // Seed from the cache synchronously so an already-loaded crest is
        // present on the very first render pass (and so offscreen rendering,
        // which never runs .task, still draws it).
        _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.18))
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            guard let url else { return }
            if let c = ImageCache.shared.cached(url) { image = c; return }
            image = await ImageCache.shared.load(url)
        }
    }
}
