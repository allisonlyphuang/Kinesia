import CoreData
import SwiftUI

enum AkinesiaCopy {
    static let title = "Fireflies"

    static let setup = [
        "Rest your phone flat on a table.",
        "Place your index finger on the jar.",
        "When a firefly lights up, tap it as fast as you can to catch it.",
        "Then place your finger back on the jar and wait for the next firefly to appear."
    ]

    static let startButton = "I'm ready"
    static let returnHome = "Place your finger back on the jar."

    static func practiceIntro(rounds: Int) -> String {
        "First, \(rounds) practice \(rounds == 1 ? "firefly" : "fireflies"). These are only practice rounds."
    }

    static func progress(round: Int, of total: Int) -> String {
        "Firefly \(round) of \(total)"
    }

    /// Practice rounds are counted separately so the patient is never told they are on scored
    /// round 1 of 12 while actually warming up.
    static func practiceProgress(round: Int, of total: Int) -> String {
        "Practice firefly \(round) of \(total)"
    }

    static func feedback(_ feedback: AkinesiaTestModel.RoundFeedback) -> String {
        switch feedback {
        case .caught:      return "You caught it!"
        case .falseStart:  return "That one was a little early. Here comes another."
        case .slip:        return "Let's try that one again."
        case .missed:      return "That firefly got away. Here comes another."
        case .interrupted: return "Something interrupted us. Here comes another."
        }
    }

    static func finished(caught: Int, of total: Int) -> String {
        "All done. You caught \(caught) of \(total)."
    }

    static let saveFailed = "Couldn't save this session. Nothing was recorded."
}

struct AkinesiaTestView: View {
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        AkinesiaTestScreen(context: context)
    }
}

private struct AkinesiaTestScreen: View {
    private let context: NSManagedObjectContext
    @Environment(\.displayScale) private var displayScale
    @StateObject private var model: AkinesiaTestModel
    @State private var latestSavedResult: AkinesiaResult?
    @State private var latestResultFetchFailed = false

