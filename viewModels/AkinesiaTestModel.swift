import Combine
import CoreData
import Foundation
import UIKit

// Configuration

// Screen components for the session, and is locked once the round begins

struct AkinesiaTestConfiguration {
    let boardGeometry: FireflyBoardGeometry
    let ring: SpawnRing
    let practiceRounds: Int
    let scoredRounds: Int
    let foreperiodRange: ClosedRange<TimeInterval>
    
    // how long the finger has to stay on home base before the foreperiod starts
    let settleDuration: TimeInterval
    
    // after a lift during the foreperiod, how long to wait for the next touch before classifying it as a slip instead of false start
    let slipWindow: TimeInterval
         
    let responseCeiling: TimeInterval
    
    // After lift-off, how long to wait before closing the round
    // reaction time still counts, just no movement time
    let movementCeiling: TimeInterval
     
    let sessionCap: TimeInterval
    let hand: CurrentHand
    let digit: String
    let screenScale: Double
    let cueModality: String

    init(
        boardGeometry: FireflyBoardGeometry,
        ring: SpawnRing,
        practiceRounds: Int = 2,
        scoredRounds: Int = 12,
        foreperiodRange: ClosedRange<TimeInterval> = 1.0...4.0,
        settleDuration: TimeInterval = 0.3,
        slipWindow: TimeInterval = 0.15,
        responseCeiling: TimeInterval = 5.0,
        movementCeiling: TimeInterval = 5.0,
        sessionCap: TimeInterval = 90,
        hand: CurrentHand = .right,
        digit: String = "index",
        screenScale: Double = 1,
        cueModality: String = "visual"
    ) {
        precondition(practiceRounds >= 0)
        precondition(scoredRounds > 0)
        precondition(foreperiodRange.lowerBound > 0)
        precondition(settleDuration >= 0)
        precondition(slipWindow >= 0)
        precondition(responseCeiling > 0)
        precondition(movementCeiling > 0)
        precondition(sessionCap > 0)
        precondition(ring.radius > 0, "a ring of radius zero would spawn the firefly on the jar")
        precondition(
            ring.radius - ring.tolerance - boardGeometry.fireflyRadius > boardGeometry.homeBaseRadius,
            "the closest possible spawn must still clear the jar, or a catch is ambiguous"
        )

        self.boardGeometry = boardGeometry
        self.ring = ring
        self.practiceRounds = practiceRounds
        self.scoredRounds = scoredRounds
        self.foreperiodRange = foreperiodRange
        self.settleDuration = settleDuration
        self.slipWindow = slipWindow
        self.responseCeiling = responseCeiling
        self.movementCeiling = movementCeiling
        self.sessionCap = sessionCap
        self.hand = hand
        self.digit = digit
        self.screenScale = screenScale
        self.cueModality = cueModality
    }
}

// Session output

struct AkinesiaDeviceIdentity: Equatable {
    var model: String
    var systemVersion: String

    @MainActor
    static var current: AkinesiaDeviceIdentity {
        AkinesiaDeviceIdentity(
            model: UIDevice.current.model,
            systemVersion: UIDevice.current.systemVersion
        )
    }
}

// finished session to store
struct AkinesiaAttempt {
    let trial: AkinesiaTrial
    let metrics: AkinesiaMetrics
    let startedAt: Date          // wall clock
    let completedAt: Date        // wall clock
    let monotonicCompletedAt: TimeInterval
    let device: AkinesiaDeviceIdentity
}

enum AkinesiaTestModelError: LocalizedError {
    // `AkinesiaStore` does not exist yet. Until it does, a finished session reaches `.failed`
    /// rather than silently pretending to have saved.
    case storeNotImplemented

    var errorDescription: String? {
        switch self {
        case .storeNotImplemented:
            return "Akinesia results cannot be saved yet: AkinesiaStore is not implemented."
        }
    }
}

////// Model

// Runs one akinesia session
// sequences rounds, classifies board events,
// sends finished trial to analyzer and store
 
@MainActor
final class AkinesiaTestModel: ObservableObject {

