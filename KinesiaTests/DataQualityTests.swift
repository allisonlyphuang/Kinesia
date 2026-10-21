import XCTest
@testable import Kinesia

final class DataQualityTests: XCTestCase {

    private let window = ReportFixtures.window(days: 7)
    private let noBaseline = BaselineState.familiarization(dayNumber: 0, of: 5)

    private func compute(
        sessions: [SessionSnapshot] = [],
        doses: [DoseSnapshot] = [],
        baselineState: BaselineState? = nil
    ) -> DataQuality {
        DataQualityReport.compute(
            sessions: sessions,
            doses: doses,
            window: window,
            baselineState: baselineState ?? noBaseline
        )
    }

    // MARK: - Counts

    func testDaysInWindowMatchesTheWindow() {
        XCTAssertEqual(compute().daysInWindow, 7)
    }

    func testDaysWithSessionsCountsDaysNotSessions() {
        let sessions = [
            ReportFixtures.session(dayOffset: 0, hour: 9),
            ReportFixtures.session(dayOffset: 0, hour: 14),
            ReportFixtures.session(dayOffset: 3, hour: 9)
        ]

        let quality = compute(sessions: sessions)
        XCTAssertEqual(quality.daysWithSessions, 2)
        XCTAssertEqual(quality.sessionCount, 3)
        XCTAssertEqual(quality.daysWithoutSessions, 5)
    }

    func testDaysWithADoseCountsDaysNotDoses() {
        let doses = [
            ReportFixtures.dose(dayOffset: 1, scheduledHour: 8),
            ReportFixtures.dose(dayOffset: 1, scheduledHour: 13),
            ReportFixtures.dose(dayOffset: 4, scheduledHour: 8)
        ]

        XCTAssertEqual(compute(doses: doses).daysWithAtLeastOneDoseLogged, 2)
    }

    func testASkippedDoseIsNotADayWithADoseLogged() {
        let doses = [ReportFixtures.dose(dayOffset: 0, wasSkipped: true)]
        XCTAssertEqual(compute(doses: doses).daysWithAtLeastOneDoseLogged, 0)
    }

    func testAnUnscheduledDoseCountsAsADoseLogged() {
        let doses = [ReportFixtures.dose(dayOffset: 0, scheduled: false)]
        XCTAssertEqual(compute(doses: doses).daysWithAtLeastOneDoseLogged, 1)
    }

    func testSessionsOutsideTheWindowAreNotCounted() {
        let sessions = [
            ReportFixtures.session(dayOffset: -1),
            ReportFixtures.session(dayOffset: 0),
            ReportFixtures.session(dayOffset: 7)
        ]

        let quality = compute(sessions: sessions)
        XCTAssertEqual(quality.sessionCount, 1)
        XCTAssertEqual(quality.daysWithSessions, 1)
    }

    // MARK: - The sparse warning

    func testFourDaysOfDataIsSparse() {
        let sessions = (0..<4).map { ReportFixtures.session(dayOffset: $0) }
        XCTAssertTrue(compute(sessions: sessions).isSparse)
    }

    func testFiveDaysOfDataIsNotSparse() {
        let sessions = (0..<5).map { ReportFixtures.session(dayOffset: $0) }
        XCTAssertFalse(compute(sessions: sessions).isSparse)
    }

    func testNoDataIsSparse() {
        XCTAssertTrue(compute().isSparse)
    }

    // MARK: - Excluded results

    func testAValidSessionIsNotExcluded() {
        XCTAssertTrue(compute(sessions: [ReportFixtures.session(dayOffset: 0)]).excludedSessions.isEmpty)
    }

