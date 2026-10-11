import Combine
import CoreData
import Foundation

@MainActor
final class DexteritySessionModel: ObservableObject {
    enum Phase: Equatable {
        case instructions
        case practice
        case scored(round: Int)
        case saving
        case finished
        case failed(String)
    }

    typealias SaveAction = @MainActor (DexteritySessionCapture, DexterityScoredMetrics, Date, Date, NSManagedObjectContext) throws -> DexterityResult

    @Published private(set) var phase: Phase = .instructions
    @Published private(set) var practiceAttempts: [DexteritySequence] = []
    @Published private(set) var scoredAttempts: [DexteritySequence] = []
    @Published private(set) var completedScoredAttemptIndexes: [Int] = []
    @Published private(set) var attemptID = UUID()
    @Published private(set) var latestResult: DexterityResult?
    @Published private(set) var finalMetrics: DexterityScoredMetrics?

    private(set) var configuration: DexterityTestConfiguration?
    private var startedAt: Date?
    private var monotonicStartedAt: TimeInterval?
    private let saveAction: SaveAction

    init(saveAction: @escaping SaveAction = DexterityStore.save) {
        self.saveAction = saveAction
    }

    func configure(_ configuration: DexterityTestConfiguration) {
        guard self.configuration != configuration, configuration.invalidReason == nil else { return }
        guard phase == .instructions else { return }
        self.configuration = configuration
    }

    func start() {
        guard configuration != nil, phase == .instructions else { return }
        startedAt = Date()
        monotonicStartedAt = nil
        practiceAttempts = []
        scoredAttempts = []
        completedScoredAttemptIndexes = []
        finalMetrics = nil
        latestResult = nil
        phase = .practice
        startFreshAttempt()
    }

    func receive(sequence: DexteritySequence, monotonicStartedAt: TimeInterval, in context: NSManagedObjectContext) {
        guard configuration != nil else { return }
        if self.monotonicStartedAt == nil { self.monotonicStartedAt = monotonicStartedAt }

        switch phase {
        case .practice:
            practiceAttempts.append(sequence)
            if sequence.completed {
                phase = .scored(round: 1)
            }
            startFreshAttempt()
        case .scored:
            scoredAttempts.append(sequence)
            if sequence.completed {
                completedScoredAttemptIndexes.append(scoredAttempts.count - 1)
            }
            if completedScoredAttemptIndexes.count == DexterityProtocolV1.scoredCompletionsRequired {
                finishAndSave(in: context)
            } else {
                phase = .scored(round: completedScoredAttemptIndexes.count + 1)
                startFreshAttempt()
            }
        default:
            return
        }
    }

    func reset() {
        phase = .instructions
        practiceAttempts = []
        scoredAttempts = []
        completedScoredAttemptIndexes = []
        latestResult = nil
        finalMetrics = nil
        startedAt = nil
        monotonicStartedAt = nil
        attemptID = UUID()
    }

    func capture() -> DexteritySessionCapture? {
        guard let configuration, let monotonicStartedAt else { return nil }
        return DexteritySessionCapture(
            route: configuration.route,
            coordinateSpace: configuration.coordinateSpace,
            targetRadius: configuration.targetRadius,
            practiceAttempts: practiceAttempts,
            scoredAttempts: scoredAttempts,
            completedScoredAttemptIndexes: completedScoredAttemptIndexes,
            startedAt: monotonicStartedAt
        )
    }

    private func startFreshAttempt() { attemptID = UUID() }

    private func finishAndSave(in context: NSManagedObjectContext) {
        guard let capture = capture(),
              let startedAt else {
            phase = .failed("This session could not be completed.")
            return
        }
        guard let completedSequences = capture.completedScoredSequences else {
            phase = .failed("This session could not be completed.")
            return
        }
        let trial = DexterityTrial(
            route: capture.route,
            coordinateSpace: capture.coordinateSpace,
            sequences: completedSequences,
            startedAt: capture.startedAt
        )
        let metrics = DexterityAnalyzer.analyzeScored(trial)
        finalMetrics = metrics
        phase = .saving
        do {
            latestResult = try saveAction(capture, metrics, startedAt, Date(), context)
            phase = .finished
        } catch {
            phase = .failed("This session could not be saved.")
        }
    }
}
