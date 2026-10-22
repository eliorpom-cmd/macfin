import SwiftUI

enum SortOrder: String, CaseIterable, Identifiable {
    case title, added, year
    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .title: "Title"
        case .added: "Date Added"
        case .year: "Year"
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var sort: SortOrder = .title
    @AppStorage("showsHero") private var showsHero = true

    private var browsing: Bool { search.isEmpty }
    private var heroItem: Item? { browsing && showsHero ? model.featured : nil }

    private var library: [Item] { sorted(browsing ? model.movies : (model.movies + model.series).filter { $0.name.localizedStandardContains(search) }) }

    private func sorted(_ filtered: [Item]) -> [Item] {
        switch sort {
        case .title: return filtered
        case .added: return filtered.sorted { ($0.dateCreated ?? "") > ($1.dateCreated ?? "") }
        case .year: return filtered.sorted { ($0.productionYear ?? 0) > ($1.productionYear ?? 0) }
        }
    }

    var body: some View {
        ZStack {
            libraryView
                .opacity(model.detail == nil ? 1 : 0)
                .allowsHitTesting(model.detail == nil)
            if let detail = model.detail {
                Group {
                    if detail.isSeries { SeriesDetailView(item: detail) } else { MovieDetailView(item: detail) }
                }
                .transition(.page)
                .zIndex(1)
            }
        }
        .toolbar {
            if model.detail != nil {
                ToolbarItem(placement: .navigation) {
                    Button { model.closeDetail() } label: { Label("Back", systemImage: "chevron.left") }
                        .keyboardShortcut(.cancelAction)
                        .help("Back (Esc)")
                }
            } else {
                ToolbarItem {
                    Toggle(isOn: $showsHero.animation(Tokens.Motion.page)) {
                        Label("Featured", systemImage: "rectangle.topthird.inset.filled")
                    }
                    .help(showsHero ? "Hide Featured Movie" : "Show Featured Movie")
                }
                ToolbarItem {
                    Menu {
                        Picker("Sort By", selection: $sort) {
                            ForEach(SortOrder.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private var libraryView: some View {
            @Bindable var model = model
            return ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.section) {
                    if let hero = heroItem {
                        HeroView(item: model.current(hero))
                    }
                    if browsing, !model.resume.isEmpty {
                        Shelf(title: "Continue Watching") {
                            ForEach(model.resume) { StillCard(item: $0) }
                        }
                    }
                    if browsing, !model.upNext.isEmpty {
                        Shelf(title: "Up Next") {
                            ForEach(model.upNext) { StillCard(item: $0) }
                        }
                    }
                    if browsing, !model.latest.isEmpty {
                        Shelf(title: "Recently Added") {
                            ForEach(model.latest) { PosterCard(item: model.current($0)).frame(width: Tokens.Size.posterMin) }
                        }
                        .id(HomeAnchor.recentlyAdded)
                    }
                    if browsing, !model.series.isEmpty {
                        Shelf(title: "TV Shows") {
                            ForEach(sorted(model.series)) { PosterCard(item: $0).frame(width: Tokens.Size.posterMin) }
                        }
                    }
                    PosterGrid(title: browsing ? "All Movies" : "Results", items: library)
                }
                .padding(.bottom, 64)
            }
            .scrollPosition($model.homeScroll)
            .ignoresSafeArea(.container, edges: heroItem == nil ? [] : .top)
            .scrollEdgeEffectHidden(heroItem != nil, for: .top)
            .contentMargins(.top, heroItem == nil ? 12 : 0, for: .scrollContent)
            .background(Tokens.Color.base)
            .overlay { statusOverlay }
    }

    @ViewBuilder private var statusOverlay: some View {
        if let error = model.loadError, model.movies.isEmpty, model.series.isEmpty {
            ContentUnavailableView {
                Label("Library Unavailable", systemImage: "wifi.exclamationmark")
            } description: { Text(error) } actions: {
                Button("Try Again") { Task { await model.refresh() } }.buttonStyle(PrimaryButtonStyle())
            }
        } else if !model.hasLoaded {
            ProgressView()
        } else if model.movies.isEmpty, model.series.isEmpty {
            ContentUnavailableView("No Movies", systemImage: "film", description: Text("Add movies to your Jellyfin library."))
        }
    }
}

// MARK: - Hero

struct HeroView: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        let client = model.client
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: client?.backdropURL(item, width: 2560))
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: Tokens.Color.base.opacity(0.7), location: 0.75), .init(color: Tokens.Color.base, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Tokens.Color.base.opacity(0.7), .clear], startPoint: .leading, endPoint: .center)

            VStack(alignment: .leading, spacing: 14) {
                if item.hasImage("Logo"), let client {
                    RemoteImage(url: client.imageURL(item, "Logo", width: 900), fit: true)
                        .frame(maxWidth: 440, maxHeight: 150, alignment: .bottomLeading)
                } else {
                    Text(item.displayTitle).font(Tokens.Font.hero).foregroundStyle(Tokens.Color.text)
                }
                Text(item.metaLine).font(Tokens.Font.meta).foregroundStyle(Tokens.Color.text2)
                ResumeProgress(item: item)
                if let overview = item.overview {
                    Text(overview).font(Tokens.Font.body).foregroundStyle(Tokens.Color.text2)
                        .lineLimit(3).frame(maxWidth: Tokens.Size.summaryWidth, alignment: .leading)
                }
                PlayButtons(item: item, showsDetails: true)
                    .padding(.top, 6)
            }
            .padding(.horizontal, Tokens.Space.gutter)
            .padding(.bottom, 8)
        }
        .containerRelativeFrame(.vertical) { height, _ in height * Tokens.Size.heroFraction }
        .clipped()
    }
}

