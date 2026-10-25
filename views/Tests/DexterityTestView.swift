import CoreData
import SwiftUI

struct DexterityTestView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var model = DexteritySessionModel()
    @State private var didConfigure = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(280, min(geometry.size.width - 32, 360))
            let height = min(max(320, geometry.size.height * 0.52), 410)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    content(configuration: configuration(width: width, height: height))
                }
                .padding(.horizontal, GameChrome.gutter)
                .padding(.bottom, Spacing.lg)
            }
            .scrollDisabled(isTracingRound)
            .gameGround()
        .onAppear {
            configure(width: width, height: height)
        }
        }
        .navigationTitle(CheckInTask.constellation.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        GameHeader(
            game: CheckInTask.constellation.title,
            instruction: "Use your right index finger to trace each path without lifting. Lift between attempts. Complete one practice trace, then three scored traces."
        )
    }

    @ViewBuilder
    private func content(configuration: DexterityTestConfiguration?) -> some View {
        switch model.phase {
        case .instructions:
            Button("Start practice") { model.start() }
                .buttonStyle(.primaryCapsule)
                .disabled(configuration == nil)
        case .practice, .scored:
            if let configuration {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    GameSectionLabel(phaseText)
                    DexterityTraceSurface(
                        configuration: configuration,
                        onSequenceFinished: { sequence, monotonicStartedAt in
                            model.receive(sequence: sequence, monotonicStartedAt: monotonicStartedAt, in: context)
                        }
                    )
                    .id(model.attemptID)
                }
            } else {
                unavailable
            }
        case .saving:
            ProgressView("Saving trace")
                .tint(Color.primaryColor)
                .font(.body)
                .foregroundStyle(Color.textQuiet)
                .gameCard(alignment: .center)
        case .finished:
            finishedContent
        case .failed(let message):
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.textDark)
                    .gameCard()
                Button("Try again") { model.reset() }
                    .buttonStyle(.primaryCapsule)
            }
        }
    }

    private var phaseText: String {
        switch model.phase {
        case .practice: return "Practice trace"
        case .scored(let round): return "Scored trace \(round) of \(DexterityProtocolV1.scoredCompletionsRequired)"
        default: return ""
        }
    }

    private var isTracingRound: Bool {
        switch model.phase {
        case .practice, .scored:
            return true
        case .instructions, .saving, .finished, .failed:
            return false
        }
    }

    private var finishedContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                GameSectionLabel("Tracing complete")
                    .padding(.bottom, Spacing.xxs)
                if let result = model.latestResult {
                    Text("Completed traces: \(result.doneSequences)")
                }
            }
            .font(.body)
            .foregroundStyle(Color.textDark)
            .gameCard()

            latestResultSection

            Button("Run again") { model.reset() }
                .buttonStyle(.primaryCapsule)
        }
    }

    @ViewBuilder
    private var latestResultSection: some View {
        if let result = model.latestResult {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                GameSectionLabel("Saved result")
                    .padding(.bottom, Spacing.xxs)
                Text("Your result was saved on this device.")
                Text("Completed traces: \(result.doneSequences)")
            }
            .font(.body)
            .foregroundStyle(Color.textDark)
            .gameCard()
        }
    }

    private var unavailable: some View {
        Text("This tracing surface is unavailable.")
            .font(.body)
            .foregroundStyle(Color.textDark)
            .gameCard()
    }

    private func configuration(width: CGFloat, height: CGFloat) -> DexterityTestConfiguration? {
        DexterityProtocolV1.configuration(captureWidth: width, captureHeight: height, padding: 32)
    }

    private func configure(width: CGFloat, height: CGFloat) {
        guard !didConfigure, let configuration = configuration(width: width, height: height) else { return }
        didConfigure = true
        model.configure(configuration)
    }

}
