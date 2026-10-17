import XCTest
@testable import Kinesia

final class TapComponentZScoreTests: XCTestCase {

    private let window = ReportFixtures.window(days: 7)

    private func baseline(center: Double, spread: Double, hand: CurrentHand = .right) -> Baseline {
        Baseline(
            hand: hand,
            center: center,
            lower: center - spread,
            upper: center + spread,
            spread: spread,
            dayCount: 14,
            establishedOn: ReportFixtures.day(0)
        )
    }

    // MARK: - The three components

    func testThereAreThreeComponents() {
        XCTAssertEqual(TapComponent.allCases, [.speed, .rhythm, .decrement])
    }

    func testEveryComponentHasALabelAndAUnit() {
        for component in TapComponent.allCases {
            XCTAssertFalse(component.label.isEmpty)
            XCTAssertFalse(component.unitLabel.isEmpty)
        }
    }

    func testSpeedReadsTapsPerSecond() throws {
        let tapping = ReportFixtures.tapping(numTaps: 100, durationSec: 20)
        XCTAssertEqual(try XCTUnwrap(TapComponent.speed.value(tapping)), 5, accuracy: 1e-9)
    }

    func testRhythmReadsTheTapIntervalCV() throws {
        let tapping = ReportFixtures.tapping(cvTapInter: 12.5)
        XCTAssertEqual(try XCTUnwrap(TapComponent.rhythm.value(tapping)), 12.5, accuracy: 1e-9)
    }

    func testDecrementReadsTheTapIntervalSlope() throws {
        let tapping = ReportFixtures.tapping(tapInterSlope: 0.004)
        XCTAssertEqual(try XCTUnwrap(TapComponent.decrement.value(tapping)), 0.004, accuracy: 1e-9)
    }

    // The statistics are gated on isValid at the snapshot boundary; the counts are not, because
    // the store validates them separately.
    func testAnInvalidRowLosesRhythmAndDecrementButKeepsSpeed() {
        let tapping = ReportFixtures.tapping(
            numTaps: 100,
            durationSec: 20,
            cvTapInter: nil,
            tapInterSlope: nil,
            isValid: false
        )

        XCTAssertNotNil(TapComponent.speed.value(tapping))
        XCTAssertNil(TapComponent.rhythm.value(tapping))
        XCTAssertNil(TapComponent.decrement.value(tapping))
    }

    func testAZeroDurationGivesNoSpeed() {
        XCTAssertNil(TapComponent.speed.value(ReportFixtures.tapping(durationSec: 0)))
    }

    // MARK: - Sign convention

    // Positive z always means further from baseline in the worsening direction. Without this,
    // speed and rhythm would point opposite ways on one axis.
    func testSlowerTappingGivesAPositiveZ() throws {
        let z = try XCTUnwrap(
            TapComponents.zScore(3, baseline: baseline(center: 5, spread: 1), component: .speed)
        )
        XCTAssertEqual(z, 2, accuracy: 1e-9)
    }

    func testFasterTappingGivesANegativeZ() throws {
        let z = try XCTUnwrap(
            TapComponents.zScore(7, baseline: baseline(center: 5, spread: 1), component: .speed)
        )
        XCTAssertEqual(z, -2, accuracy: 1e-9)
    }

    func testMoreVariableRhythmGivesAPositiveZ() throws {
        let z = try XCTUnwrap(
            TapComponents.zScore(14, baseline: baseline(center: 10, spread: 2), component: .rhythm)
        )
        XCTAssertEqual(z, 2, accuracy: 1e-9)
    }

    func testSteeperDecrementGivesAPositiveZ() throws {
        let z = try XCTUnwrap(
            TapComponents.zScore(0.003, baseline: baseline(center: 0.001, spread: 0.001), component: .decrement)
        )
        XCTAssertEqual(z, 2, accuracy: 1e-9)
    }

