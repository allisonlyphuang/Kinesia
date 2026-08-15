//
//  BradykinesiaTestView.swift
//  Kinesia
//
//  Created by Amanda Hon on 8/13/26.
//

import CoreData
import SwiftUI

struct BradykinesiaTestView: View {
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        BradykinesiaTestScreen(context: context)
    }
}

private struct BradykinesiaTestScreen: View {
    private struct TargetGeometry {
        let leftCenter: TapPoint
        let rightCenter: TapPoint
        let radius: Double
    }

    private let context: NSManagedObjectContext
    @Environment(\.displayScale) private var displayScale
    @StateObject private var model: BradykinesiaTestModel
    @State private var captureSurfaceSize: CGSize = .zero
    @State private var latestSavedResult: BradykinesiaResult?
    @State private var latestResultFetchFailed = false
    @State private var latestSavedSession: TestSession?

    init(context: NSManagedObjectContext) {
        self.context = context
        _model = StateObject(
            wrappedValue: BradykinesiaTestModel(
                configuration: BradykinesiaTestConfiguration(
                    leftCenter: TapPoint(x: 0, y: 0),
                    rightCenter: TapPoint(x: 0, y: 0),
                    targetRadius: 1,
                    handOrder: [.right, .left],
                    screenScale: 1
                ),
                context: context
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                tappingSurface
                phaseContent
                latestResultSection
            }
            .padding(Spacing.lg)
        }
        .background(Color.bgPrimaryColor.ignoresSafeArea())
        .navigationTitle("Bradykinesia")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshLatestResult()
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .finished {
                refreshLatestResult()
            }
        }
        .onDisappear {
            switch model.phase {
            case .countdown, .running, .rest:
                model.reset()
            case .ready, .finished, .failed:
                break
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Bradykinesia tapping test")
                .font(.displayMedium)
                .foregroundStyle(Color.textDark)
            Text("Alternate between the two targets as quickly and accurately as you can for 20 seconds, starting on the right.")
                .font(.body)
                .foregroundStyle(Color.textDark)
        }
    }

    private var tappingSurface: some View {
        GeometryReader { proxy in
            let geometry = targetGeometry(in: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                    .fill(Color.bgSecondaryColor)

                targetCircle(
                    label: model.activeHand.map { "\(handName($0)) hand, left tapping target" } ?? "Left tapping target",
                    diameter: CGFloat(geometry.radius * 2)
                )
                    .position(x: CGFloat(geometry.leftCenter.x), y: CGFloat(geometry.leftCenter.y))
                targetCircle(
                    label: model.activeHand.map { "\(handName($0)) hand, right tapping target" } ?? "Right tapping target",
                    diameter: CGFloat(geometry.radius * 2)
                )

                TapCaptureView(
                    leftCenter: geometry.leftCenter,
                    rightCenter: geometry.rightCenter,
                    targetRadius: geometry.radius,
                    isCaptureActive: model.isCaptureActive,
                    onTap: model.recordTap
                )
                .background(Color.clear)
                .accessibilityHidden(true)

                if case .countdown = model.phase {
                    VStack(spacing: Spacing.xs) {
                        Text("Get ready")
                            .font(.heading)
                        Text("\(model.secondsRemaining)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.textDark)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
            .onAppear {
                captureSurfaceSize = proxy.size
            }
            .onChange(of: proxy.size) { _, size in
                captureSurfaceSize = size
            }
        }
        .frame(height: 300)
        .accessibilityElement(children: .contain)
    }

    private func handName(_ hand: CurrentHand) -> String {
        switch hand {
        case .left: return "left"
        case .right: return "right"
        }
    }
    
    private func targetCircle(label: String, diameter: CGFloat) -> some View {
        Circle()
            .fill(Color.primaryColor)
            .overlay {
                Circle()
                    .stroke(Color.textLight, lineWidth: 3)
            }
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .ready:
            Button("Start 20-second test") {
                let geometry = targetGeometry(in: captureSurfaceSize)
                model.configure(configuration(for: geometry))
                model.start()
            }
            .buttonStyle(PrimaryTestButtonStyle())
            .disabled(captureSurfaceSize == .zero)

        case .countdown(let hand):
            Text("\(handName(hand)) hand — place your index finger over the targets.")
                .font(.subheading)
                .foregroundStyle(Color.textDark)

        case .running(let hand):
            Text("\(handName(hand)) hand — \(model.secondsRemaining) seconds remaining")
                .font(.heading)
                .foregroundStyle(Color.textDark)
                .accessibilityLabel("\(handName(hand)) hand, \(model.secondsRemaining) seconds remaining")

        case .finished:
            finishedContent

        case .failed:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Couldn’t save this test.")
                    .font(.heading)
                    .foregroundStyle(Color.textDark)
                Text("Your results were not marked as saved. Please reset and try again.")
                    .font(.body)
                    .foregroundStyle(Color.textDark)
                Button("Reset") {
                    model.reset()
                }
                .buttonStyle(PrimaryTestButtonStyle())
            }
        case .rest(let nextHand):
            restContent(nextHand: nextHand)
        }
    }
    
    private func restContent(nextHand: CurrentHand) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("\(model.completedAttempts.count) of \(model.configuration.handOrder.count) hands complete.")
                .font(.heading)
                .foregroundStyle(Color.textDark)
            Text("Switch to your \(handName(nextHand).lowercased()) hand, then continue when you're ready.")
                .font(.body)
                .foregroundStyle(Color.textDark)
            Button("Start \(handName(nextHand).lowercased()) hand") {
                let geometry = targetGeometry(in: captureSurfaceSize)
                model.configure(configuration(for: geometry))
                model.beginCountdown(for: nextHand)
            }
            .buttonStyle(PrimaryTestButtonStyle())
        }
    }

