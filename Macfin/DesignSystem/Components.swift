import SwiftUI

/// The single filled action of a screen: white capsule, black label.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Tokens.Color.onAction)
            .padding(.horizontal, 22)
            .frame(height: Tokens.Size.button)
            .background(Capsule().fill(Tokens.Color.action))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? Tokens.Motion.pressScale : 1)
            .animation(Tokens.Motion.hover, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Posters and stills: grow and lift on hover, shrink slightly on press.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration)
    }

    private struct CardBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? Tokens.Motion.pressScale : (hovering ? Tokens.Motion.hoverScale : 1))
                .shadow(color: .black.opacity(hovering ? 0.5 : 0), radius: 16, y: 10)
                .animation(Tokens.Motion.hover, value: hovering)
                .animation(Tokens.Motion.hover, value: configuration.isPressed)
                .onHover { hovering = $0 && !Self.ignoresPointer }
        }

        #if DEBUG
        private static var ignoresPointer: Bool { DemoAutomation.isRunning }
        #else
        private static var ignoresPointer: Bool { false }
        #endif
    }
}

/// Playback progress laid on an image.
struct ProgressCapsule: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.Color.track)
                Capsule().fill(Tokens.Color.action)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: Tokens.Size.progress)
    }
}

/// Image loaded from the Jellyfin server, kept in memory once decoded.
struct RemoteImage: View {
    let url: URL?
    var fit = false

    @State private var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(fit ? SwiftUI.Color.clear : Tokens.Color.surface)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: fit ? .fit : .fill)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                if let cached = ImagePipeline.shared.cached(url) { image = cached; return }
                let loaded = await ImagePipeline.shared.image(for: url)
                withAnimation(Tokens.Motion.fade) { image = loaded }
            }
    }
}

@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()
    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func image(for url: URL) async -> NSImage? {
        if let hit = cached(url) { return hit }
        if let task = inFlight[url] { return await task.value }
        let task = Task { () -> NSImage? in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