    func testAnInvalidTappingResultIsNamedWithItsReason() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [
                ReportFixtures.tapping(
                    hand: .left,
                    isValid: false,
                    invalidReason: "tap interval slope unavailable"
                )
            ]
        )

        let excluded = try XCTUnwrap(compute(sessions: [session]).excludedSessions.first)
        XCTAssertEqual(excluded.task, DataQualityReport.tappingTask)
        XCTAssertEqual(excluded.hand, .left)
        XCTAssertEqual(excluded.reason, "tap interval slope unavailable")
        XCTAssertEqual(excluded.id, session.id)
    }

    // A session can have a usable tapping result and an unusable tracing one, so exclusions are
    // counted per result rather than per session.
    func testOneSessionCanContributeSeveralExclusions() {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [
                ReportFixtures.tapping(hand: .right, isValid: true),
                ReportFixtures.tapping(hand: .left, isValid: false, invalidReason: "a")
            ],
            firefly: ReportFixtures.firefly(isValid: false, invalidReason: "b"),
            tracing: ReportFixtures.tracing(isValid: false, invalidReason: "c")
        )

        let excluded = compute(sessions: [session]).excludedSessions
        XCTAssertEqual(excluded.count, 3)
        XCTAssertEqual(
            Set(excluded.map(\.task)),
            [DataQualityReport.tappingTask, DataQualityReport.fireflyTask, DataQualityReport.tracingTask]
        )
    }

    func testAnInvalidResultWithNoReasonSaysSo() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [ReportFixtures.tapping(isValid: false, invalidReason: nil)]
        )

        let excluded = try XCTUnwrap(compute(sessions: [session]).excludedSessions.first)
        XCTAssertEqual(excluded.reason, DataQualityReport.unstatedReason)
        XCTAssertFalse(excluded.reason.isEmpty)
    }

    func testExclusionsComeBackOldestFirst() {
        let sessions = [2, 0, 1].map { offset in
            ReportFixtures.session(
                dayOffset: offset,
                tapping: [ReportFixtures.tapping(dayOffset: offset, isValid: false, invalidReason: "x")]
            )
        }

        let dates = compute(sessions: sessions).excludedSessions.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    // The regulatory rule is to label a test by its task, not the symptom it is thought to
    // measure.
    func testTaskNamesDoNotNameASymptom() {
        let banned = ["bradykinesia", "akinesia", "dexterity", "tremor", "severity"]
        let tasks = [
            DataQualityReport.tappingTask,
            DataQualityReport.fireflyTask,
            DataQualityReport.tracingTask
        ]

        for task in tasks {
            XCTAssertFalse(task.isEmpty)
            for word in banned {
                XCTAssertFalse(task.lowercased().contains(word), "\"\(task)\" contains \"\(word)\"")
            }
        }
    }

    // MARK: - Metrics versions

    func testOneVersionInTheWindowIsNotADefinitionChange() {
        let sessions = (0..<3).map { offset in
            ReportFixtures.session(
                dayOffset: offset,
                tapping: [ReportFixtures.tapping(dayOffset: offset, metricsVersion: 1)]
            )
        }

        let quality = compute(sessions: sessions)
        XCTAssertEqual(quality.metricsVersionsInWindow, [1])
        XCTAssertFalse(quality.definitionChanged)
    }

    // Two versions in one window means a line would mix two definitions.
    func testTwoVersionsInTheWindowIsADefinitionChange() {
        let sessions = [
            ReportFixtures.session(dayOffset: 0, tapping: [ReportFixtures.tapping(dayOffset: 0, metricsVersion: 1)]),
            ReportFixtures.session(dayOffset: 1, tapping: [ReportFixtures.tapping(dayOffset: 1, metricsVersion: 2)])
        ]

        let quality = compute(sessions: sessions)
        XCTAssertEqual(quality.metricsVersionsInWindow, [1, 2])
        XCTAssertTrue(quality.definitionChanged)
    }

    // 0 means the row was written before versioning existed.
    func testUnversionedRowsShowAsZero() {
        let sessions = [
            ReportFixtures.session(dayOffset: 0, tapping: [ReportFixtures.tapping(dayOffset: 0, metricsVersion: 0)])
        ]
        XCTAssertEqual(compute(sessions: sessions).metricsVersionsInWindow, [0])
    }

    func testVersionsAreCollectedFromEveryTask() {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [ReportFixtures.tapping(metricsVersion: 1)],
            firefly: ReportFixtures.firefly(metricsVersion: 2),
            tracing: ReportFixtures.tracing(metricsVersion: 3)
        )

        XCTAssertEqual(compute(sessions: [session]).metricsVersionsInWindow, [1, 2, 3])
    }

    func testNoSessionsGivesNoVersions() {
        XCTAssertTrue(compute().metricsVersionsInWindow.isEmpty)
    }

    // MARK: - Baseline state

    func testTheBaselineStateIsCarriedThrough() throws {
        let baseline = Baseline(
            hand: .right,
            center: 5,
            lower: 4,
            upper: 6,
            spread: 1,
            dayCount: 14,
            establishedOn: ReportFixtures.day(18)
        )

        let quality = compute(baselineState: .established(baseline))
        XCTAssertEqual(try XCTUnwrap(quality.baselineState.baseline), baseline)
    }

    func testAStillBuildingBaselineIsReported() {
        let quality = compute(baselineState: .building(dayNumber: 9, of: 14))
        XCTAssertEqual(quality.baselineState, .building(dayNumber: 9, of: 14))
        XCTAssertNil(quality.baselineState.baseline)
    }
}
