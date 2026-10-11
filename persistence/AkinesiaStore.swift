import CoreData
import Foundation

enum AkinesiaStoreError: Error {
    case noRounds
    case roundCountMismatch(metrics: Int, trial: Int)
    case outcomeCountsDoNotSum(sum: Int, numRounds: Int)
    case countOutOfRange(String, Int)
    case invalidWallClockTimestamp
    case invalidSessionDuration(Double)
}

struct AkinesiaStore {
    
    static let rawCaptureKind = "akinesia"
    static let rawCaptureSchemaVersion: Int16 = 1
    
    @discardableResult
    static func save(
        attempt: AkinesiaAttempt,
        in context: NSManagedObjectContext
    ) throws -> TestSession {
        
        // MARK: Validate everything
        
        // all sessions have rounds?
        guard !attempt.trial.rounds.isEmpty else { throw AkinesiaStoreError.noRounds }
        
        // saved metrics are for this trial and not another trial?
        let expected = attempt.metrics.numRounds + attempt.metrics.numPracticeRounds
        guard expected == attempt.trial.rounds.count else {
            throw AkinesiaStoreError.roundCountMismatch(metrics: expected, trial: attempt.trial.rounds.count)
        }
        
        // outcome counts for each classification must sum correctly
        let m = attempt.metrics
        let sum = m.numValidRounds + m.numAnticipations + m.numLapses + m.numFalseStarts + m.numSlips + m.numMissed + m.numMalformed
        guard sum == m.numRounds else {
            throw AkinesiaStoreError.outcomeCountsDoNotSum(sum: sum, numRounds: m.numRounds)
        }
        
        // counts must fit datatype
        for (name, value) in [("numRounds", m.numRounds), ("numValidRounds", m.numValidRounds), ("numAnticipations", m.numAnticipations),("numLapses", m.numLapses), ("numFalseStarts", m.numFalseStarts),("numSlips", m.numSlips), ("numMissed", m.numMissed), ("numMalformed", m.numMalformed)] {
            
            guard Int32(exactly: value) != nil else {
                throw AkinesiaStoreError.countOutOfRange(name, value)
            }
        }
        
        // clock times must be real
        let startedAtEpoch = attempt.startedAt.timeIntervalSince1970
        let completedAtEpoch = attempt.completedAt.timeIntervalSince1970
        // according to the current day as the user's calendar is configured, return a new Date at midnight of attempt.startedAt expressed in timeIntervalSince1970
        let dayStart = Calendar.current.startOfDay(for: attempt.startedAt).timeIntervalSince1970
        guard startedAtEpoch.isFinite, completedAtEpoch.isFinite, dayStart.isFinite else {
            throw AkinesiaStoreError.invalidWallClockTimestamp
        }
        
        // duration must be positive
        
        let duration = attempt.monotonicCompletedAt - attempt.trial.startedAt
        guard duration.isFinite, duration > 0 else {
            throw AkinesiaStoreError.invalidSessionDuration(duration)
        }
        
        // MARK: Encode
        
        let payload = try JSONEncoder().encode(attempt.trial) // what's being encoded
        
        // MARK: Lookup medication dose
        
        let dose = try BradykinesiaStore.mostRecentDose(onOrAfter: dayStart, atOrBefore: startedAtEpoch, in: context)
        
        // MARK: Create session + result + raw capture
        
        let session = TestSession(context: context)
        session.id = UUID()
        session.startedAt = startedAtEpoch
        session.completedAt = completedAtEpoch
        session.dayStart = dayStart
        if let dose {
            session.medicationContext = dose
            session.minutesSinceDose = (startedAtEpoch - dose.timestamp) / 60
        }
        
        let result = AkinesiaResult(context: context)
        result.id = UUID()
        result.timestamp = completedAtEpoch
        result.dayStart = dayStart
        result.hand = attempt.trial.hand.rawValue
        result.metricsVersion = Int16(AkinesiaMetrics.metricsVersion)
        result.session = session
        MetricMapping(metrics: attempt.metrics).apply(to: result, metrics: attempt.metrics)
        
        let rawCapture = RawCapture(context: context)
        rawCapture.id = UUID()
        rawCapture.kind = rawCaptureKind
        rawCapture.payload = payload
        rawCapture.schemaVersion = rawCaptureSchemaVersion
        rawCapture.timestamp = completedAtEpoch
        rawCapture.session = session
        
        // MARK: save
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return session
    }
    