/// Play / resume, restart when resumable, details link, watched toggle.
struct PlayButtons: View {
    @Environment(AppModel.self) private var model
    let item: Item
    var showsDetails = false

    var body: some View {
        HStack(spacing: 12) {
            Button { model.play(item) } label: {
                Label(item.canResume ? "Resume" : "Play", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())

            if item.canResume {
                Button { model.play(item, fromStart: true) } label: { Label("Start Over", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.glass).controlSize(.large)
            }
            if showsDetails {
                Button { model.openDetail(item) } label: { Label("Details", systemImage: "info.circle") }
                    .buttonStyle(.glass).controlSize(.large)
            } else {
                Button { Task { await model.setPlayed(item, !item.isPlayed) } } label: {
                    Label(item.isPlayed ? "Watched" : "Mark as Watched", systemImage: item.isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(.glass).controlSize(.large)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

/// "1 hr 12 min left" with a progress bar, only for a started film.
struct ResumeProgress: View {
    let item: Item

    var body: some View {
        if let remaining = item.remainingText {
            HStack(spacing: 10) {
                ProgressCapsule(value: item.progress ?? 0).frame(width: 160)
                Text(remaining).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.text2)
            }
        }
    }
}

// MARK: - Rows and grid

struct Shelf<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Tokens.Font.section).foregroundStyle(Tokens.Color.text)
                .padding(.horizontal, Tokens.Space.gutter)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Tokens.Space.row) { content }
                    .padding(.horizontal, Tokens.Space.gutter)
                    .padding(.vertical, 12)
            }
            .scrollIndicators(.never)
            .scrollClipDisabled()
        }
    }
}

struct PosterGrid: View {
    let title: LocalizedStringKey
    let items: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(Tokens.Font.section).foregroundStyle(Tokens.Color.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Tokens.Size.posterMin, maximum: Tokens.Size.posterMax),
                                         spacing: Tokens.Space.gridH)],
                      alignment: .leading, spacing: Tokens.Space.gridV) {
                ForEach(items) { PosterCard(item: $0) }
            }
        }
        .padding(.horizontal, Tokens.Space.gutter)
    }
}

/// Landscape card of the "Continue Watching" row: a click resumes playback.
struct StillCard: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        Button { model.play(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                RemoteImage(url: model.client?.stillURL(item, width: Int(Tokens.Size.still * 2)))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        if let progress = item.progress {
                            ProgressCapsule(value: progress).padding(12)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.still))
                Text(item.displayTitle).font(Tokens.Font.card).foregroundStyle(Tokens.Color.text).lineLimit(1)
                if let caption = [item.episodeLine, item.remainingText].compactMap({ $0 }).joined(separator: " · ").nilIfEmpty {
                    Text(caption).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.text3).lineLimit(1)
                }
            }
            .frame(width: Tokens.Size.still)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu { ItemMenu(item: item) }
    }
}

/// Portrait poster: a click opens the details page.
struct PosterCard: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        Button { model.openDetail(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                RemoteImage(url: model.client?.imageURL(item, "Primary", width: Int(Tokens.Size.posterMax * 2)))
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if item.isPlayed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Tokens.Color.onAction, Tokens.Color.action)
                                .padding(8)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let progress = item.progress { ProgressCapsule(value: progress).padding(10) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.poster))
                Text(item.name).font(Tokens.Font.card).foregroundStyle(Tokens.Color.text).lineLimit(1)
                if let year = item.productionYear {
                    Text(String(year)).font(Tokens.Font.caption).foregroundStyle(Tokens.Color.text3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu { ItemMenu(item: item) }
    }
}

struct ItemMenu: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        if item.isSeries {
            Button("Show Series") { model.openDetail(item) }
        } else {
            Button(item.canResume ? "Resume" : "Play") { model.play(item) }
            Button(item.isEpisode ? "Show Series" : "Show Details") { model.openDetail(item) }
        }
        if item.canResume { Button("Play from Beginning") { model.play(item, fromStart: true) } }
        Divider()
        Button(item.isPlayed ? "Mark as Unwatched" : "Mark as Watched") {
            Task { await model.setPlayed(item, !item.isPlayed) }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Scroll targets in the home view.
nonisolated enum HomeAnchor: Hashable, Sendable {
    case recentlyAdded
}
