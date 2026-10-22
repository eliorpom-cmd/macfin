import AVKit
import SwiftUI

/// QuickTime-style player: translucent title bar on top, compact glass control bar at the bottom.
struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    let playback: PlaybackSession
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var fullScreen = false
    @State private var window: NSWindow?
    @State private var lastHover = Date.distantPast
    @State private var controlsPinned = false
    @FocusState private var focused: Bool

    private var showsChrome: Bool { chromeVisible || !playback.isPlaying || controlsPinned }

    var body: some View {
        ZStack {
            Tokens.Color.base.ignoresSafeArea()
            VideoSurface(playback: playback, onDoubleClick: toggleFullScreen).ignoresSafeArea()
            WindowReader { window = $0 }.frame(width: 0, height: 0)

            VStack(spacing: 0) {
                if !fullScreen { TitleBar(title: playback.item.episodeLine.map { "\(playback.item.displayTitle) — \($0)" } ?? playback.item.name) }
                Spacer()
                PlayerControls(playback: playback, pinned: $controlsPinned, close: close, toggleFullScreen: toggleFullScreen)
                    .padding(.bottom, 24)
            }
            .ignoresSafeArea()
            .opacity(showsChrome ? 1 : 0)
        }
        .animation(Tokens.Motion.fade, value: showsChrome)
        .onContinuousHover { _ in
            // Throttled: resetting the hide timer on every mouse event made the controls sluggish.
            guard Date.now.timeIntervalSince(lastHover) > 0.25 else { return }
            lastHover = .now
            showChrome()
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.space) { playback.togglePlay(); showChrome(); return .handled }
        .onKeyPress(.leftArrow) { playback.skip(-10); showChrome(); return .handled }
        .onKeyPress(.rightArrow) { playback.skip(10); showChrome(); return .handled }
        .onKeyPress(.escape) { fullScreen ? toggleFullScreen() : close(); return .handled }
        .onKeyPress(characters: ["f"]) { _ in toggleFullScreen(); return .handled }
        .onAppear { focused = true; showChrome() }
        .onDisappear { hideTask?.cancel(); setWindowButtonsHidden(false) }
        .onChange(of: showsChrome) { _, visible in setWindowButtonsHidden(!visible) }
        .onChange(of: controlsPinned) { _, pinned in if !pinned { showChrome() } }
        .onChange(of: window) { _, _ in setWindowButtonsHidden(!showsChrome) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in fullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in fullScreen = false }
    }

    private func close() { Task { await model.closePlayer() } }

    private func toggleFullScreen() { window?.toggleFullScreen(nil) }

    private func showChrome() {
        chromeVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: Tokens.Motion.chromeDelay)
            guard !Task.isCancelled else { return }
            chromeVisible = false
            if playback.isPlaying { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }

    /// Traffic lights appear and disappear with the title bar.
    private func setWindowButtonsHidden(_ hidden: Bool) {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.animator().alphaValue = hidden ? 0 : 1
            }
        }
    }
}

/// Translucent band behind the traffic lights with the centered title, like QuickTime Player.
private struct TitleBar: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Tokens.Color.text2)
            .lineLimit(1)
            .padding(.horizontal, 90)
            .frame(maxWidth: .infinity)
            .frame(height: Tokens.Size.titleBar)
            .background(Tokens.Color.titleBar)
            .overlay(alignment: .bottom) { Rectangle().fill(Tokens.Color.hairline).frame(height: 1) }
            .allowsHitTesting(false)
    }
}