    init(context: NSManagedObjectContext) {
        self.context = context
        // Placeholder geometry. The real board size is not known until the screen is drawn, so the
        // model is reconfigured from the Start button, the same way the tapping screen does it.
        let placeholder = AkinesiaBoardLayout.fit(in: CGSize(width: 320, height: 320))
        _model = StateObject(
            wrappedValue: AkinesiaTestModel(
                configuration: AkinesiaTestConfiguration(
                    boardGeometry: placeholder.geometry,
                    ring: placeholder.ring
                ),
                context: context
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            content(layout: AkinesiaBoardLayout.fit(in: boardSpace(in: proxy.size)))
        }
            .background(Color.bgPrimaryColor.ignoresSafeArea())
            .navigationTitle(AkinesiaCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { refreshLatestResult() }
            .onChange(of: model.sessionPhase) { _, phase in
                if phase == .finished || phase == .failed { refreshLatestResult() }
            }
            .onDisappear {
                // Abandoning mid-session discards it and writes nothing.
                switch model.sessionPhase {
                case .instructions, .practicing, .scoring: model.reset()
                case .ready, .finished, .failed: break
                }
            }
    }

    // the space left for the board after the progress line, feedback line, and padding.
    private func boardSpace(in size: CGSize) -> CGSize {
        let chrome: CGFloat = 160
        return CGSize(width: size.width, height: max(0, size.height - chrome))
    }

    @ViewBuilder
    private func content(layout: AkinesiaBoardLayout) -> some View {
        switch model.sessionPhase {
        case .practicing, .scoring:
            playingLayout(layout: layout)
        case .ready, .instructions, .finished, .failed:
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    phaseContent(layout: layout)
                    latestResultSection
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // Playing

    private func playingLayout(layout: AkinesiaBoardLayout) -> some View {
        VStack(spacing: Spacing.md) {
            progressLine
            board(layout: layout)
            feedbackLine
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    private var progressLine: some View {
        Text(progressText)
            .font(.heading)
            .foregroundStyle(Color.textDark)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var progressText: String {
        if model.sessionPhase == .practicing {
            return AkinesiaCopy.practiceProgress(
                round: model.currentPracticeRoundNumber,
                of: model.totalPracticeRounds
            )
        }
        return AkinesiaCopy.progress(
            round: model.currentScoredRoundNumber,
            of: model.totalScoredRounds
        )
    }

    private func board(layout: AkinesiaBoardLayout) -> some View {
        FireflyBoardView(
            geometry: layout.geometry,
            isCaptureActive: model.isCaptureActive,
            fireflyAt: model.fireflyAt,
            onTouchDown: model.handleTouchDown,
            onHomeTouchUp: model.handleHomeTouchUp,
            onCueDisplayed: model.handleCueDisplayed,
            onFrameClockReady: model.handleFrameClockReady(refreshRateHz:)
        )
        .frame(width: layout.boardSide, height: layout.boardSide)
        .clipShape(RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Firefly catching area")
        .accessibilityHint(AkinesiaCopy.setup[2])
    }

  
    private var feedbackLine: some View {
        Text(feedbackText)
            .font(.body)
            .foregroundStyle(Color.textDark)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .top)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var feedbackText: String {
        if model.isAwaitingReturnHome { return AkinesiaCopy.returnHome }
        if let feedback = model.lastRoundFeedback { return AkinesiaCopy.feedback(feedback) }
        return " "
    }

    // Other phases

    @ViewBuilder
    private func phaseContent(layout: AkinesiaBoardLayout) -> some View {
        switch model.sessionPhase {
        case .ready, .instructions:
            instructions(layout: layout)
        case .finished:
            finished
        case .failed:
            failed
        case .practicing, .scoring:
            EmptyView()
        }
    }

    private func instructions(layout: AkinesiaBoardLayout) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(AkinesiaCopy.title)
                .font(.displayMedium)
                .foregroundStyle(Color.textDark)

            ForEach(AkinesiaCopy.setup, id: \.self) { line in
                Text(line)
                    .font(.body)
                    .foregroundStyle(Color.textDark)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.totalPracticeRounds > 0 {
                Text(AkinesiaCopy.practiceIntro(rounds: model.totalPracticeRounds))
                    .font(.subheading)
                    .foregroundStyle(Color.textDark)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(AkinesiaCopy.startButton) {
                model.configure(configuration(for: layout))
                model.startRounds()
            }
            .buttonStyle(AkinesiaButtonStyle())
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(AkinesiaCopy.finished(caught: model.completedScoredRounds, of: model.totalScoredRounds))
                .font(.heading)
                .foregroundStyle(Color.textDark)
                .fixedSize(horizontal: false, vertical: true)

            Button("Play again") { model.reset() }
                .buttonStyle(AkinesiaButtonStyle())
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(AkinesiaCopy.saveFailed)
                .font(.heading)
                .foregroundStyle(Color.textDark)
                .fixedSize(horizontal: false, vertical: true)

            Button("Start over") { model.reset() }
                .buttonStyle(AkinesiaButtonStyle())
        }
    }

    private func configuration(for layout: AkinesiaBoardLayout) -> AkinesiaTestConfiguration {
        AkinesiaTestConfiguration(
            boardGeometry: layout.geometry,
            ring: layout.ring,
            hand: .right,
            digit: "index",
            screenScale: displayScale
        )
    }
}

private extension AkinesiaTestScreen {

    var latestResultSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Latest saved test")
                .font(.heading)
                .foregroundStyle(Color.textDark)

            if let result = latestSavedResult {
                Text("\(result.numValidRounds) of \(result.numRounds) rounds counted")
                Text("Median reaction: \(formattedMilliseconds(result.reactionTimeMedian, isValid: result.isValid))")
                Text("Median movement: \(formattedMilliseconds(result.movementTimeMedian, isValid: result.isValid))")
                Text(failureBreakdown(result))
                if !result.isValid {
                    // A zero in a statistic column is a placeholder while isValid is false, not a
                    // measured zero. See DATA_DICTIONARY.md.
                    Text("Not scored: \(result.invalidReason ?? "reason unavailable")")
                }
            } else if latestResultFetchFailed {
                Text("Latest saved test is unavailable right now.")
            } else {
                Text("No saved Fireflies tests yet.")
            }
        }
        .font(.body)
        .foregroundStyle(Color.textDark)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondaryColor, in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
    }

    func failureBreakdown(_ result: AkinesiaResult) -> String {
        "Early \(result.numAnticipations) · False starts \(result.numFalseStarts) · Slips \(result.numSlips)"
        + " · Missed \(result.numMissed) · Slow \(result.numLapses) · Unusable \(result.numMalformed)"
    }

    func formattedMilliseconds(_ seconds: Double, isValid: Bool) -> String {
        guard isValid, seconds.isFinite, seconds > 0 else { return "unavailable" }
        return "\(Int((seconds * 1000).rounded())) ms"
    }

    func refreshLatestResult() {
        do {
            latestSavedResult = try AkinesiaStore.fetchLatestResult(in: context)
            latestResultFetchFailed = false
        } catch {
            latestSavedResult = nil
            latestResultFetchFailed = true
        }
    }
}

private struct AkinesiaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.button)
            .foregroundStyle(Color.textLight)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Color.textDark.opacity(configuration.isPressed ? 0.75 : 1),
                in: Capsule()
            )
    }
}
