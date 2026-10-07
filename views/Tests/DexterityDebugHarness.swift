#if DEBUG
import SwiftUI

/// Development validation only. This provisional route and target radius are not a production protocol.
struct DexterityDebugHarness: View {
    @State private var runID = UUID()
    @State private var completedSequence: DexteritySequence?
    @State private var debugMetrics: DexterityMetrics?
    @State private var isTraceInteractionActive = true

    private let configuration = DexterityDebugConfiguration.configuration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("dexterity debug harness")
                    .font(.displayMedium)
                    .foregroundStyle(Color.textDark)

                Text("development validation only. this route and target radius are provisional and are not a clinical or production protocol.")
                    .font(.body)
                    .foregroundStyle(Color.textDark)
                    .fixedSize(horizontal: false, vertical: true)

                if let configuration {
                    DexterityTraceSurface(
                        configuration: configuration,
                        onSequenceFinished: analyze,
                        onPhaseChanged: updateScrollState
                    )
                    .id(runID)

                    debugMetricsPanel

                    Button("reset debug run") {
                        resetDebugRun()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Starts a new development-only tracing run.")
                } else {
                    Text("the development tracing configuration is unavailable.")
                        .font(.body)
                        .foregroundStyle(Color.textDark)
                }
            }
            .padding(Spacing.lg)
        }
        .scrollDisabled(isTraceInteractionActive)
        .background(Color.bgPrimaryColor.ignoresSafeArea())
    }

    @ViewBuilder
    private var debugMetricsPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("debug metrics")
                .font(.heading)
                .foregroundStyle(Color.textDark)

            if let completedSequence, let debugMetrics {
                Text("sequence completed: \(completedSequence.completed ? "yes" : "no")")
                Text("captured samples: \(completedSequence.samples.count)")
                Text("ended by lift: \(completedSequence.endedByLift ? "yes" : "no")")
                Text("ended by cancellation: \(completedSequence.endedByCancellation ? "yes" : "no")")
                metricRow("rms error", value: debugMetrics.rmsError, unit: "canonical route units")
                metricRow("max point error", value: debugMetrics.maxPointError, unit: "canonical route units")
                metricRow("mean swipe speed", value: debugMetrics.swipeSpeedStats?.mean, unit: "canonical route units / second")
                metricRow("speed stdev", value: debugMetrics.swipeSpeedStats?.stdev, unit: "canonical route units / second")
                metricRow("speed cv", value: debugMetrics.cvSwipeSpeed, unit: "%")

                if let pathInvalidReason = debugMetrics.pathInvalidReason {
                    Text("path issue: \(pathInvalidReason)")
                }
                if let speedInvalidReason = debugMetrics.speedInvalidReason {
                    Text("speed issue: \(speedInvalidReason)")
                }
            } else {
                Text("complete or end a trace to inspect the captured sequence and calculated metrics.")
            }
        }
        .font(.subheading)
        .foregroundStyle(Color.textDark)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondaryColor, in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func metricRow(_ label: String, value: Double?, unit: String) -> some View {
        Text("\(label): \(formatted(value)) \(unit)")
    }

    private func formatted(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return "unavailable"
        }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    private func analyze(sequence: DexteritySequence, startedAt: TimeInterval) {
        guard let configuration else {
            return
        }

        let trial = DexterityTrial(
            route: configuration.route,
            coordinateSpace: configuration.coordinateSpace,
            sequences: [sequence],
            startedAt: startedAt
        )
        completedSequence = sequence
        debugMetrics = DexterityAnalyzer.analyze(trial)
    }

    private func resetDebugRun() {
        completedSequence = nil
        debugMetrics = nil
        isTraceInteractionActive = true
        runID = UUID()
    }

    private func updateScrollState(for phase: DexterityTestModel.Phase) {
        switch phase {
        case .ready, .tracing:
            isTraceInteractionActive = true
        case .completed, .ended, .configurationInvalid:
            isTraceInteractionActive = false
        }
    }
}

private enum DexterityDebugConfiguration {
    static let route = DexterityRoute(
        identifier: "debug-development-route",
        version: 1,
        points: [
            .init(x: 15, y: 80),
            .init(x: 20, y: 20),
            .init(x: 50, y: 45),
            .init(x: 80, y: 20),
            .init(x: 85, y: 80)
        ]
    )

    static let targetRadius = 8.0
    static let captureWidth = 320.0
    static let captureHeight = 400.0
    static let padding = 40.0

    static let configuration: DexterityTestConfiguration? = {
        guard let coordinateSpace = DexterityRouteFit.coordinateSpace(
            for: route,
            captureWidth: captureWidth,
            captureHeight: captureHeight,
            padding: padding
        ) else {
            return nil
        }

        return DexterityTestConfiguration(
            route: route,
            coordinateSpace: coordinateSpace,
            targetRadius: targetRadius
        )
    }()
}

#Preview("Dexterity debug harness") {
    DexterityDebugHarness()
}
#endif