/// Compact glass bar: back, full screen | play/pause | picture in picture, speed — then the scrubber.
struct PlayerControls: View {
    @Bindable var playback: PlaybackSession
    @Binding var pinned: Bool
    let close: () -> Void
    let toggleFullScreen: () -> Void
    @State private var scrubbing: Double?
    @State private var hovering = false
    @State private var speedOpen = false
    @State private var sliderFrame: CGRect = .zero
    @State private var hoverX: CGFloat?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 4) {
                    icon("chevron.backward", help: "Back to Library (Esc)", action: close)
                    icon("arrow.up.left.and.arrow.down.right", help: "Full Screen (F)", action: toggleFullScreen)
                    Spacer()
                    icon("pip.enter", help: "Picture in Picture") { playback.togglePictureInPicture() }
                        .disabled(playback.pictureInPicture == nil)
                    speedMenu
                    if playback.next != nil {
                        icon("forward.end.fill", help: "Next Episode") { Task { await AppModel.shared.playNext() } }
                    }
                }
                Button { playback.togglePlay() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 40, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Play/Pause (Space)")
            }
            .foregroundStyle(Tokens.Color.text)

            HStack(spacing: 10) {
                Text(Self.clock(scrubbing ?? playback.time)).frame(minWidth: 44, alignment: .leading)
                Slider(value: Binding(get: { scrubbing ?? playback.time }, set: { scrubbing = $0 }),
                       in: 0...max(playback.duration, 1)) { editing in
                    guard !editing, let target = scrubbing else { return }
                    Task { await playback.seek(to: target); scrubbing = nil }
                }
                .controlSize(.small)
                .tint(Tokens.Color.action)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("controlBar")) } action: { sliderFrame = $0 }
                .onContinuousHover { phase in
                    if case .active(let point) = phase { hoverX = point.x } else { hoverX = nil }
                }
                Text("-" + Self.clock(max(playback.duration - (scrubbing ?? playback.time), 0))).frame(minWidth: 44, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(Tokens.Color.text2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: Tokens.Size.controlBar)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Tokens.Radius.controlBar))
        .coordinateSpace(.named("controlBar"))
        .overlay(alignment: .topLeading) { preview }
        .onHover { hovering = $0; pinned = hovering || speedOpen }
        .onChange(of: speedOpen) { _, open in pinned = hovering || open }
    }

    /// Time under the pointer (or being scrubbed), for the thumbnail preview.
    private var previewTime: Double? {
        if let scrubbing { return scrubbing }
        #if DEBUG
        if let forced = AppModel.shared.demoPreviewTime { return forced }
        #endif
        guard let hoverX, sliderFrame.width > 0 else { return nil }
        return Double(min(max(hoverX / sliderFrame.width, 0), 1)) * playback.duration
    }

    @ViewBuilder private var preview: some View {
        if let time = previewTime, let info = playback.item.trickplayInfo {
            let size = CGSize(width: Tokens.Size.preview, height: Tokens.Size.preview * CGFloat(info.height) / CGFloat(info.width))
            let x = sliderFrame.minX + sliderFrame.width * CGFloat(time / max(playback.duration, 1)) - size.width / 2
            VStack(spacing: 6) {
                TrickplayThumbnail(item: playback.item, client: playback.client, info: info, time: time)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.preview))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.preview).stroke(Tokens.Color.hairline))
                Text(Self.clock(time))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Tokens.Color.text)
            }
            .offset(x: min(max(x, 0), Tokens.Size.controlBar - size.width), y: -(size.height + 30))
            .allowsHitTesting(false)
        }
    }

    private var speedMenu: some View {
        Button { speedOpen.toggle() } label: {
            Text(Self.rateLabel(playback.rate))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(minWidth: 32, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Playback Speed")
        .popover(isPresented: $speedOpen, arrowEdge: .top) {
            VStack(spacing: 2) {
                ForEach(Self.rates.reversed(), id: \.self) { rate in
                    Button { playback.rate = rate; speedOpen = false } label: {
                        HStack {
                            Text(Self.rateLabel(rate)).monospacedDigit()
                            Spacer()
                            if rate == playback.rate { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(width: 96, height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
    }

    private func icon(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    static func rateLabel(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2)).locale(.autoupdatingCurrent)) + "×"
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One thumbnail cut out of a Jellyfin trickplay tile sheet.
struct TrickplayThumbnail: View {
    let item: Item
    let client: JellyfinClient
    let info: TrickplayInfo
    let time: Double

    @State private var sheet: NSImage?
    @State private var sheetIndex: Int?

    private var thumbIndex: Int { min(Int(time * 1000) / max(info.interval, 1), max(info.thumbnailCount - 1, 0)) }
    private var perSheet: Int { info.tileWidth * info.tileHeight }

    var body: some View {
        GeometryReader { geo in
            let local = thumbIndex % perSheet
            let col = CGFloat(local % info.tileWidth), row = CGFloat(local / info.tileWidth)
            ZStack(alignment: .topLeading) {
                Tokens.Color.surface
                if let sheet, sheetIndex == thumbIndex / perSheet {
                    Image(nsImage: sheet)
                        .resizable()
                        .frame(width: geo.size.width * CGFloat(info.tileWidth), height: geo.size.height * CGFloat(info.tileHeight))
                        .offset(x: -col * geo.size.width, y: -row * geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .task(id: thumbIndex / perSheet) {
            let index = thumbIndex / perSheet
            let image = await ImagePipeline.shared.image(for: client.trickplayTileURL(item, width: info.width, index: index))
            sheet = image; sheetIndex = index
        }
    }
}

/// Gives the SwiftUI view access to its hosting window.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

final class VideoView: NSView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }
}

/// Bare AVPlayerLayer (no AVKit controls) so picture in picture can be driven from SwiftUI.
struct VideoSurface: NSViewRepresentable {
    let playback: PlaybackSession
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> VideoView {
        let view = VideoView()
        view.onDoubleClick = onDoubleClick
        let layer = AVPlayerLayer(player: playback.player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: layer)
            DispatchQueue.main.async { playback.pictureInPicture = pip }
        }
        return view
    }

    func updateNSView(_ view: VideoView, context: Context) { view.onDoubleClick = onDoubleClick }
}