    private var finishedContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Test saved")
                .font(.heading)
                .foregroundStyle(Color.textDark)

            // maps on screen items to data items across redraws
            ForEach(model.completedAttempts, id: \.hand) { attempt in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(handName(attempt.hand)) hand")
                        .font(.subheading)
                    Text("Captured taps: \(attempt.metrics.numTaps)")
                    Text("Mean interval: \(formatted(attempt.metrics.tapInterStats?.mean))")
                    Text("Median interval: \(formatted(attempt.metrics.tapInterStats?.median))")
                }
                .font(.body)
                .foregroundStyle(Color.textDark)
            }

            Button("Run again") {
                model.reset()
            }
            .buttonStyle(PrimaryTestButtonStyle())
        }
    }

    @ViewBuilder
    private var latestResultSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Latest saved test")
                .font(.heading)
                .foregroundStyle(Color.textDark)

            if let latestSavedSession {
                ForEach(sortedResults(in: latestSavedSession), id: \.objectID) { result in
                    Text("\(displayHand(result.hand)): \(result.numTaps) taps — mean \(result.isValid ? formatted(result.tapInterMean) : "unavailable")")
                }
            } else if latestResultFetchFailed {
                Text("Latest saved test is unavailable right now.")
            } else {
                Text("No saved Bradykinesia tests yet.")
            }
        }
        .font(.body)
        .foregroundStyle(Color.textDark)
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondaryColor, in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
    }

    private func sortedResults(in session: TestSession) -> [BradykinesiaResult] {
        let results = session.bradykinesiaResults as? Set<BradykinesiaResult> ?? [] // try to treat it as a set of results, if fail, use an empty set
        return results.sorted { $0.timestamp < $1.timestamp }
    }

    private func displayHand(_ raw: String?) -> String {
        guard let raw, let hand = CurrentHand(rawValue: raw) else { return "Unknown" }
        return handName(hand)
    }

    private func targetGeometry(in size: CGSize) -> TargetGeometry {
        let width = Double(size.width)
        let height = Double(size.height)
        let radius = max(42, min(64, min(width * 0.16, height * 0.22)))
        let horizontalInset = max(radius + Double(Spacing.lg), width * 0.25)
        let leftX = min(horizontalInset, max(radius + Double(Spacing.md), width - radius - Double(Spacing.md)))
        let rightX = max(width - horizontalInset, radius + Double(Spacing.md))
        let centerY = height * 0.5

        return TargetGeometry(
            leftCenter: TapPoint(x: leftX, y: centerY),
            rightCenter: TapPoint(x: rightX, y: centerY),
            radius: radius
        )
    }

    private func configuration(for geometry: TargetGeometry) -> BradykinesiaTestConfiguration {
        BradykinesiaTestConfiguration(
            leftCenter: geometry.leftCenter,
            rightCenter: geometry.rightCenter,
            targetRadius: geometry.radius,
            handOrder: [.right, .left],
            screenScale: displayScale
        )
    }

    private func formatted(_ value: Double?) -> String {
        guard let value, value.isFinite else {
            return "Unavailable"
        }
        return String(format: "%.2f s", value)
    }
    

    private func refreshLatestResult() {
        do {
            latestSavedSession = try BradykinesiaStore.fetchLatestSession(in: context)
            latestResultFetchFailed = false
        } catch {
            latestSavedSession = nil
            latestResultFetchFailed = true
        }
    }
    
}

private struct PrimaryTestButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.button)
            .foregroundStyle(Color.textLight)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color.primaryColor.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}
