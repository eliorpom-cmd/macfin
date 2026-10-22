import SwiftUI

struct MovieDetailView: View {
    @Environment(AppModel.self) private var model
    let item: Item

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
                        ResumeProgress(item: item)
                        PlayButtons(item: item).padding(.top, 6)
                    }
                    .padding(.horizontal, Tokens.Space.gutter)
                    .padding(.bottom, 8)
                }
                .containerRelativeFrame(.vertical) { height, _ in height * Tokens.Size.heroFraction }
                .clipped()

                if let overview = item.overview {
                    Text(overview).font(Tokens.Font.body).foregroundStyle(Tokens.Color.text2)
                        .lineSpacing(3)
                        .frame(maxWidth: Tokens.Size.summaryWidth, alignment: .leading)
                        .padding(.horizontal, Tokens.Space.gutter)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, 64)
        }
        .ignoresSafeArea(.container, edges: .top)
        .scrollEdgeEffectHidden(true, for: .top)
        .background(Tokens.Color.base)
    }
}
