import SwiftUI

/// Design tokens — DESIGN.md is the source of truth.
enum Tokens {
    enum Color {
        static let base = SwiftUI.Color.black
        static let surface = SwiftUI.Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
        static let text = SwiftUI.Color.white
        static let text2 = SwiftUI.Color.white.opacity(0.62)
        static let text3 = SwiftUI.Color.white.opacity(0.40)
        static let track = SwiftUI.Color.white.opacity(0.25)
        static let action = SwiftUI.Color.white
        static let onAction = SwiftUI.Color.black
        static let hairline = SwiftUI.Color.white.opacity(0.08)
        static let titleBar = SwiftUI.Color.black.opacity(0.55)
    }
    enum Font {
        static let hero = SwiftUI.Font.system(size: 56, weight: .bold)
        static let section = SwiftUI.Font.title2.weight(.bold)
        static let card = SwiftUI.Font.callout.weight(.medium)
        static let meta = SwiftUI.Font.subheadline
        static let body = SwiftUI.Font.body
        static let caption = SwiftUI.Font.caption
    }
    enum Space {
        static let gutter: CGFloat = 48
        static let section: CGFloat = 40
        static let row: CGFloat = 20
        static let gridH: CGFloat = 24
        static let gridV: CGFloat = 32
    }
    enum Size {
        static let posterMin: CGFloat = 168
        static let posterMax: CGFloat = 226
        static let still: CGFloat = 340
        static let episodeStill: CGFloat = 280
        static let heroFraction: CGFloat = 0.72
        static let summaryWidth: CGFloat = 560
        static let progress: CGFloat = 4
        static let button: CGFloat = 40
        static let titleBar: CGFloat = 28
        static let controlBar: CGFloat = 440
        static let preview: CGFloat = 192
    }
    enum Radius {
        static let poster: CGFloat = 12
        static let still: CGFloat = 14
        static let controlBar: CGFloat = 20
        static let preview: CGFloat = 8
    }
    enum Motion {
        static let hover = Animation.snappy(duration: 0.22)
        static let fade = Animation.easeOut(duration: 0.25)
        static let page = Animation.smooth(duration: 0.4)
        static let pageScale: CGFloat = 1.03
        static let hoverScale: CGFloat = 1.04
        static let pressScale: CGFloat = 0.97
        static let chromeDelay: Duration = .seconds(2.5)
    }
}
