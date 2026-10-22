import SwiftUI

/// Show page: backdrop with the episode to watch next, season picker, then the season's episodes.
struct SeriesDetailView: View {
    @Environment(AppModel.self) private var model
    let item: Item
    @State private var season: Int?

    private var episodes: [Item] { model.episodes[item.id] ?? [] }
    private var seasons: [Int] { Array(Set(episodes.map { $0.parentIndexNumber ?? 1 })).sorted() }
    private var shown: [Item] {
        let selected = season ?? up?.parentIndexNumber ?? seasons.first ?? 1
        return episodes.filter { ($0.parentIndexNumber ?? 1) == selected }
    }

    /// Episode the main button plays: the one in progress, else the first unwatched, else the first.
    private var up: Item? {
        episodes.first { $0.canResume } ?? episodes.first { !$0.isPlayed } ?? episodes.first
    }

    var body: some View {
        let item = model.current(self.item)
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.section) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: model.client?.backdropURL(item, width: 2560))
                    LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: Tokens.Color.base.opacity(0.7), location: 0.72), .init(color: Tokens.Color.base, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    LinearGradient(colors: [Tokens.Color.base.opacity(0.7), .clear], startPoint: .leading, endPoint: .center)

                    VStack(alignment: .leading, spacing: 14) {
                        if item.hasImage("Logo"), let client = model.client {
                            RemoteImage(url: client.imageURL(item, "Logo", width: 900), fit: true)
                                .frame(maxWidth: 440, maxHeight: 150, alignment: .bottomLeading)
                        } else {
                            Text(item.name).font(Tokens.Font.hero).foregroundStyle(Tokens.Color.text)
                        }
                        Text(item.metaLine).font(Tokens.Font.meta).foregroundStyle(Tokens.Color.text2)
                        if let overview = item.overview {
                            Text(overview).font(Tokens.Font.body).foregroundStyle(Tokens.Color.text2)
                                .lineLimit(3).frame(maxWidth: Tokens.Size.summaryWidth, alignment: .leading)
                        }
                        if let up {
                            ResumeProgress(item: up)
                            Button { model.play(up) } label: {
                                Label(up.canResume ? "Resume \(up.episodeCode ?? "")" : "Play \(up.episodeCode ?? "")", systemImage: "play.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .labelStyle(.titleAndIcon)
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, Tokens.Space.gutter)
                    .padding(.bottom, 8)
                }
                .containerRelativeFrame(.vertical) { height, _ in height * Tokens.Size.heroFraction }
                .clipped()

                VStack(alignment: .leading, spacing: 18) {
                    if seasons.count > 1 {
                        Picker("Season", selection: Binding(get: { season ?? up?.parentIndexNumber ?? seasons[0] }, set: { season = $0 })) {
                            ForEach(seasons, id: \.self) { Text("Season \($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    } else if let only = seasons.first {
                        Text("Season \(only)").font(Tokens.Font.section).foregroundStyle(Tokens.Color.text)
                    }
                    ForEach(shown) { EpisodeRow(item: $0) }
                }
                .padding(.horizontal, Tokens.Space.gutter)
                .overlay { if episodes.isEmpty { ProgressView() } }
            }
            .padding(.bottom, 64)
        }
        .ignoresSafeArea(.container, edges: .top)
        .scrollEdgeEffectHidden(true, for: .top)
        .background(Tokens.Color.base)
        .task(id: item.id) { await model.loadEpisodes(of: item.id) }
    }
}

/// One episode: 16:9 still with progress, number and title, runtime, summary. A click plays it.
struct EpisodeRow: View {
    @Environment(AppModel.self) private var model
    let item: Item

    var body: some View {
        Button { model.play(item) } label: {
            HStack(alignment: .top, spacing: Tokens.Space.row) {
                RemoteImage(url: model.client?.imageURL(item, "Primary", width: Int(Tokens.Size.episodeStill * 2)))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        if let progress = item.progress { ProgressCapsule(value: progress).padding(10) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.isPlayed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Tokens.Color.onAction, Tokens.Color.action)
                                .padding(8)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.still))
                    .frame(width: Tokens.Size.episodeStill)

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "\(item.indexNumber.map { "\($0). " } ?? "")\(item.name)")
                        .font(.headline).foregroundStyle(Tokens.Color.text)
                    Text(item.remainingText ?? item.runtimeText ?? "")
                        .font(Tokens.Font.caption).foregroundStyle(Tokens.Color.text3)
                    if let overview = item.overview {
                        Text(overview).font(Tokens.Font.body).foregroundStyle(Tokens.Color.text2)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: Tokens.Size.summaryWidth, alignment: .leading)
                .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle())
        .contextMenu { ItemMenu(item: item) }
    }
}
