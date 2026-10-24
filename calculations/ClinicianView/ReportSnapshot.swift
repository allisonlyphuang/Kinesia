import Foundation


nonisolated struct SessionSnapshot: Sendable {
    let id: UUID
    let startedAt: Date
    let dayStart: Date
    let minutesSinceDose: Double? // nil when medicationContext is nil
    let tapping: [TappingSnapshot] // one per hand
    let firefly: FireflySnapshot?
    let tracing: TracingSnapshot?
}

nonisolated struct TappingSnapshot: Sendable {
    let hand: CurrentHand
    let timestamp: Date
    let numTaps: Int
    let durationSec: Double
    let tapInterMedian: Double?
    let cvTapInter: Double?
    let tapInterSlope: Double?
    let numCorrectTaps: Int
    let isValid: Bool
    let invalidReason: String?
    let metricsVersion: Int
}

nonisolated struct FireflySnapshot: Sendable {
    let hand: CurrentHand
    let timestamp: Date
    let reactionTimeMedian: Double? // primary metric for firefly
    let reactionTimeP90: Double?
    let movementTimeMedian: Double?
    let numRounds: Int
    let numValidRounds: Int
    let numLapses: Int
    let numMissed: Int
    let isValid: Bool
    let invalidReason: String?
    let metricsVersion: Int
}

nonisolated struct TracingSnapshot: Sendable {
    let hand: CurrentHand
    let timestamp: Date
    let rmsError: Double? // primary metric for tracing
    let swipeSpeedMedian: Double?
    let fingerLifts: Int
    let numSequences: Int
    let doneSequences: Int
    let isValid: Bool
    let invalidReason: String?
    let metricsVersion: Int
}

nonisolated struct DoseSnapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let dayStart: Date
    let takenAt: Date
    let scheduledAt: Date?
    let wasSkipped: Bool
    let slotMinutesIntoDay: Int?
    
    var delayMinutes: Double? {
        guard let scheduledAt, !wasSkipped else { return nil }
        return takenAt.timeIntervalSince(scheduledAt) / 60
    }

    var isScheduled: Bool { scheduledAt != nil }
}
