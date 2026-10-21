import Foundation
@testable import Kinesia

// Snapshot builders for the clinician view derivation tests.
// Everything here is a value type, so no suite that uses these needs a Core Data store.
enum ReportFixtures {

    // A fixed UTC calendar so day boundaries do not change with the machine's time zone.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let referenceDay = utc.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    /// Local midnight `offset` days after the reference day.
    static func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: referenceDay)!
    }

    /// An instant inside the day `offset` days after the reference day.
    static func instant(_ offset: Int, hour: Int = 9, minute: Int = 0) -> Date {
        utc.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset))!
    }

    /// A window covering day(0) through day(days - 1).
    static func window(days: Int = 7) -> ReportWindow {
        ReportWindow(days: days, endingOn: day(days - 1), calendar: utc)!
    }

    static func tapping(
        hand: CurrentHand = .right,
        dayOffset: Int = 0,
        hour: Int = 9,
        numTaps: Int = 100,
        durationSec: Double = 20,
        tapInterMedian: Double? = 0.2,
        cvTapInter: Double? = 10,
        tapInterSlope: Double? = 0.001,
        numCorrectTaps: Int = 90,
        isValid: Bool = true,
        invalidReason: String? = nil,
        metricsVersion: Int = 1
    ) -> TappingSnapshot {
        TappingSnapshot(
            hand: hand,
            timestamp: instant(dayOffset, hour: hour),
            numTaps: numTaps,
            durationSec: durationSec,
            tapInterMedian: tapInterMedian,
            cvTapInter: cvTapInter,
            tapInterSlope: tapInterSlope,
            numCorrectTaps: numCorrectTaps,
            isValid: isValid,
            invalidReason: invalidReason,
            metricsVersion: metricsVersion
        )
    }

    static func firefly(
        hand: CurrentHand = .right,
        dayOffset: Int = 0,
        hour: Int = 9,
        reactionTimeMedian: Double? = 0.35,
        reactionTimeP90: Double? = 0.6,
        movementTimeMedian: Double? = 0.25,
        numRounds: Int = 12,
        numValidRounds: Int = 11,
        numLapses: Int = 1,
        numMissed: Int = 0,
        isValid: Bool = true,
        invalidReason: String? = nil,
        metricsVersion: Int = 1
    ) -> FireflySnapshot {
        FireflySnapshot(
            hand: hand,
            timestamp: instant(dayOffset, hour: hour),
            reactionTimeMedian: reactionTimeMedian,
            reactionTimeP90: reactionTimeP90,
            movementTimeMedian: movementTimeMedian,
            numRounds: numRounds,
            numValidRounds: numValidRounds,
            numLapses: numLapses,
            numMissed: numMissed,
            isValid: isValid,
            invalidReason: invalidReason,
            metricsVersion: metricsVersion
        )
    }

    static func tracing(
        hand: CurrentHand = .right,
        dayOffset: Int = 0,
        hour: Int = 9,
        rmsError: Double? = 4,
        swipeSpeedMedian: Double? = 30,
        fingerLifts: Int = 0,
        numSequences: Int = 3,
        doneSequences: Int = 3,
        isValid: Bool = true,
        invalidReason: String? = nil,
        metricsVersion: Int = 1
    ) -> TracingSnapshot {
        TracingSnapshot(
            hand: hand,
            timestamp: instant(dayOffset, hour: hour),
            rmsError: rmsError,
            swipeSpeedMedian: swipeSpeedMedian,
            fingerLifts: fingerLifts,
            numSequences: numSequences,
            doneSequences: doneSequences,
            isValid: isValid,
            invalidReason: invalidReason,
            metricsVersion: metricsVersion
        )
    }

    static func session(
        dayOffset: Int = 0,
        hour: Int = 9,
        minutesSinceDose: Double? = 60,
        tapping: [TappingSnapshot]? = nil,
        firefly: FireflySnapshot? = nil,
        tracing: TracingSnapshot? = nil
    ) -> SessionSnapshot {
        SessionSnapshot(
            id: UUID(),
            startedAt: instant(dayOffset, hour: hour),
            dayStart: day(dayOffset),
            minutesSinceDose: minutesSinceDose,
            tapping: tapping ?? [Self.tapping(dayOffset: dayOffset, hour: hour)],
            firefly: firefly,
            tracing: tracing
        )
    }

    static func dose(
        dayOffset: Int = 0,
        scheduledHour: Int = 8,
        scheduledMinute: Int = 0,
        delayMinutes: Double = 0,
        wasSkipped: Bool = false,
        scheduled: Bool = true,
        slotLabel: String? = nil
    ) -> DoseSnapshot {
        let scheduledAt = instant(dayOffset, hour: scheduledHour, minute: scheduledMinute)
        return DoseSnapshot(
            id: UUID(),
            dayStart: day(dayOffset),
            takenAt: scheduledAt.addingTimeInterval(delayMinutes * 60),
            scheduledAt: scheduled ? scheduledAt : nil,
            wasSkipped: wasSkipped,
            slotLabel: slotLabel,
            slotMinutesIntoDay: scheduled ? scheduledHour * 60 + scheduledMinute : nil
        )
    }

    /// `count` consecutive days of tapping, each with one session, oldest first.
    /// `tapRate` is converted to a tap count against a 20-second capture.
    static func history(count: Int, tapRate: (Int) -> Double) -> [SessionSnapshot] {
        (0..<count).map { offset in
            session(
                dayOffset: offset,
                tapping: [tapping(dayOffset: offset, numTaps: Int(tapRate(offset) * 20), durationSec: 20)]
            )
        }
    }
}
