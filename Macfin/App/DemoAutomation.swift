#if DEBUG
import AppKit
import SwiftUI

/// Debug-only hooks that drive the app from environment variables, so `scripts/screenshots.sh`
/// can capture each screen against the demo server without the keyboard, the mouse or the keychain.
///
/// - `MACFIN_DEMO_SERVER`, `MACFIN_DEMO_USER`, `MACFIN_DEMO_PASSWORD`: signs in for this launch only
///   (nothing is written to the keychain).
/// - `MACFIN_DEMO_WINDOW`: content size, for example `1440x900`.
/// - `MACFIN_DEMO_SCREEN`: `home`, `grid`, `detail:<movie name>` or `player:<movie name>@<seconds>`.
/// - `MACFIN_DEMO_PREVIEW`: in the player, shows the trickplay preview at this fraction of the movie.
enum DemoAutomation {
    private static let env = ProcessInfo.processInfo.environment

    /// True when these hooks drive the app: cards then ignore the real pointer, so screenshots don't
    /// catch a hover effect wherever the mouse happens to be.
    static let isRunning = env["MACFIN_DEMO_SERVER"] != nil

    static func run(_ model: AppModel) async {
        guard let server = env["MACFIN_DEMO_SERVER"].flatMap(URL.init(string:)),
              let user = env["MACFIN_DEMO_USER"] else { return }
        resizeWindow()
        let client = JellyfinClient(server: server)
        guard let credentials = try? await client.authenticate(username: user, password: env["MACFIN_DEMO_PASSWORD"] ?? "") else {
            print("DemoAutomation: sign-in failed")
            return
        }
        model.useDemoSession(credentials)
        await model.refresh()
        try? await Task.sleep(for: .seconds(1))
        resizeWindow()

        let screen = env["MACFIN_DEMO_SCREEN"] ?? "home"
        if screen == "grid" {
            withAnimation(nil) { model.homeScroll.scrollTo(id: HomeAnchor.recentlyAdded, anchor: .top) }
            try? await Task.sleep(for: .milliseconds(500))
            // The home view runs under the toolbar: move back down so the shelf title clears it.
            scrollBy(-50)
        } else if screen.hasPrefix("detail:"), let item = find(String(screen.dropFirst(7)), in: model) {
            model.openDetail(item)
        } else if screen.hasPrefix("player:") {
            let spec = screen.dropFirst(7).split(separator: "@", maxSplits: 1)
            guard let name = spec.first, let item = find(String(name), in: model) else { return }
            model.play(item, fromStart: true)
            try? await Task.sleep(for: .seconds(2))
            guard let playback = model.playback else { return }
            playback.player.pause()
            if spec.count > 1, let seconds = Double(spec[1]) { await playback.seek(to: seconds) }
            if let fraction = env["MACFIN_DEMO_PREVIEW"].flatMap(Double.init) {
                model.demoPreviewTime = fraction * playback.duration
            }
        }
    }

    private static func find(_ name: String, in model: AppModel) -> Item? {
        model.movies.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Scrolls the window's main scroll view by `delta` points (negative moves toward the top).
    private static func scrollBy(_ delta: CGFloat) {
        guard let root = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.contentView,
              let scrollView = scrollViews(in: root).max(by: { $0.frame.height < $1.frame.height }) else { return }
        let clip = scrollView.contentView
        let flipped = scrollView.documentView?.isFlipped ?? true
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + (flipped ? delta : -delta)))
        scrollView.reflectScrolledClipView(clip)
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        let own = (view as? NSScrollView).map { [$0] } ?? []
        return own + view.subviews.flatMap(scrollViews(in:))
    }

    private static func resizeWindow() {
        guard let spec = env["MACFIN_DEMO_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), spec.count == 2,
              let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        window.setContentSize(NSSize(width: spec[0], height: spec[1]))
    }
}
#endif