    func testAValueAtBaselineIsZero() throws {
        for component in TapComponent.allCases {
            let z = try XCTUnwrap(
                TapComponents.zScore(5, baseline: baseline(center: 5, spread: 1), component: component)
            )
            XCTAssertEqual(z, 0, accuracy: 1e-9, "\(component)")
        }
    }

    func testTheSpeedAndRhythmSignsAreOpposite() {
        XCTAssertFalse(TapComponent.speed.higherIsWorse)
        XCTAssertTrue(TapComponent.rhythm.higherIsWorse)
        XCTAssertTrue(TapComponent.decrement.higherIsWorse)
    }

    // MARK: - When there is no z-score

    func testNoBaselineGivesNoZ() {
        XCTAssertNil(TapComponents.zScore(5, baseline: nil, component: .speed))
    }

    func testNoValueGivesNoZ() {
        XCTAssertNil(TapComponents.zScore(nil, baseline: baseline(center: 5, spread: 1), component: .speed))
    }

    // Every baseline day identical means no spread to measure distance against.
    func testAZeroSpreadGivesNoZ() {
        XCTAssertNil(TapComponents.zScore(7, baseline: baseline(center: 5, spread: 0), component: .speed))
    }

    func testANonFiniteValueGivesNoZ() {
        XCTAssertNil(TapComponents.zScore(.nan, baseline: baseline(center: 5, spread: 1), component: .speed))
    }

    // MARK: - Points

    func testThereIsOnePointPerDayPerComponent() {
        let points = TapComponents.points(
            sessions: ReportFixtures.history(count: 7) { _ in 5 },
            window: window,
            hand: .right,
            baselines: [:]
        )

        XCTAssertEqual(points.count, 7 * 3)
        for component in TapComponent.allCases {
            XCTAssertEqual(points.filter { $0.component == component }.count, 7)
        }
    }

    func testADayWithNoSessionHasNoValueAndNoZ() {
        let points = TapComponents.points(
            sessions: [ReportFixtures.session(dayOffset: 0)],
            window: window,
            hand: .right,
            baselines: [.speed: .established(baseline(center: 5, spread: 1))]
        )

        let speed = points.filter { $0.component == .speed }
        XCTAssertNotNil(speed[0].rawValue)
        XCTAssertNil(speed[3].rawValue)
        XCTAssertNil(speed[3].z)
    }

    func testWithoutABaselineThePointsStillCarryRawValues() throws {
        let points = TapComponents.points(
            sessions: [ReportFixtures.session(dayOffset: 0)],
            window: window,
            hand: .right,
            baselines: [:]
        )

        let speed = try XCTUnwrap(points.first { $0.component == .speed && $0.dayStart == ReportFixtures.day(0) })
        XCTAssertNotNil(speed.rawValue)
        XCTAssertNil(speed.z)
    }

    func testThePointsZMatchesTheStandaloneCalculation() throws {
        let known = baseline(center: 5, spread: 1)
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [ReportFixtures.tapping(numTaps: 60, durationSec: 20)] // 3 taps/sec
        )

        let points = TapComponents.points(
            sessions: [session],
            window: window,
            hand: .right,
            baselines: [.speed: .established(known)]
        )