    enum SessionPhase: Equatable {
        case ready
        case instructions
        case practicing
        case scoring
        case finished
        case failed
    }

    // summary for the message under the board
    enum RoundFeedback: Equatable {
        case caught
        case falseStart
        case slip
        case missed
        case interrupted
    }

    enum RoundPhase: Equatable {
        case idle
        case awaitingHome
        case settling
        case foreperiod
        case resolvingLift
        case cueVisible
        case moving
        case returningHome
    }

    typealias PersistenceAction = (AkinesiaAttempt, NSManagedObjectContext) throws -> TestSession

    ///// Published state

    @Published private(set) var sessionPhase: SessionPhase = .ready
    @Published private(set) var roundPhase: RoundPhase = .idle
    @Published private(set) var fireflyAt: TapPoint?
    @Published private(set) var isCaptureActive = false
    @Published private(set) var completedScoredRounds = 0
    @Published private(set) var lastRoundFeedback: RoundFeedback?
    @Published private(set) var persistenceError: Error?

    var totalScoredRounds: Int { configuration.scoredRounds }
    var totalPracticeRounds: Int { configuration.practiceRounds }
    var isAwaitingReturnHome: Bool { roundPhase == .returningHome }
    
    // 1 based, eg "Firefly 5 of 12". set to 0 before the first scored round starts
    var currentScoredRoundNumber: Int {
        min(completedScoredRounds + 1, configuration.scoredRounds)
    }

    // practice rounds banked so far. like the scored count, a retried round does not advance it
    var completedPracticeRounds: Int { practiceRoundsTowardTarget }

    // 1 based, eg "Practice firefly 1 of 2"
    var currentPracticeRoundNumber: Int {
        min(completedPracticeRounds + 1, max(configuration.practiceRounds, 1))
    }

    private(set) var configuration: AkinesiaTestConfiguration
    private(set) var rounds: [RoundRecord] = []
    private(set) var refreshRateHz: Double = 0
    private(set) var interruptedRoundCount = 0

    ///// Dependencies

    private let context: NSManagedObjectContext
    private let monotonicNow: () -> TimeInterval
    private let wallClockNow: () -> Date
    private let foreperiodGenerator: (ClosedRange<TimeInterval>) -> TimeInterval
    private let spawnGenerator: (SpawnRing) -> TapPoint

    private let deviceIdentity: (() -> AkinesiaDeviceIdentity)?
    private let persistenceAction: PersistenceAction
    private let automaticallyScheduleTimers: Bool

    ///// Internal state

    private static func consumesTarget(_ outcome: CaptureOutcome) -> Bool {
        switch outcome {
        case .completed, .missed: return true
        case .falseStart, .slip: return false
        }
    }

    private var practiceRoundsTowardTarget: Int {
        rounds.filter { $0.isPractice && Self.consumesTarget($0.captureOutcome) }.count
    }

    private var scoredRoundsTowardTarget: Int {
        rounds.filter { !$0.isPractice && Self.consumesTarget($0.captureOutcome) }.count
    }

    private struct RoundInProgress {
        var index: Int
        var isPractice: Bool
        var homeSettledAt: TimeInterval
        var plannedForeperiod: TimeInterval
        var cueOnsetAt: TimeInterval?
        var liftOffAt: TimeInterval?
        var catchAt: TimeInterval?
        var spawn: TapPoint?
    }

    private var current: RoundInProgress?
    private var isHomeTouchDown = false
    private var monotonicStartedAt: TimeInterval?
    private var wallClockStartedAt: Date?
    private var isFinishing = false


    private var transitionGeneration = 0
    private var deadlineTask: Task<Void, Never>?
    private var sessionCapTask: Task<Void, Never>?

