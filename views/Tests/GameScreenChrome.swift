import SwiftUI

nonisolated enum GameChrome {
    /// The page gutter the home and medication screens use.
    static let gutter: CGFloat = 22
    static let cardPadding: CGFloat = 18
}

extension View {
    /// The ground every game screen stands on, the same gradient as the home screen.
    func gameGround() -> some View {
        background { Rectangle().fill(.pageGround).ignoresSafeArea() }
    }

    /// A cream card on the page ground.
    func gameCard(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
            .padding(GameChrome.cardPadding)
            .background(
                Color.cardSurface,
                in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
            )
    }

    /// The edge a play surface needs. A surface is white so the art and the targets on it carry
    /// the colour; without a hairline it dissolves into the page it sits on.
    func playSurfaceEdge() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            }
    }
}

/// The white board a game is played on.
///
/// It is used as the fill behind the targets rather than as a background modifier, because the
/// capture layer measures against this rectangle and has to sit inside it.
struct PlaySurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
            .fill(Color.bgPrimaryColor)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            }
    }
}

/// The name of the game, then what to do. The game is named the way the home screen names it,
/// so the row a patient taps and the screen it opens agree.
struct GameHeader: View {
    let game: String
    var instruction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(game)
                .font(.displayMedium)
                .fontWeight(.medium)
                .foregroundStyle(Color.textDark)

            if let instruction {
                Text(instruction)
                    .font(.body)
                    .foregroundStyle(Color.textQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)
    }
}

/// The small tracked heading that separates a section, and that carries the live round count
/// while a game is being played.
struct GameSectionLabel: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .sectionLabelStyle()
            .foregroundStyle(Color.primaryColor)
    }
}
