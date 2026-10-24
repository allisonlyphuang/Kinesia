import CoreData
import Foundation

nonisolated extension TappingSnapshot {
    init? (_ row: BradykinesiaResult) {
        guard let hand = row.hand.flatMap(CurrentHand.init(rawValue:)) else { return nil }
        let valid = row.isValid
        
        self.init(
            hand: hand,
            timestamp: Date(timeIntervalSince1970: row.timestamp),
            numTaps: Int(row.numTaps),
            durationSec: row.durationSec,
            tapInterMedian: Self.measured(row.tapInterMedian, isValid: valid),
            cvTapInter: Self.measured(row.cvTapInter, isValid: valid),
            tapInterSlope: Self.measured(row.tapInterSlope, isValid: valid),
            numCorrectTaps: Int(row.numCorrectTaps),
            isValid: valid,
            invalidReason: row.invalidReason,
            metricsVersion: Int(row.metricsVersion)
        )
    }
    
    private static func measured(_ value: Double, isValid: Bool) -> Double? {
        guard isValid, value.isFinite else { return nil }
        return value
    }
}

nonisolated extension DoseSnapshot {
    init?(_ row: MedicationLog) {
        guard let id = row.id else { return nil }

        let schedule = row.schedule
        self.init(
            id: id,
            dayStart: Date(timeIntervalSince1970: row.dayStart),
            takenAt: row.takenDate,
            scheduledAt: row.scheduledDate,
            wasSkipped: row.wasSkipped,
            slotMinutesIntoDay: schedule.map { Int($0.hour) * 60 + Int($0.minute) }
        )
    }
}

nonisolated extension FireflySnapshot {
    init?(_ row: AkinesiaResult) {
        guard let hand = row.hand.flatMap(CurrentHand.init(rawValue:)) else { return nil }
        let valid = row.isValid

        self.init(
            hand: hand,
            timestamp: Date(timeIntervalSince1970: row.timestamp),
            reactionTimeMedian: Self.measured(row.reactionTimeMedian, isValid: valid),
            reactionTimeP90: Self.measured(row.reactionTimeP90, isValid: valid),
            movementTimeMedian: Self.measured(row.movementTimeMedian, isValid: valid),
            numRounds: Int(row.numRounds),
            numValidRounds: Int(row.numValidRounds),
            numLapses: Int(row.numLapses),
            numMissed: Int(row.numMissed),
            isValid: valid,
            invalidReason: row.invalidReason,
            metricsVersion: Int(row.metricsVersion)
        )
    }

    private static func measured(_ value: Double, isValid: Bool) -> Double? {
        guard isValid, value.isFinite else { return nil }
        return value
    }
}

nonisolated extension TracingSnapshot {
    init?(_ row: DexterityResult) {
        guard let hand = row.hand.flatMap(CurrentHand.init(rawValue:)) else { return nil }
        let valid = row.isValid

        self.init(
            hand: hand,
            timestamp: Date(timeIntervalSince1970: row.timestamp),
            rmsError: Self.measured(row.rmsError, isValid: valid),
            swipeSpeedMedian: Self.measured(row.swipeSpeedMedian, isValid: valid),
            fingerLifts: Int(row.fingerLifts),
            numSequences: Int(row.numSequences),
            doneSequences: Int(row.doneSequences),
            isValid: valid,
            invalidReason: row.invalidReason,
            metricsVersion: Int(row.metricsVersion)
        )
    }

    private static func measured(_ value: Double, isValid: Bool) -> Double? {
        guard isValid, value.isFinite else { return nil }
        return value
    }
}

nonisolated extension SessionSnapshot {
    init?(_ row: TestSession) {
        guard let id = row.id else { return nil }

        let tapping = (row.bradykinesiaResults as? Set<BradykinesiaResult> ?? [])
            .compactMap(TappingSnapshot.init)
            .sorted { $0.timestamp < $1.timestamp } // recovers hand order; the relationship is a set

        self.init(
            id: id,
            startedAt: Date(timeIntervalSince1970: row.startedAt),
            dayStart: Date(timeIntervalSince1970: row.dayStart),
            minutesSinceDose: Self.minutesSinceDose(row),
            tapping: tapping,
            firefly: row.akinesia.flatMap(FireflySnapshot.init),
            tracing: row.dexterity.flatMap(TracingSnapshot.init)
        )
    }

    // nil when no dose was taken on the session's own day before it started.
    //
    // The only correct test is medicationContext != nil. minutesSinceDose is a non-optional
    // Double defaulting to 0, so 0 means either "tested at the moment of a dose" or "no dose
    // that day". Testing the number drops every pre-first-dose session, which is the OFF-state
    // data the wearing-off question depends on.
    private static func minutesSinceDose(_ row: TestSession) -> Double? {
        guard row.medicationContext != nil, row.minutesSinceDose.isFinite else { return nil }
        return row.minutesSinceDose
    }
}