    init(
        configuration: AkinesiaTestConfiguration,
        context: NSManagedObjectContext,
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wallClockNow: @escaping () -> Date = { Date() },
        foreperiodGenerator: @escaping (ClosedRange<TimeInterval>) -> TimeInterval = { Double.random(in: $0) },
        spawnGenerator: @escaping (SpawnRing) -> TapPoint = { AkinesiaTestModel.ringSpawn(in: $0) },
        deviceIdentity: (() -> AkinesiaDeviceIdentity)? = nil,
        automaticallyScheduleTimers: Bool = true,
        persistenceAction: PersistenceAction? = nil
    ) {
        self.configuration = configuration
        self.context = context
        self.monotonicNow = monotonicNow
        self.wallClockNow = wallClockNow
        self.foreperiodGenerator = foreperiodGenerator
        self.spawnGenerator = spawnGenerator
        self.deviceIdentity = deviceIdentity
        self.automaticallyScheduleTimers = automaticallyScheduleTimers
        self.persistenceAction = persistenceAction ?? { _, _ in
            throw AkinesiaTestModelError.storeNotImplemented
        }
    }

    deinit {
        deadlineTask?.cancel()
        sessionCapTask?.cancel()
    }

    ///// Spawn

    // Spawns at a point on the ring using a random angle within the arc, at the nominal distance +/- the tolerance
    nonisolated static func ringSpawn(
        in ring: SpawnRing,
        unitRandom: () -> Double = { Double.random(in: 0..<1) }
    ) -> TapPoint {
        let distance = ring.radius + (unitRandom() * 2 - 1) * ring.tolerance
        let angle = ring.arcStart + unitRandom() * (ring.arcEnd - ring.arcStart)
        return TapPoint(
            x: ring.center.x + distance * cos(angle),
            y: ring.center.y + distance * sin(angle)
        )
    }

    ///// Session lifecycle

    // Accepted only before rounds begin
    func configure(_ configuration: AkinesiaTestConfiguration) {
        switch sessionPhase {
        case .ready, .instructions:
            self.configuration = configuration
        case .practicing, .scoring, .finished, .failed:
            return
        }
    }

    func beginInstructions() {
        guard sessionPhase == .ready else { return }
        sessionPhase = .instructions
    }

    func startRounds() {
        guard sessionPhase == .ready || sessionPhase == .instructions else { return }

        rounds = []
        interruptedRoundCount = 0
        lastRoundFeedback = nil
        persistenceError = nil
        monotonicStartedAt = monotonicNow()
        wallClockStartedAt = wallClockNow()
        sessionPhase = configuration.practiceRounds > 0 ? .practicing : .scoring
        isCaptureActive = true
        beginAwaitingHome()
        scheduleSessionCap()
    }

    func reset() {
        cancelDeadline()
        sessionCapTask?.cancel()
        sessionCapTask = nil
        sessionPhase = .ready
        roundPhase = .idle
        fireflyAt = nil
        isCaptureActive = false
        completedScoredRounds = 0
        lastRoundFeedback = nil
        persistenceError = nil
        rounds = []
        interruptedRoundCount = 0
        current = nil
        isHomeTouchDown = false
        monotonicStartedAt = nil
        wallClockStartedAt = nil
        isFinishing = false
        transitionGeneration += 1
    }

    ///// Board events

    func handleFrameClockReady(refreshRateHz: Double) {
        guard refreshRateHz.isFinite, refreshRateHz > 0 else { return }
        self.refreshRateHz = refreshRateHz
    }

    func handleTouchDown(_ kind: BoardTouchKind, at timestamp: TimeInterval, location: CGPoint) {
        guard isCaptureActive else { return }

        switch (roundPhase, kind) {
        case (.awaitingHome, .home):
            isHomeTouchDown = true
            beginSettling()

        case (.resolvingLift, _):
            closeRound(as: .falseStart, feedback: .falseStart)

        case (.moving, .firefly):
            current?.catchAt = timestamp
            fireflyAt = nil
            closeRound(as: .completed, feedback: .caught, keepOpenForReturn: true)

        case (.returningHome, .home):
            isHomeTouchDown = true
            finishReturnLeg(at: timestamp)

        default:
            if kind == .home { isHomeTouchDown = true }
        }
    }

