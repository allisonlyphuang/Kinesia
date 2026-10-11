import CoreData
import SwiftUI

struct DexterityTestView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var model = DexteritySessionModel()
    @State private var latestSavedResult: DexterityResult?
    @State private var didConfigure = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(280, min(geometry.size.width - 32, 360))
            let height = min(max(320, geometry.size.height * 0.52), 410)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    content(configuration: configuration(width: width, height: height))
                    latestResultSection
                }
                .padding(Spacing.lg)
            }
            .scrollDisabled(isTracingRound)
        .onAppear {
            configure(width: width, height: height)
            refreshLatestResult()
        }
        .onChange(of: model.latestResult) { _, _ in
            refreshLatestResult()
        }
        }
        .navigationTitle("Dexterity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Constellation tracing")
                .font(.displayMedium)
                .foregroundStyle(Color.textDark)
            Text("Use your right index finger. Complete one practice trace, then three scored traces without lifting your finger.")
                .font(.body)
                .foregroundStyle(Color.textDark)
        }
    }

    @ViewBuilder
    private func content(configuration: DexterityTestConfiguration?) -> some View {
        switch model.phase {
        case .instructions:
            Button("Start practice") { model.start() }
                .buttonStyle(.borderedProminent)
                .disabled(configuration == nil)
        case .practice, .scored:
            if let configuration {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(phaseText)
                        .font(.subheading)
                        .foregroundStyle(Color.textDark)
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
        case .finished:
            finishedContent
        case .failed(let message):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(message).foregroundStyle(Color.textDark)
                Button("Try again") { model.reset() }.buttonStyle(.bordered)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tracing complete")
                .font(.displayMedium)
                .foregroundStyle(Color.textDark)
            if let result = model.latestResult {
                Text("Completed traces: \(result.doneSequences)")
                Text("Average trace length: \(result.swipeDist, format: .number.precision(.fractionLength(1))) canonical units")
                Text("Mean swipe speed: \(result.swipeSpeedMean, format: .number.precision(.fractionLength(1))) canonical units / second")
            }
            Button("Run again") { model.reset() }.buttonStyle(.borderedProminent)
        }
        .foregroundStyle(Color.textDark)
    }

    @ViewBuilder
    private var latestResultSection: some View {
        if let latestSavedResult {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Latest saved trace").font(.subheading)
                Text("Completed traces: \(latestSavedResult.doneSequences)")
                Text("Mean swipe speed: \(latestSavedResult.swipeSpeedMean, format: .number.precision(.fractionLength(1))) canonical units / second")
                Text(latestSavedResult.isValid ? "Saved result is available" : "Saved result needs review")
            }
            .foregroundStyle(Color.textDark)
        }
    }

    private var unavailable: some View {
        Text("This tracing surface is unavailable.").foregroundStyle(Color.textDark)
    }

    private func configuration(width: CGFloat, height: CGFloat) -> DexterityTestConfiguration? {
        DexterityProtocolV1.configuration(captureWidth: width, captureHeight: height, padding: 32)
    }

    private func configure(width: CGFloat, height: CGFloat) {
        guard !didConfigure, let configuration = configuration(width: width, height: height) else { return }
        didConfigure = true
        model.configure(configuration)
    }

    private func refreshLatestResult() {
        latestSavedResult = try? DexterityStore.fetchLatestResult(in: context)
    }
}