        let speed = try XCTUnwrap(points.first { $0.component == .speed && $0.dayStart == ReportFixtures.day(0) })
        XCTAssertEqual(try XCTUnwrap(speed.z), 2, accuracy: 1e-9)
    }

    func testPointsUseTheDailyMedianWhenADayHasSeveralSessions() throws {
        let sessions = [4.0, 6.0, 5.0].enumerated().map { index, rate in
            ReportFixtures.session(
                dayOffset: 0,
                hour: 9 + index,
                tapping: [ReportFixtures.tapping(dayOffset: 0, hour: 9 + index, numTaps: Int(rate * 20), durationSec: 20)]
            )
        }

        let points = TapComponents.points(sessions: sessions, window: window, hand: .right, baselines: [:])
        let speed = try XCTUnwrap(points.first { $0.component == .speed && $0.dayStart == ReportFixtures.day(0) })
        XCTAssertEqual(try XCTUnwrap(speed.rawValue), 5, accuracy: 1e-9)
    }

    // MARK: - Baselines per component

    func testBaselineStatesCoverEveryComponent() {
        let states = TapComponents.baselineStates(
            history: ReportFixtures.history(count: 19) { _ in 5 },
            hand: .right,
            calendar: ReportFixtures.utc
        )

        XCTAssertEqual(Set(states.keys), Set(TapComponent.allCases))
    }

    func testEachComponentGetsItsOwnBaseline() throws {
        let history = (0..<19).map { offset in
            ReportFixtures.session(
                dayOffset: offset,
                tapping: [
                    ReportFixtures.tapping(
                        dayOffset: offset,
                        numTaps: 100,
                        durationSec: 20,
                        cvTapInter: 12,
                        tapInterSlope: 0.002
                    )
                ]
            )
        }

        let states = TapComponents.baselineStates(history: history, hand: .right, calendar: ReportFixtures.utc)

        XCTAssertEqual(try XCTUnwrap(states[.speed]?.baseline).center, 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(states[.rhythm]?.baseline).center, 12, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(states[.decrement]?.baseline).center, 0.002, accuracy: 1e-9)
    }

    // A component whose values were never available has no baseline, while the others do.
    func testAComponentWithNoDataHasNoBaselineWhileOthersDo() {
        let history = (0..<19).map { offset in
            ReportFixtures.session(
                dayOffset: offset,
                tapping: [ReportFixtures.tapping(dayOffset: offset, tapInterSlope: nil)]
            )
        }

        let states = TapComponents.baselineStates(history: history, hand: .right, calendar: ReportFixtures.utc)
        XCTAssertNotNil(states[.speed]?.baseline)
        XCTAssertNil(states[.decrement]?.baseline)
        XCTAssertEqual(states[.decrement], .familiarization(dayNumber: 0, of: 5))
    }

    func testShortHistoryLeavesEveryComponentWithoutABaseline() {
        let states = TapComponents.baselineStates(
            history: ReportFixtures.history(count: 10) { _ in 5 },
            hand: .right,
            calendar: ReportFixtures.utc
        )

        for component in TapComponent.allCases {
            XCTAssertNil(states[component]?.baseline, "\(component)")
        }
    }

    // MARK: - Accuracy

    func testAccuracyIsCorrectTapsOverTotalTaps() throws {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [ReportFixtures.tapping(numTaps: 100, numCorrectTaps: 90)]
        )

        let points = TapComponents.accuracy(sessions: [session], window: window, hand: .right)
        XCTAssertEqual(try XCTUnwrap(points[0].accuracy), 0.9, accuracy: 1e-9)
    }

    func testThereIsOneAccuracyPointPerDayInTheWindow() {
        let points = TapComponents.accuracy(
            sessions: [ReportFixtures.session(dayOffset: 0)],
            window: window,
            hand: .right
        )

        XCTAssertEqual(points.count, 7)
        XCTAssertNil(points[3].accuracy)
    }

    func testNoTapsGivesNoAccuracyRatherThanZeroOverZero() {
        let session = ReportFixtures.session(
            dayOffset: 0,
            tapping: [ReportFixtures.tapping(numTaps: 0, numCorrectTaps: 0)]
        )

        let points = TapComponents.accuracy(sessions: [session], window: window, hand: .right)
        XCTAssertNil(points[0].accuracy)
    }

    // Accuracy measures whether the patient followed the alternating instruction, so it is not
    // a z-score and is not one of the three components.
    func testAccuracyIsNotAComponent() {
        XCTAssertFalse(TapComponent.allCases.map(\.rawValue).contains("accuracy"))
    }
}