    func handleHomeTouchUp(_ reason: HomeLiftReason, at timestamp: TimeInterval) {
        isHomeTouchDown = false
        guard isCaptureActive else { return }

        if reason == .cancelled {
            // The system removed the touch, so the
            // round is discarded instead of recorded
            discardRound(feedback: .interrupted)
            return
        }

        switch roundPhase {
        case .settling:
            // Never settled, so no round had started. Just wait for the finger again.
            beginAwaitingHome()

        case .foreperiod:
            current?.liftOffAt = timestamp
            beginResolvingLift()

        case .cueVisible:
            current?.liftOffAt = timestamp
            beginMoving()

        default:
            break
        }
    }

    func handleCueDisplayed(at frameTimestamp: TimeInterval) {
        guard roundPhase == .foreperiod, current != nil else { return }
        current?.cueOnsetAt = frameTimestamp
        beginCueVisible()
    }

    ///// Deadlines

    func settleElapsed() {
        guard roundPhase == .settling else { return }
        beginForeperiod()
    }

    func foreperiodElapsed() {
        guard roundPhase == .foreperiod, current != nil else { return }
       
        let spawn = spawnGenerator(configuration.ring)
        current?.spawn = spawn
        fireflyAt = spawn
    }

    func slipWindowElapsed() {
        guard roundPhase == .resolvingLift else { return }
         closeRound(as: .slip, feedback: .slip)
    }

    func responseCeilingElapsed() {
        guard roundPhase == .cueVisible else { return }
        fireflyAt = nil
        closeRound(as: .missed, feedback: .missed)
    }

    func movementCeilingElapsed() {
        guard roundPhase == .moving else { return }
         
        fireflyAt = nil
        closeRound(as: .completed, feedback: .caught, keepOpenForReturn: true)
    }

    func sessionCapElapsed() {
        guard sessionPhase == .practicing || sessionPhase == .scoring else { return }
        finishSession()
    }

    // Round transitions

    private func beginAwaitingHome() {
        current = nil
        fireflyAt = nil
        transition(to: .awaitingHome)
        if isHomeTouchDown {

            beginSettling()
        }
    }

    private func beginSettling() {
        transition(to: .settling)
        schedule(configuration.settleDuration) { [weak self] in self?.settleElapsed() }
    }

    private func beginForeperiod() {
        let foreperiod = foreperiodGenerator(configuration.foreperiodRange)
        current = RoundInProgress(
            index: rounds.count,
            isPractice: practiceRoundsTowardTarget < configuration.practiceRounds,
            homeSettledAt: monotonicNow(),
            plannedForeperiod: foreperiod
        )
        transition(to: .foreperiod)
        schedule(foreperiod) { [weak self] in self?.foreperiodElapsed() }
    }

    private func beginResolvingLift() {
        transition(to: .resolvingLift)
        schedule(configuration.slipWindow) { [weak self] in self?.slipWindowElapsed() }
    }

    private func beginCueVisible() {
        transition(to: .cueVisible)
        schedule(configuration.responseCeiling) { [weak self] in self?.responseCeilingElapsed() }
    }

    private func beginMoving() {
        transition(to: .moving)
        schedule(configuration.movementCeiling) { [weak self] in self?.movementCeilingElapsed() }
    }

    private func transition(to phase: RoundPhase) {
        transitionGeneration += 1
        deadlineTask?.cancel()
        deadlineTask = nil
        roundPhase = phase
    }

    ///// Closing a round

    // Records the round and either waits for the return leg or moves on
    // the timestamp of a rounds return is the start of the next foreperiod and must be recorded
    private func closeRound(
        as outcome: CaptureOutcome,
        feedback: RoundFeedback,
        keepOpenForReturn: Bool = false
    ) {
        guard let round = current else {
            beginAwaitingHome()
            return
        }

        lastRoundFeedback = feedback

        if keepOpenForReturn {
            transition(to: .returningHome)
            pendingOutcome = outcome
            if isHomeTouchDown {
                // Already back on the jar: the catch finger and the home finger were the same one
                // and it never left, or the patient returned faster than this call.
                finishReturnLeg(at: round.catchAt ?? monotonicNow())
            }
            return
        }

        append(round, outcome: outcome, returnedHomeAt: nil)
        advanceAfterRound()
    }

