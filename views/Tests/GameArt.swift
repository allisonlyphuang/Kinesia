import SwiftUI
import UIKit

struct ArtImage<Fallback: View>: View {
    let name: String
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
        } else {
            fallback()
        }
    }
}

nonisolated enum GameArtName {
    /// Ripples, three stages of one plant. Square, transparent, the pot at the foot of the square
    /// so all three stages share a centre and the pot does not move when the plant grows. Drawn
    /// at 64pt, so draw for 192 across.
    static let plantStages = ["gamePlant1", "gamePlant2", "gamePlant3"]

    /// Stage 1 is the start of the test, 2 is one hand done, 3 is the saved session.
    static func plant(stage: Int) -> String {
        plantStages[min(max(stage, 1), plantStages.count) - 1]
    }

    /// Constellation. One star, drawn once and in its own colour: square, transparent, the star
    /// centred, 52pt. The state of a route point is the ring around it and how faded it is, not
    /// the colour of the star.
    static let star = "gameStar"

    /// Fireflies. Both square and transparent, and both are drawn inside a circle the capture
    /// layer measures against, so the subject has to sit in the middle and leave the corners
    /// empty. The jar is 56pt at the smallest and the firefly 52pt.
    static let jar = "gameJar"
    static let firefly = "gameFirefly"
}

extension GameArtName {
    /// Whether the catalogue has this art yet.
    ///
    /// A screen needs this when it draws something over a slot and has to pick a colour for it:
    /// the number that reads on a drawn moss star does not read on a gold one.
    @MainActor
    static func hasArt(_ name: String) -> Bool {
        UIImage(named: name) != nil
    }
}

/// The drawn stand-in for a plant in its pot.
///
/// Three stages, each taller and with one more pair of leaves. All three are drawn from the same
/// baseline so the pot does not move when the plant grows.
struct PlantGlyph: View {
    var stage = 1

    /// The pot is the one warm tone in the app. It has to differ from `buttonSoft`, which is the
    /// fill of the target circle the pot sits on, or the pot disappears into it.
    private static let pot = Color(.sRGB, red: 201/255, green: 195/255, blue: 180/255, opacity: 1)

    /// Stem height as a fraction of the side, and the heights up the stem that carry a leaf pair.
    private static let stemHeights: [CGFloat] = [0.22, 0.38, 0.52]
    private static let leafHeights: [CGFloat] = [0.9, 0.58, 0.3]

    private var clampedStage: Int { min(max(stage, 1), Self.stemHeights.count) }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let potWidth = side * 0.52
            let potHeight = side * 0.3
            let stemHeight = side * Self.stemHeights[clampedStage - 1]

            ZStack(alignment: .bottom) {
                Path { path in
                    let baseline = side - potHeight
                    path.move(to: CGPoint(x: side / 2, y: baseline))
                    path.addLine(to: CGPoint(x: side / 2, y: baseline - stemHeight))
                }
                .stroke(Color.primaryColor, style: StrokeStyle(lineWidth: side * 0.05, lineCap: .round))

                ForEach(0..<clampedStage, id: \.self) { pair in
                    let height = stemHeight * Self.leafHeights[pair]
                    leaf(side: side, height: height, potHeight: potHeight, toTheLeft: true)
                    leaf(side: side, height: height, potHeight: potHeight, toTheLeft: false)
                }

                UnevenRoundedRectangle(
                    topLeadingRadius: side * 0.04,
                    bottomLeadingRadius: side * 0.1,
                    bottomTrailingRadius: side * 0.1,
                    topTrailingRadius: side * 0.04,
                    style: .continuous
                )
                .fill(Self.pot)
                .frame(width: potWidth, height: potHeight)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func leaf(side: CGFloat, height: CGFloat, potHeight: CGFloat, toTheLeft: Bool) -> some View {
        Ellipse()
            .fill(Color.primaryColor)
            .frame(width: side * 0.3, height: side * 0.16)
            .rotationEffect(.degrees(toTheLeft ? -24 : 24))
            .offset(
                x: toTheLeft ? -side * 0.16 : side * 0.16,
                y: -(potHeight + height)
            )
    }
}

/// The drawn stand-in for a route point in Constellation.
struct StarGlyph: View {
    var fill: Color
    var stroke: Color
    var lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                starPath(side: side).fill(fill)
                starPath(side: side).stroke(stroke, lineWidth: lineWidth)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// A five-point star, outer radius 0.5 of the side and inner radius 0.42 of that, starting at
    /// the top so the point faces up.
    private func starPath(side: CGFloat) -> Path {
        let centre = CGPoint(x: side / 2, y: side / 2)
        let outer = side / 2 - lineWidth / 2
        let inner = outer * 0.42

        return Path { path in
            for step in 0..<10 {
                let radius = step.isMultiple(of: 2) ? outer : inner
                let angle = Angle.degrees(Double(step) * 36 - 90).radians
                let point = CGPoint(
                    x: centre.x + CGFloat(cos(angle)) * radius,
                    y: centre.y + CGFloat(sin(angle)) * radius
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        HStack(spacing: Spacing.lg) {
            ForEach(1...3, id: \.self) { stage in
                PlantGlyph(stage: stage).frame(width: 96, height: 96)
            }
        }
        HStack(spacing: Spacing.lg) {
            StarGlyph(fill: Color.primaryColor, stroke: Color.textLight, lineWidth: 2)
                .frame(width: 52, height: 52)
            StarGlyph(fill: Color.bgPrimaryColor, stroke: Color.primaryColor, lineWidth: 2)
                .frame(width: 52, height: 52)
        }
    }
    .padding(Spacing.xl)
    .background(Color.bgSecondaryColor)
}
