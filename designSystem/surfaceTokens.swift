import SwiftUI

// Surfaces and text colours for the opening and home screens.
//
// These are declared here rather than in the asset catalogue because they are
// compositional values — gradient stops, translucent cards, hairlines — that are
// only meaningful next to each other.
//
// Every colour that carries text is at or above 4.5:1 against the surface it sits
// on. moss (#576155) is 6.3:1 on cream and carries secondary text; sage (#A8B3A0)
// is 2.1:1 and is never used for text here, only for fills and rules.
nonisolated extension Color {
    // Page ground, top to bottom
    static let groundTop    = Color(.sRGB, red: 253/255, green: 252/255, blue: 247/255, opacity: 1)
    static let groundMiddle = Color(.sRGB, red: 251/255, green: 250/255, blue: 243/255, opacity: 1)
    static let groundBottom = Color(.sRGB, red: 236/255, green: 239/255, blue: 224/255, opacity: 1)

    // Surfaces
    static let cardSurface = Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255, opacity: 0.82)
    static let hairline    = Color(.sRGB, red: 230/255, green: 227/255, blue: 215/255, opacity: 1)

    // Text
    static let textQuiet   = Color(.sRGB, red: 110/255, green: 117/255, blue: 105/255, opacity: 1)  // 4.7:1 on cream
    static let chevronTint = Color(.sRGB, red: 125/255, green: 133/255, blue: 111/255, opacity: 1)

    // Controls
    static let buttonSoft = Color(.sRGB, red: 221/255, green: 226/255, blue: 210/255, opacity: 1)

    // Over the photograph
    static let scrimDark        = Color(.sRGB, red: 36/255, green: 43/255, blue: 36/255, opacity: 1)
    static let textOnPhoto      = Color(.sRGB, red: 255/255, green: 253/255, blue: 248/255, opacity: 1)
    static let textOnPhotoQuiet = Color(.sRGB, red: 217/255, green: 222/255, blue: 205/255, opacity: 1)
}

nonisolated extension ShapeStyle where Self == LinearGradient {

    // The page ground shared by the home screen and anything that sits in its key.
    static var pageGround: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .groundTop,    location: 0),
                .init(color: .groundMiddle, location: 0.38),
                .init(color: .groundBottom, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // The scrim over openingBackground.
    //
    // The alphas are measured, not chosen by eye. The photograph's brightest pixel
    // runs from about 0.22 relative luminance at the top to about 0.70 at the
    // bottom, so cream text needs roughly 0.21 alpha at the top rising to 0.77 at
    // the foot to stay at 4.5:1. These stops clear that everywhere, with margin.
    // Changing the photograph means measuring again.
    static var openingScrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .scrimDark.opacity(0.45), location: 0),
                .init(color: .scrimDark.opacity(0.55), location: 0.28),
                .init(color: .scrimDark.opacity(0.74), location: 0.45),
                .init(color: .scrimDark.opacity(0.80), location: 0.60),
                .init(color: .scrimDark.opacity(0.88), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // Left-to-right scrim for the garden card, which carries text on its left side.
    static var gardenCardScrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .scrimDark.opacity(0.82), location: 0),
                .init(color: .scrimDark.opacity(0.52), location: 0.62),
                .init(color: .scrimDark.opacity(0.34), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