    // MARK: Reading back

    /// Akinesia results, newest first by their explicit wall-clock timestamp.
    static func fetchResults(in context: NSManagedObjectContext) throws -> [AkinesiaResult] {
        let request = AkinesiaResult.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(AkinesiaResult.timestamp), ascending: false)]
        return try context.fetch(request)
    }

    /// The most recently completed session. One result per session, so this is all the
    /// "latest saved test" panel needs.
    static func fetchLatestResult(in context: NSManagedObjectContext) throws -> AkinesiaResult? {
        let request = AkinesiaResult.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(AkinesiaResult.timestamp), ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// True once any session has been saved. Will drive the "practice only on the first session"
    /// rule; counting with a fetch limit avoids loading the row.
    static func hasCompletedSession(in context: NSManagedObjectContext) throws -> Bool {
        let request = AkinesiaResult.fetchRequest()
        request.fetchLimit = 1
        return try context.count(for: request) > 0
    }

    private struct MetricMapping {
        private let reactionStats: SummaryStats?
        private let movementStats: SummaryStats?
        private let invalidReasons: [String]
        
        init(metrics: AkinesiaMetrics) {
            reactionStats = Self.finite(metrics.reactionTimeStats)
            movementStats = Self.finite(metrics.movementTimeStats)
            
            var reasons: [String] = []
            if reactionStats == nil { reasons.append("reaction time statistics unavailable") }
            if movementStats == nil { reasons.append("movement time statistics unavailable") }
            invalidReasons = reasons
        }
        
        func apply(to result: AkinesiaResult, metrics: AkinesiaMetrics) {
            result.reactionTimeMin = value(reactionStats?.min)
            result.reactionTimeMax =  value(reactionStats?.max)
            result.reactionTimeMean = value(reactionStats?.mean)
            result.reactionTimeMedian = value(reactionStats?.median)
            result.reactionTimeP25 = value(reactionStats?.p25)
            result.reactionTimeP75 = value(reactionStats?.p75)
            result.reactionTimeP90 = value(reactionStats?.p90)
            result.reactionTimeStdev = value(reactionStats?.stdev)
            result.reactionTimeMAD = value(reactionStats?.mad)
            // leave out movementTimeP90
            result.movementTimeMin = value(movementStats?.min)
            result.movementTimeMax = value(movementStats?.max)
            result.movementTimeMean = value(movementStats?.mean)
            result.movementTimeMedian = value(movementStats?.median)
            result.movementTimeP25 = value(movementStats?.p25)
            result.movementTimeP75 = value(movementStats?.p75)
            result.movementTimeStdev = value(movementStats?.stdev)
            result.movementTimeMAD = value(movementStats?.mad)
            
            result.numRounds = Int32(metrics.numRounds)
            result.numPracticeRounds = Int32(metrics.numPracticeRounds)
            result.numValidRounds = Int32(metrics.numValidRounds)
            result.numSlips = Int32(metrics.numSlips)
            result.numLapses = Int32(metrics.numLapses)
            result.numFalseStarts = Int32(metrics.numFalseStarts)
            result.numMalformed = Int32(metrics.numMalformed)
            result.numMissed = Int32(metrics.numMissed)
            result.numAnticipations = Int32(metrics.numAnticipations)
            
            result.isValid = invalidReasons.isEmpty
            result.invalidReason = invalidReasons.isEmpty ? nil : invalidReasons.joined(separator: ";")
        }
        
        private func value(_ metric: Double?) -> Double { metric ?? 0 }
        
        // a bundle with infinity or NaN is not usable
        
        private static func finite(_ stats: SummaryStats?) -> SummaryStats? {
            guard let stats,[stats.min, stats.max, stats.mean, stats.median, stats.p25, stats.p75, stats.stdev, stats.mad].allSatisfy(\.isFinite) else { return nil }
            return stats
        }
    }
}

