import CoreData
import Foundation

enum DexterityStoreError: Error, Equatable {
    case incompleteScoredSequences
    case invalidMetrics(String)
    case invalidWallClockTimestamp
}

struct DexterityStore {
    static let rawCaptureKind = "dexterity"
    static let rawCaptureSchemaVersion: Int16 = 1

    @discardableResult
    static func save(
        capture: DexteritySessionCapture,
        metrics: DexterityScoredMetrics,
        startedAt: Date,
        completedAt: Date,
        in context: NSManagedObjectContext
    ) throws -> DexterityResult {
        guard let scoredSequences = capture.completedScoredSequences,
              scoredSequences.count == DexterityProtocolV1.scoredCompletionsRequired else {
            throw DexterityStoreError.incompleteScoredSequences
        }

        let invalidReason = validityReason(capture: capture, metrics: metrics)
        let startedEpoch = startedAt.timeIntervalSince1970
        let completedEpoch = completedAt.timeIntervalSince1970
        let dayStart = Calendar.current.startOfDay(for: startedAt).timeIntervalSince1970
        guard startedEpoch.isFinite, completedEpoch.isFinite, dayStart.isFinite else {
            throw DexterityStoreError.invalidWallClockTimestamp
        }

        let payload = try JSONEncoder().encode(capture)
        let session = TestSession(context: context)
        session.id = UUID()
        session.startedAt = startedEpoch
        session.completedAt = completedEpoch
        session.dayStart = dayStart

        let result = DexterityResult(context: context)
        result.id = UUID()
        result.timestamp = completedEpoch
        result.dayStart = dayStart
        result.hand = capture.hand
        result.numSequences = Int32(DexterityProtocolV1.scoredCompletionsRequired)
        result.doneSequences = Int32(scoredSequences.count)
        result.fingerLifts = Int32(capture.scoredAttempts.filter { !$0.completed && $0.endedByLift }.count)
        result.metricsVersion = Int16(DexterityMetrics.metricsVersion)
        result.session = session

        apply(metrics: metrics, invalidReason: invalidReason, to: result)

        let rawCapture = RawCapture(context: context)
        rawCapture.id = UUID()
        rawCapture.kind = rawCaptureKind
        rawCapture.schemaVersion = rawCaptureSchemaVersion
        rawCapture.timestamp = completedEpoch
        rawCapture.payload = payload
        rawCapture.session = session

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return result
    }

    static func fetchResults(in context: NSManagedObjectContext) throws -> [DexterityResult] {
        let request = DexterityResult.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(DexterityResult.timestamp), ascending: false)]
        return try context.fetch(request)
    }

    static func fetchLatestResult(in context: NSManagedObjectContext) throws -> DexterityResult? {
        let request = DexterityResult.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(DexterityResult.timestamp), ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func validityReason(capture: DexteritySessionCapture, metrics: DexterityScoredMetrics) -> String? {
        var reasons: [String] = []
        if capture.protocolIdentifier != DexterityProtocolV1.identifier || capture.protocolVersion != DexterityProtocolV1.version {
            reasons.append("protocol metadata is invalid")
        }
        if capture.hand != DexterityProtocolV1.hand || capture.digit != DexterityProtocolV1.digit {
            reasons.append("hand or digit metadata is invalid")
        }
        if capture.route != DexterityProtocolV1.route || capture.targetRadius != DexterityProtocolV1.targetRadius {
            reasons.append("protocol configuration does not match version 1")
        }
        if !DexterityAnalyzer.isCalculationValid(route: capture.route) || !capture.coordinateSpace.isCalculationValid || !capture.targetRadius.isFinite || capture.targetRadius <= 0 {
            reasons.append("capture configuration is invalid")
        }
        if metrics.aggregate.pathInvalidReason != nil || metrics.aggregate.speedInvalidReason != nil {
            reasons.append(metrics.aggregate.calculationInvalidReason ?? "metric calculation is invalid")
        }
        guard let rmsError = metrics.aggregate.rmsError,
              let rmsErrorMax = metrics.rmsErrorMax,
              let swipeDist = metrics.swipeDist,
              let speedStats = metrics.aggregate.swipeSpeedStats,
              [rmsError, rmsErrorMax, swipeDist, speedStats.min, speedStats.max, speedStats.mean, speedStats.median, speedStats.p25, speedStats.p75, speedStats.stdev].allSatisfy(\.isFinite) else {
            reasons.append("required metrics are unavailable")
            return reasons.joined(separator: "; ")
        }
        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }

    private static func apply(metrics: DexterityScoredMetrics, invalidReason: String?, to result: DexterityResult) {
        result.isValid = invalidReason == nil
        result.invalidReason = invalidReason
        guard invalidReason == nil,
              let rmsError = metrics.aggregate.rmsError,
              let rmsErrorMax = metrics.rmsErrorMax,
              let swipeDist = metrics.swipeDist,
              let stats = metrics.aggregate.swipeSpeedStats else {
            result.rmsError = 0
            result.rmsErrorMax = 0
            result.swipeDist = 0
            result.swipeSpeedMin = 0
            result.swipeSpeedMax = 0
            result.swipeSpeedMean = 0
            result.swipeSpeedMedian = 0
            result.swipeSpeedP25 = 0
            result.swipeSpeedP75 = 0
            result.swipeSpeedStdev = 0
            return
        }

        result.rmsError = rmsError
        result.rmsErrorMax = rmsErrorMax
        result.swipeDist = swipeDist
        result.swipeSpeedMin = stats.min
        result.swipeSpeedMax = stats.max
        result.swipeSpeedMean = stats.mean
        result.swipeSpeedMedian = stats.median
        result.swipeSpeedP25 = stats.p25
        result.swipeSpeedP75 = stats.p75
        result.swipeSpeedStdev = stats.stdev
    }
}