    private var pendingOutcome: CaptureOutcome?

    private func finishReturnLeg(at timestamp: TimeInterval) {
        guard let round = current, let outcome = pendingOutcome else { return }
        pendingOutcome = nil
        append(round, outcome: outcome, returnedHomeAt: timestamp)
        advanceAfterRound()
    }

    private func append(_ round: RoundInProgress, outcome: CaptureOutcome, returnedHomeAt: TimeInterval?) {
        rounds.append(
            RoundRecord(
                index: round.index,
                isPractice: round.isPractice,
                homeSettledAt: round.homeSettledAt,
                plannedForeperiod: round.plannedForeperiod,
                cueOnsetAt: round.cueOnsetAt,
                liftOffAt: round.liftOffAt,
                catchAt: round.catchAt,
                returnedHomeAt: returnedHomeAt,
                spawn: round.spawn.map { SpawnPoint(x: $0.x, y: $0.y) },
                captureOutcome: outcome,
                // A placeholder. The analyzer recomputes every verdict from the timestamps and
                // ignores whatever is stored here; see AkinesiaAnalyzer.
                scoredOutcome: .valid
            )
        )
        current = nil
        completedScoredRounds = scoredRoundsTowardTarget
    }

    /// A round the system interrupted. Not recorded: it is not an observation about the patient.
    private func discardRound(feedback: RoundFeedback) {
        guard sessionPhase == .practicing || sessionPhase == .scoring else { return }
        if current != nil || roundPhase != .awaitingHome {
            interruptedRoundCount += 1
            lastRoundFeedback = feedback
        }
        pendingOutcome = nil
        beginAwaitingHome()
    }

    private func advanceAfterRound() {
        if sessionPhase == .practicing, practiceRoundsTowardTarget >= configuration.practiceRounds {
            sessionPhase = .scoring
        }
        if scoredRoundsTowardTarget >= configuration.scoredRounds {
            finishSession()
        } else {
            beginAwaitingHome()
        }
    }

    ///// Finishing

    private func finishSession() {
        guard !isFinishing,
              let monotonicStartedAt,
              let wallClockStartedAt else { return }

        isFinishing = true
        cancelDeadline()
        sessionCapTask?.cancel()
        sessionCapTask = nil

        fireflyAt = nil
        isCaptureActive = false
        roundPhase = .idle

        let trial = AkinesiaTrial(
            rounds: rounds,
            homeBaseCenter: SpawnPoint(
                x: configuration.boardGeometry.center.x,
                y: configuration.boardGeometry.center.y
            ),
            homeBaseRadius: configuration.boardGeometry.homeBaseRadius,
            fireflyRadius: configuration.boardGeometry.fireflyRadius,
            hand: configuration.hand,
            digit: configuration.digit,
            screenScale: configuration.screenScale,
            refreshRateHz: refreshRateHz,
            cueModality: configuration.cueModality,
            startedAt: monotonicStartedAt,
            spawnRing: configuration.ring
        )

        let attempt = AkinesiaAttempt(
            trial: trial,
            metrics: AkinesiaAnalyzer.analyze(trial),
            startedAt: wallClockStartedAt,
            completedAt: wallClockNow(),
            monotonicCompletedAt: monotonicNow(),
            device: deviceIdentity?() ?? AkinesiaDeviceIdentity.current
        )

        do {
            _ = try persistenceAction(attempt, context)
            persistenceError = nil
            sessionPhase = .finished
        } catch {
            persistenceError = error
            sessionPhase = .failed
        }
        isFinishing = false
    }

    ///// Timers

    private func schedule(_ duration: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        deadlineTask?.cancel()
        guard automaticallyScheduleTimers else { return }

        let generation = transitionGeneration
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.transitionGeneration == generation else { return }
            action()
        }
    }

    private func scheduleSessionCap() {
        sessionCapTask?.cancel()
        guard automaticallyScheduleTimers else { return }

        sessionCapTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.configuration.sessionCap * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.sessionCapElapsed()
        }
    }

    private func cancelDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
    }
}
