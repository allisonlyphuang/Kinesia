import CoreData
import Foundation

enum BradykinesiaStoreError: Error {
    case metricTapCountMismatch(metrics: Int, samples: Int)
    case tapCountOutOfRange(Int)
    case invalidWallClockTimestamp
    case noAttempts
    case duplicateHand
    case invalidCaptureDuration(Double)
}

struct BradykinesiaStore {
    static let rawCaptureKind = "bradykinesia"
    static let rawCaptureSchemaVersion: Int16 = 1

    /// Persists an analyzer-produced metric bundle and the original raw trial without recalculating either.
    @discardableResult
    static func save(
        attempts: [HandAttempt],
        in context: NSManagedObjectContext
    ) throws -> TestSession {
        
        // validation before anything is created
        
        guard !attempts.isEmpty else {
            throw BradykinesiaStoreError.noAttempts
        }
        
        let hands = attempts.map(\.hand)
        guard Set(hands).count == hands.count else {
            throw BradykinesiaStoreError.duplicateHand
        }
        
        // do validation checks without creating anything
        
        for attempt in attempts {
            guard attempt.metrics.numTaps == attempt.trial.samples.count else {
                throw BradykinesiaStoreError.metricTapCountMismatch(
                    metrics: attempt.metrics.numTaps,
                    samples: attempt.trial.samples.count
                )
            }
            guard Int32(exactly: attempt.metrics.numTaps) != nil else {
                throw BradykinesiaStoreError.tapCountOutOfRange(attempt.metrics.numTaps)
            }
            guard Int32(exactly: attempt.metrics.numCorrectTaps) != nil else {
                throw BradykinesiaStoreError.tapCountOutOfRange(attempt.metrics.numCorrectTaps)
            }
            
            let duration = attempt.monotonicCompletedAt - attempt.trial.startedAt
            guard duration.isFinite, duration > 0 else {
                throw BradykinesiaStoreError.invalidCaptureDuration(duration)
            }
        }
        
        guard let startedAt = attempts.map(\.startedAt).min(), let completedAt = attempts.map(\.completedAt).max() else {
            throw BradykinesiaStoreError.noAttempts
        }
        
        let startedAtEpoch = startedAt.timeIntervalSince1970
        let completedAtEpoch = completedAt.timeIntervalSince1970
        let dayStart = Calendar.current.startOfDay(for: startedAt).timeIntervalSince1970
        guard startedAtEpoch.isFinite, completedAtEpoch.isFinite, dayStart.isFinite else {
            throw BradykinesiaStoreError.invalidWallClockTimestamp
        }
        
        
        
        let payloads = try attempts.map { try JSONEncoder().encode($0.trial) }
        
        // create one session
        let dose = try mostRecentDose(
            onOrAfter: dayStart,
            atOrBefore: startedAtEpoch,
            in: context
        )

        let session = TestSession(context: context)
        session.id = UUID()
        session.startedAt = startedAtEpoch
        session.completedAt = completedAtEpoch
        session.dayStart = dayStart
        if let dose {
            session.medicationContext = dose
            session.minutesSinceDose = (startedAtEpoch - dose.timestamp) / 60
        }
        
        
        // create two rows per attempt
        
        for (attempt, payload) in zip(attempts, payloads) {
            let result = BradykinesiaResult(context: context)
            result.id = UUID()
            result.timestamp = attempt.completedAt.timeIntervalSince1970
            result.dayStart = dayStart
            result.hand = attempt.hand.rawValue
            result.numTaps = Int32(attempt.metrics.numTaps)
            result.numCorrectTaps = Int32(attempt.metrics.numCorrectTaps)
            result.metricsVersion = Int16(BradykinesiaMetrics.metricsVersion)
            result.session = session
            result.durationSec = attempt.monotonicCompletedAt - attempt.trial.startedAt
            MetricMapping(metrics: attempt.metrics).apply(to: result)

            // TODO: Map MotionQC only when motion data exists; schema defaults are preserved for now.

            let rawCapture = RawCapture(context: context)
            rawCapture.id = UUID()
            rawCapture.kind = rawCaptureKind
            rawCapture.payload = payload
            rawCapture.schemaVersion = rawCaptureSchemaVersion
            rawCapture.timestamp = attempt.completedAt.timeIntervalSince1970
            rawCapture.session = session
        }
        
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return session
    }
    
    
    // most recent dose taken on the test's actual day (at or after local midnight), at or before the test began
    // returns nil when no such dose exists, callers must leave medicationContext unset in that case
    static func mostRecentDose(
        onOrAfter dayStart: TimeInterval,
        atOrBefore instant: TimeInterval,
        in context: NSManagedObjectContext
    ) throws -> MedicationLog? {
        let request = MedicationLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@ AND wasSkipped == NO",
            NSNumber(value: dayStart),
            NSNumber(value: instant)
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(MedicationLog.timestamp), ascending: false)
        ]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    /// Fetches persisted Bradykinesia results newest first by their explicit wall-clock timestamp.
    static func fetchResults(in context: NSManagedObjectContext) throws -> [BradykinesiaResult] {
        let request = BradykinesiaResult.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(BradykinesiaResult.timestamp), ascending: false)]
        return try context.fetch(request)
    }
    
    static func fetchLatestSession(in context: NSManagedObjectContext) throws -> TestSession? {
        let request = TestSession.fetchRequest()
        request.predicate = NSPredicate(format: "bradykinesiaResults.@count > 0")
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(TestSession.completedAt), ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchLatestResult(in context: NSManagedObjectContext) throws -> BradykinesiaResult? {
        let request = BradykinesiaResult.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(BradykinesiaResult.timestamp), ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    
    }

    /// Required Core Data numeric attributes use zero only as a storage placeholder when `isValid` is false.
    /// Consumers must consult `isValid` and `invalidReason` before interpreting mapped numeric metrics.
    private struct MetricMapping {
        private let tapInterStats: SummaryStats?
        private let tapInterSkew: Double?
        private let driftLeftStats: SummaryStats?
        private let driftLeftSkew: Double?
        private let driftRightStats: SummaryStats?
        private let driftRightSkew: Double?
        private let correlationXY: Double?
        private let invalidReasons: [String]
        private let cvTapInter: Double?
        private let cvDriftLeft: Double?
        private let cvDriftRight: Double?
        private let tapInterSlope: Double?

        init(metrics: BradykinesiaMetrics) {
            tapInterStats = Self.finiteStats(metrics.tapInterStats)
            tapInterSkew = Self.finiteValue(metrics.skewTapInter)
            driftLeftStats = Self.finiteStats(metrics.driftLeftStats)
            driftLeftSkew = Self.finiteValue(metrics.skewDriftLeft)
            driftRightStats = Self.finiteStats(metrics.driftRightStats)
            driftRightSkew = Self.finiteValue(metrics.skewDriftRight)
            correlationXY = Self.finiteValue(metrics.corXY)
            cvTapInter = Self.finiteValue(metrics.cvTapInter)
            cvDriftLeft = Self.finiteValue(metrics.cvDriftLeft)
            cvDriftRight = Self.finiteValue(metrics.cvDriftRight)
            tapInterSlope = Self.finiteValue(metrics.tapInterSlope)




            var reasons: [String] = []
            if tapInterStats == nil {
                reasons.append("tap interval statistics unavailable")
            }
            if tapInterSkew == nil {
                reasons.append("tap interval skew unavailable")
            }
            if driftLeftStats == nil {
                reasons.append("left drift statistics unavailable")
            }
            if driftLeftSkew == nil {
                reasons.append("left drift skew unavailable")
            }
            if driftRightStats == nil {
                reasons.append("right drift statistics unavailable")
            }
            if driftRightSkew == nil {
                reasons.append("right drift skew unavailable")
            }
            if correlationXY == nil {
                reasons.append("x/y correlation unavailable")
            }
            if cvTapInter == nil {
                reasons.append("tap interval coefficient of variation unavailable")
            }
            if cvDriftLeft == nil {
                reasons.append("left drift coefficient of variation unavailable")
            }
            if cvDriftRight == nil {
                reasons.append("right drift coefficient of variation unavailable")
            }
            if tapInterSlope == nil {
                reasons.append("tap interval slope unavailable")
            }
            invalidReasons = reasons
        }

        func apply(to result: BradykinesiaResult) {
            apply(tapInterStats, to: (\BradykinesiaResult.tapInterMin, \BradykinesiaResult.tapInterMax, \BradykinesiaResult.tapInterMean, \BradykinesiaResult.tapInterMedian, \BradykinesiaResult.tapInterP25, \BradykinesiaResult.tapInterP75, \BradykinesiaResult.tapInterStdev), result: result)
            result.tapInterSkew = value(tapInterSkew)
            result.cvTapInter = value(cvTapInter)
            result.tapInterSlope = value(tapInterSlope)

            apply(driftLeftStats, to: (\BradykinesiaResult.driftLeftMin, \BradykinesiaResult.driftLeftMax, \BradykinesiaResult.driftLeftMean, \BradykinesiaResult.driftLeftMedian, \BradykinesiaResult.driftLeftP25, \BradykinesiaResult.driftLeftP75, \BradykinesiaResult.driftLeftStdev), result: result)
            result.driftLeftSkew = value(driftLeftSkew)
            result.cvDriftLeft = value(cvDriftLeft)

            apply(driftRightStats, to: (\BradykinesiaResult.driftRightMin, \BradykinesiaResult.driftRightMax, \BradykinesiaResult.driftRightMean, \BradykinesiaResult.driftRightMedian, \BradykinesiaResult.driftRightP25, \BradykinesiaResult.driftRightP75, \BradykinesiaResult.driftRightStdev), result: result)
            result.driftRightSkew = value(driftRightSkew)
            result.cvDriftRight = value(cvDriftRight)
            
            result.corXY = value(correlationXY)

            result.isValid = invalidReasons.isEmpty
            result.invalidReason = invalidReasons.isEmpty ? nil : invalidReasons.joined(separator: "; ")
        }

        private func apply(
            _ stats: SummaryStats?,
            to fields: (ReferenceWritableKeyPath<BradykinesiaResult, Double>, ReferenceWritableKeyPath<BradykinesiaResult, Double>, ReferenceWritableKeyPath<BradykinesiaResult, Double>, ReferenceWritableKeyPath<BradykinesiaResult, Double>, ReferenceWritableKeyPath<BradykinesiaResult, Double>, ReferenceWritableKeyPath<BradykinesiaResult, Double>, ReferenceWritableKeyPath<BradykinesiaResult, Double>),
            result: BradykinesiaResult
        ) {
            result[keyPath: fields.0] = value(stats?.min)
            result[keyPath: fields.1] = value(stats?.max)
            result[keyPath: fields.2] = value(stats?.mean)
            result[keyPath: fields.3] = value(stats?.median)
            result[keyPath: fields.4] = value(stats?.p25)
            result[keyPath: fields.5] = value(stats?.p75)
            result[keyPath: fields.6] = value(stats?.stdev)
        }

        private func value(_ metric: Double?) -> Double {
            guard let metric else {
                return 0
            }
            return metric
        }

        private static func finiteValue(_ metric: Double?) -> Double? {
            guard let metric, metric.isFinite else {
                return nil
            }
            return metric
        }

        private static func finiteStats(_ stats: SummaryStats?) -> SummaryStats? {
            guard let stats,
                  [
                    stats.min,
                    stats.max,
                    stats.mean,
                    stats.median,
                    stats.p25,
                    stats.p75,
                    stats.stdev,
                    stats.range,
                    stats.iqr,
                    stats.p90,
                    stats.mad
                  ].allSatisfy(\.isFinite) else {
                return nil
            }
            return stats
        }
        
    }
}
