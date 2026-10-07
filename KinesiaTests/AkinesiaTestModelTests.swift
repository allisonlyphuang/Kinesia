import CoreData
import XCTest
@testable import Kinesia

/// The model is driven synchronously: `automaticallyScheduleTimers: false` means no timer ever
/// fires on its own, and each test calls the `...Elapsed()` hooks itself. A whole session runs in
/// microseconds, the same approach `BradykinesiaTestModelTests` uses.
@MainActor
final class AkinesiaTestModelTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        let modelBundle = Bundle(for: AkinesiaResult.self)
        let modelURL = try XCTUnwrap(modelBundle.url(forResource: "Kinesia", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        container = NSPersistentContainer(name: "Kinesia", managedObjectModel: model)

        let storeDescription = NSPersistentStoreDescription()
        storeDescription.type = NSInMemoryStoreType
        storeDescription.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [storeDescription]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private let geometry = FireflyBoardGeometry(
        center: TapPoint(x: 150, y: 150),
        homeBaseRadius: 40,
        fireflyRadius: 30
    )

    private var ring: SpawnRing {
        SpawnRing(center: TapPoint(x: 150, y: 150), radius: 100, tolerance: 8, arcStart: 0, arcEnd: 2 * .pi)
    }

    private func configuration(
        practiceRounds: Int = 0,
        scoredRounds: Int = 2
    ) -> AkinesiaTestConfiguration {
        AkinesiaTestConfiguration(
            boardGeometry: geometry,
            ring: ring,
            practiceRounds: practiceRounds,
            scoredRounds: scoredRounds,
            foreperiodRange: 1.0...4.0,
            hand: .right,
            digit: "index",
            screenScale: 3
        )
    }

    /// A clock that advances on every read. A constant clock would make the session's own bounds
    /// degenerate, the same trap documented for the bradykinesia model.
    private func advancingClock(from start: TimeInterval = 100, step: TimeInterval = 0.001) -> () -> TimeInterval {
        var now = start
        return {
            defer { now += step }
            return now
        }
    }

    private final class SaveRecorder {
        var attempts: [AkinesiaAttempt] = []
        var errorToThrow: Error?
    }

    private func makeModel(
        practiceRounds: Int = 0,
        scoredRounds: Int = 2,
        foreperiod: TimeInterval = 2.0,
        spawn: TapPoint = TapPoint(x: 150, y: 50),
        recorder: SaveRecorder? = nil
    ) -> AkinesiaTestModel {
        AkinesiaTestModel(
            configuration: configuration(practiceRounds: practiceRounds, scoredRounds: scoredRounds),
            context: context,
            monotonicNow: advancingClock(),
            wallClockNow: { Date(timeIntervalSince1970: 1_800_000_000) },
            foreperiodGenerator: { _ in foreperiod },
            spawnGenerator: { _ in spawn },
            deviceIdentity: { AkinesiaDeviceIdentity(model: "iPhone", systemVersion: "26.5") },
            automaticallyScheduleTimers: false,
            persistenceAction: { attempt, _ in
                if let error = recorder?.errorToThrow { throw error }
                recorder?.attempts.append(attempt)
                return TestSession(context: self.context)
            }
        )
    }

    /// Plays one clean round end to end, leaving the finger on the jar for the next one.
    private func playCleanRound(
        _ model: AkinesiaTestModel,
        homeAt: TimeInterval,
        cueAt: TimeInterval,
        liftAt: TimeInterval,
        catchAt: TimeInterval,
        returnAt: TimeInterval
    ) {
        model.handleTouchDown(.home, at: homeAt, location: CGPoint(x: 150, y: 150))
        model.settleElapsed()
        model.foreperiodElapsed()
        model.handleCueDisplayed(at: cueAt)
        model.handleHomeTouchUp(.lifted, at: liftAt)
        model.handleTouchDown(.firefly, at: catchAt, location: CGPoint(x: 150, y: 50))
        model.handleTouchDown(.home, at: returnAt, location: CGPoint(x: 150, y: 150))
    }

    // MARK: - Session lifecycle

    func testStartingWithoutPracticeGoesStraightToScoring() {
        let model = makeModel(practiceRounds: 0)

        XCTAssertEqual(model.sessionPhase, .ready)
        XCTAssertFalse(model.isCaptureActive)

        model.startRounds()

        XCTAssertEqual(model.sessionPhase, .scoring)
        XCTAssertTrue(model.isCaptureActive)
        XCTAssertEqual(model.roundPhase, .awaitingHome)
    }

    func testPracticeProgressAdvancesSeparatelyFromScoredProgress() {
        let model = makeModel(practiceRounds: 2, scoredRounds: 2)
        model.startRounds()

        XCTAssertEqual(model.currentPracticeRoundNumber, 1)
        XCTAssertEqual(model.completedPracticeRounds, 0)

        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)

        XCTAssertEqual(model.completedPracticeRounds, 1)
        XCTAssertEqual(model.currentPracticeRoundNumber, 2)
        XCTAssertEqual(model.completedScoredRounds, 0, "practice never advances the scored count")
    }

    func testStartingWithPracticeEntersPracticingFirstAndSwitchesAfterThem() {
        let model = makeModel(practiceRounds: 2, scoredRounds: 2)
        model.startRounds()
        XCTAssertEqual(model.sessionPhase, .practicing)

        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)
        XCTAssertEqual(model.sessionPhase, .practicing, "one practice round done, one to go")
        XCTAssertEqual(model.completedScoredRounds, 0, "practice never counts as a scored round")

        playCleanRound(model, homeAt: 13, cueAt: 15, liftAt: 15.3, catchAt: 15.55, returnAt: 15.9)
        XCTAssertEqual(model.sessionPhase, .scoring)
        XCTAssertEqual(model.completedScoredRounds, 0)
    }

    func testInstructionsPhaseIsOptionalAndDoesNotStartCapture() {
        let model = makeModel()
        model.beginInstructions()

        XCTAssertEqual(model.sessionPhase, .instructions)
        XCTAssertFalse(model.isCaptureActive)

        model.startRounds()
        XCTAssertEqual(model.sessionPhase, .scoring)
    }

    func testGeometryIsLockedOnceRoundsBegin() {
        let model = makeModel()
        let moved = AkinesiaTestConfiguration(
            boardGeometry: FireflyBoardGeometry(center: TapPoint(x: 10, y: 10), homeBaseRadius: 30, fireflyRadius: 25),
            ring: ring
        )

        model.configure(moved)
        XCTAssertEqual(model.configuration.boardGeometry.center, TapPoint(x: 10, y: 10))

        model.startRounds()
        model.configure(configuration())
        XCTAssertEqual(
            model.configuration.boardGeometry.center,
            TapPoint(x: 10, y: 10),
            "configuration accepted after the first round would not match the stored trial"
        )
    }

    // MARK: - One clean round

    func testACleanRoundRecordsEveryTimestampFromTheBoard() throws {
        let recorder = SaveRecorder()
        let model = makeModel(scoredRounds: 1, recorder: recorder)
        model.startRounds()

        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)

        XCTAssertEqual(model.sessionPhase, .finished)
        let round = try XCTUnwrap(recorder.attempts.first?.trial.rounds.first)
        XCTAssertEqual(round.cueOnsetAt, 12)
        XCTAssertEqual(round.liftOffAt, 12.3)
        XCTAssertEqual(round.catchAt, 12.55)
        XCTAssertEqual(round.returnedHomeAt, 12.9, "the return leg is unscored but its time is still needed")
        XCTAssertEqual(round.captureOutcome, .completed)
        XCTAssertFalse(round.isPractice)
        XCTAssertEqual(round.plannedForeperiod, 2.0)
    }

    func testTheFireflyIsRequestedOnlyWhenTheForeperiodElapsesAndClearedOnTheCatch() {
        let model = makeModel(scoredRounds: 1)
        model.startRounds()

        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()
        XCTAssertNil(model.fireflyAt, "nothing is shown while the patient waits")

        model.foreperiodElapsed()
        XCTAssertEqual(model.fireflyAt, TapPoint(x: 150, y: 50))

        model.handleCueDisplayed(at: 12)
        model.handleHomeTouchUp(.lifted, at: 12.3)
        XCTAssertEqual(model.fireflyAt, TapPoint(x: 150, y: 50), "still lit while the finger travels")

        model.handleTouchDown(.firefly, at: 12.55, location: .zero)
        XCTAssertNil(model.fireflyAt)
    }

    func testThePhaseDoesNotAdvanceUntilTheBoardConfirmsTheFrame() {
        // Between asking for a firefly and the board presenting it, the patient cannot have seen
        // it yet, so a lift in that window is still a false start.
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()
        model.foreperiodElapsed()

        XCTAssertEqual(model.roundPhase, .foreperiod)

        model.handleHomeTouchUp(.lifted, at: 11.9)
        model.handleTouchDown(.elsewhere, at: 11.95, location: .zero)

        XCTAssertEqual(model.rounds.first?.captureOutcome, .falseStart)
    }

    // MARK: - False start, slip, missed

    func testALiftDuringTheForeperiodFollowedByATouchIsAFalseStart() throws {
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()

        model.handleHomeTouchUp(.lifted, at: 11.0)
        XCTAssertEqual(model.roundPhase, .resolvingLift)

        model.handleTouchDown(.elsewhere, at: 11.05, location: .zero)

        let round = try XCTUnwrap(model.rounds.first)
        XCTAssertEqual(round.captureOutcome, .falseStart)
        XCTAssertNil(round.cueOnsetAt, "the firefly never appeared")
        XCTAssertEqual(model.lastRoundFeedback, .falseStart)
        XCTAssertEqual(model.roundPhase, .awaitingHome, "the patient tries again")
    }

    func testALiftDuringTheForeperiodWithNoFollowUpTouchIsASlip() throws {
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()

        model.handleHomeTouchUp(.lifted, at: 11.0)
        model.slipWindowElapsed()

        let round = try XCTUnwrap(model.rounds.first)
        XCTAssertEqual(round.captureOutcome, .slip)
        XCTAssertEqual(model.lastRoundFeedback, .slip)
        XCTAssertEqual(model.roundPhase, .awaitingHome)
    }

    func testNoLiftWithinTheResponseCeilingIsAMissedRound() throws {
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()
        model.foreperiodElapsed()
        model.handleCueDisplayed(at: 12)

        model.responseCeilingElapsed()

        let round = try XCTUnwrap(model.rounds.first)
        XCTAssertEqual(round.captureOutcome, .missed)
        XCTAssertEqual(round.cueOnsetAt, 12)
        XCTAssertNil(round.liftOffAt)
        XCTAssertNil(model.fireflyAt)
    }

    func testALiftWithNoCatchStillRecordsTheReactionTime() throws {
        // Movement time is a by-product; losing it must not cost the akinesia measurement.
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()
        model.foreperiodElapsed()
        model.handleCueDisplayed(at: 12)
        model.handleHomeTouchUp(.lifted, at: 12.3)

        model.movementCeilingElapsed()
        model.handleTouchDown(.home, at: 18, location: .zero)

        let round = try XCTUnwrap(model.rounds.first)
        XCTAssertEqual(round.captureOutcome, .completed)
        XCTAssertEqual(round.liftOffAt, 12.3)
        XCTAssertNil(round.catchAt)
    }

    func testADragOutOfTheJarCountsAsLiftOff() throws {
        // Some patients slide instead of lifting; the board reports .draggedOut and the timing
        // must be treated identically.
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()
        model.foreperiodElapsed()
        model.handleCueDisplayed(at: 12)

        model.handleHomeTouchUp(.draggedOut, at: 12.28)
        model.handleTouchDown(.firefly, at: 12.5, location: .zero)
        model.handleTouchDown(.home, at: 12.9, location: .zero)

        let round = try XCTUnwrap(model.rounds.first)
        XCTAssertEqual(round.liftOffAt, 12.28)
        XCTAssertEqual(round.catchAt, 12.5)
    }

    func testASystemCancellationDiscardsTheRoundInsteadOfRecordingASlip() {
        // A phone call is not an observation about the patient, and inflating the slip count
        // would corrupt a signal the plan treats as meaningful.
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()

        model.handleHomeTouchUp(.cancelled, at: 11.0)

        XCTAssertTrue(model.rounds.isEmpty, "nothing is recorded")
        XCTAssertEqual(model.interruptedRoundCount, 1)
        XCTAssertEqual(model.lastRoundFeedback, .interrupted)
        XCTAssertEqual(model.roundPhase, .awaitingHome)
        XCTAssertEqual(model.sessionPhase, .scoring, "the session continues; the round is retried")
    }

    func testAFingerLiftedBeforeSettlingStartsNoRound() {
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)

        model.handleHomeTouchUp(.lifted, at: 10.1)

        XCTAssertTrue(model.rounds.isEmpty)
        XCTAssertNil(model.lastRoundFeedback, "nothing happened worth telling the patient about")
        XCTAssertEqual(model.roundPhase, .awaitingHome)
    }

    // MARK: - Gating

    func testBoardEventsAreIgnoredBeforeTheSessionStarts() {
        let model = makeModel()

        model.handleTouchDown(.home, at: 1, location: .zero)
        model.handleCueDisplayed(at: 2)
        model.handleHomeTouchUp(.lifted, at: 3)

        XCTAssertEqual(model.roundPhase, .idle)
        XCTAssertTrue(model.rounds.isEmpty)
    }

    func testFailedRoundsDoNotCountTowardTheScoredTotal() {
        let model = makeModel(scoredRounds: 2)
        model.startRounds()

        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()
        model.handleHomeTouchUp(.lifted, at: 11)
        model.slipWindowElapsed()
        XCTAssertEqual(model.rounds.count, 1, "the slip is recorded")
        XCTAssertEqual(model.completedScoredRounds, 0, "but it does not use up one of the two rounds")

        playCleanRound(model, homeAt: 12, cueAt: 14, liftAt: 14.3, catchAt: 14.55, returnAt: 14.9)
        XCTAssertEqual(model.completedScoredRounds, 1)
        XCTAssertEqual(model.sessionPhase, .scoring, "still one measured round short")

        playCleanRound(model, homeAt: 16, cueAt: 18, liftAt: 18.3, catchAt: 18.55, returnAt: 18.9)
        XCTAssertEqual(model.sessionPhase, .finished)
        XCTAssertEqual(model.rounds.count, 3, "two measured rounds plus the recorded slip")
    }

    func testAMissedRoundCountsTowardTheTargetBecauseItIsAMeasurement() {
        // Failing to initiate within the ceiling is exactly what this test looks for, so unlike a
        // false start it is not retried.
        let model = makeModel(scoredRounds: 1)
        model.startRounds()
        model.handleTouchDown(.home, at: 10, location: .zero)
        model.settleElapsed()
        model.foreperiodElapsed()
        model.handleCueDisplayed(at: 12)

        model.responseCeilingElapsed()

        XCTAssertEqual(model.completedScoredRounds, 1)
        XCTAssertEqual(model.sessionPhase, .finished)
    }

    func testRepeatedFalseStartsDoNotShortenTheSession() {
        // The whole point of a fixed round count: a patient who false-starts a lot must still
        // finish with the same number of measured rounds as anyone else.
        let model = makeModel(scoredRounds: 1)
        model.startRounds()

        for attempt in 0..<3 {
            let base = 10.0 + Double(attempt)
            model.handleTouchDown(.home, at: base, location: .zero)
            model.settleElapsed()
            model.handleHomeTouchUp(.lifted, at: base + 0.5)
            model.handleTouchDown(.elsewhere, at: base + 0.55, location: .zero)
        }

        XCTAssertEqual(model.rounds.count, 3, "every false start is recorded")
        XCTAssertEqual(model.completedScoredRounds, 0)
        XCTAssertEqual(model.sessionPhase, .scoring, "still owed one measured round")

        playCleanRound(model, homeAt: 20, cueAt: 22, liftAt: 22.3, catchAt: 22.55, returnAt: 22.9)
        XCTAssertEqual(model.sessionPhase, .finished)
        XCTAssertEqual(model.rounds.count, 4)
    }

    // MARK: - Finishing

    func testTheSessionFinishesAfterTheConfiguredNumberOfScoredRounds() throws {
        let recorder = SaveRecorder()
        let model = makeModel(scoredRounds: 2, recorder: recorder)
        model.startRounds()

        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)
        XCTAssertEqual(model.sessionPhase, .scoring, "not finished yet")

        playCleanRound(model, homeAt: 13, cueAt: 15, liftAt: 15.3, catchAt: 15.55, returnAt: 15.9)

        XCTAssertEqual(model.sessionPhase, .finished)
        XCTAssertEqual(recorder.attempts.count, 1, "the store is called exactly once")
        XCTAssertFalse(model.isCaptureActive)
        XCTAssertNil(model.fireflyAt)
        XCTAssertEqual(try XCTUnwrap(recorder.attempts.first).trial.rounds.count, 2)
    }

    func testTheSavedTrialCarriesTheBoardAndSessionContext() throws {
        let recorder = SaveRecorder()
        let model = makeModel(scoredRounds: 1, recorder: recorder)
        model.handleFrameClockReady(refreshRateHz: 120)
        model.startRounds()
        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)

        let attempt = try XCTUnwrap(recorder.attempts.first)
        XCTAssertEqual(attempt.trial.hand, .right)
        XCTAssertEqual(attempt.trial.digit, "index")
        XCTAssertEqual(attempt.trial.refreshRateHz, 120, "needed to bound how precisely onset is known")
        XCTAssertEqual(attempt.trial.screenScale, 3)
        XCTAssertEqual(attempt.trial.cueModality, "visual")
        XCTAssertEqual(attempt.trial.homeBaseRadius, 40)
        XCTAssertEqual(attempt.trial.fireflyRadius, 30)
        XCTAssertEqual(attempt.trial.spawnRing.radius, 100)
        XCTAssertEqual(attempt.device.model, "iPhone")
    }

    func testTheSessionCapFinishesWithWhateverWasCollected() {
        let recorder = SaveRecorder()
        let model = makeModel(scoredRounds: 12, recorder: recorder)
        model.startRounds()
        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)

        model.sessionCapElapsed()

        XCTAssertEqual(model.sessionPhase, .finished)
        XCTAssertEqual(recorder.attempts.first?.trial.rounds.count, 1)
    }

    func testAFailedSaveSurfacesTheErrorWithoutRetrying() {
        let recorder = SaveRecorder()
        recorder.errorToThrow = AkinesiaTestModelError.storeNotImplemented
        let model = makeModel(scoredRounds: 1, recorder: recorder)
        model.startRounds()

        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)

        XCTAssertEqual(model.sessionPhase, .failed)
        XCTAssertNotNil(model.persistenceError)
        XCTAssertTrue(recorder.attempts.isEmpty)
    }

    func testTheDefaultPersistenceActionFailsLoudlyUntilTheStoreExists() {
        // AkinesiaStore is not written yet. A finished session must not look saved.
        let model = AkinesiaTestModel(
            configuration: configuration(scoredRounds: 1),
            context: context,
            monotonicNow: advancingClock(),
            foreperiodGenerator: { _ in 2.0 },
            spawnGenerator: { _ in TapPoint(x: 150, y: 50) },
            automaticallyScheduleTimers: false
        )
        model.startRounds()
        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)

        XCTAssertEqual(model.sessionPhase, .failed)
        XCTAssertTrue(model.persistenceError is AkinesiaTestModelError)
    }

    func testResetClearsEverythingSoASecondSessionDoesNotInherit() {
        let model = makeModel(scoredRounds: 2)
        model.startRounds()
        playCleanRound(model, homeAt: 10, cueAt: 12, liftAt: 12.3, catchAt: 12.55, returnAt: 12.9)

        model.reset()

        XCTAssertEqual(model.sessionPhase, .ready)
        XCTAssertEqual(model.roundPhase, .idle)
        XCTAssertTrue(model.rounds.isEmpty)
        XCTAssertEqual(model.completedScoredRounds, 0)
        XCTAssertNil(model.lastRoundFeedback)
        XCTAssertNil(model.fireflyAt)
        XCTAssertFalse(model.isCaptureActive)
    }

    // MARK: - Ring spawn

    func testRingSpawnStaysWithinToleranceAndInsideTheArc() {
        let ring = SpawnRing(center: TapPoint(x: 150, y: 150), radius: 100, tolerance: 8, arcStart: 0, arcEnd: 2 * .pi)

        for sample in [0.0, 0.25, 0.5, 0.75, 0.999] {
            let point = AkinesiaTestModel.ringSpawn(in: ring) { sample }
            let distance = hypot(point.x - ring.center.x, point.y - ring.center.y)
            XCTAssertGreaterThanOrEqual(distance, ring.radius - ring.tolerance - 0.000_001, "sample \(sample)")
            XCTAssertLessThanOrEqual(distance, ring.radius + ring.tolerance + 0.000_001, "sample \(sample)")
        }
    }

    func testRingSpawnHonoursARestrictedArc() {
        // Upper half only, in UIKit coordinates where y grows downward.
        let upper = SpawnRing(center: TapPoint(x: 150, y: 150), radius: 100, tolerance: 0, arcStart: .pi, arcEnd: 2 * .pi)

        for sample in [0.0, 0.3, 0.6, 0.99] {
            let point = AkinesiaTestModel.ringSpawn(in: upper) { sample }
            XCTAssertLessThanOrEqual(point.y, upper.center.y + 0.000_001, "sample \(sample) should stay above centre")
        }
    }

    func testRingSpawnIsDeterministicForAFixedRandomSource() {
        let first = AkinesiaTestModel.ringSpawn(in: ring) { 0.42 }
        let second = AkinesiaTestModel.ringSpawn(in: ring) { 0.42 }
        XCTAssertEqual(first, second)
    }
}
