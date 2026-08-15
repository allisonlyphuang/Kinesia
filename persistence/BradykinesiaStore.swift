//
//  BradykinesiaStore.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import CoreData
import Foundation

enum BradykinesiaStoreError: Error {
    case metricTapCountMismatch(metrics: Int, samples: Int)
    case tapCountOutOfRange(Int)
    case invalidWallClockTimestamp
}

struct BradykinesiaStore {
    static let rawCaptureKind = "bradykinesia"
    static let rawCaptureSchemaVersion: Int16 = 1

    /// Persists an analyzer-produced metric bundle and the original raw trial without recalculating either.
    /// `startedAt` and `completedAt` are wall-clock dates; raw touch timestamps remain inside `trial` only.
    @discardableResult
    static func save(
        trial: TapTrial,
        metrics: BradykinesiaMetrics,
        startedAt: Date,
        completedAt: Date,
        in context: NSManagedObjectContext
    ) throws -> BradykinesiaResult {
        guard metrics.numTaps == trial.samples.count else {
            throw BradykinesiaStoreError.metricTapCountMismatch(
                metrics: metrics.numTaps,
                samples: trial.samples.count
            )
        }
        guard Int32(exactly: metrics.numTaps) != nil else {
            throw BradykinesiaStoreError.tapCountOutOfRange(metrics.numTaps)
        }

        let startedAtEpoch = startedAt.timeIntervalSince1970
        let completedAtEpoch = completedAt.timeIntervalSince1970
        guard startedAtEpoch.isFinite, completedAtEpoch.isFinite else {
            throw BradykinesiaStoreError.invalidWallClockTimestamp
        }

        let rawPayload = try JSONEncoder().encode(trial)
        let dayStart = Calendar.current.startOfDay(for: completedAt).timeIntervalSince1970
        guard dayStart.isFinite else {
            throw BradykinesiaStoreError.invalidWallClockTimestamp
        }

        let session = TestSession(context: context)
        session.id = UUID()
        session.startedAt = startedAtEpoch
        session.completedAt = completedAtEpoch
        session.dayStart = dayStart
        // TODO: Associate medicationContext once the selection rule is defined.

        let result = BradykinesiaResult(context: context)
        result.id = UUID()
        result.timestamp = completedAtEpoch
        result.dayStart = dayStart
        result.hand = trial.hand
        result.numTaps = Int32(metrics.numTaps)
        result.session = session
        // TODO: Map numCorrectTaps only after its correctness rule is defined. The required schema
        // default remains an unresolved placeholder and is never derived from TapTarget here.
        // TODO: Map MotionQC only when motion data exists; schema defaults are preserved for now.

        let mappedMetrics = MetricMapping(metrics: metrics)
        mappedMetrics.apply(to: result)

        let rawCapture = RawCapture(context: context)
        rawCapture.id = UUID()
        rawCapture.kind = rawCaptureKind
        rawCapture.payload = rawPayload
        rawCapture.schemaVersion = rawCaptureSchemaVersion
        rawCapture.timestamp = completedAtEpoch
        rawCapture.session = session

        try context.save()
        return result
    }

    /// Fetches persisted Bradykinesia results newest first by their explicit wall-clock timestamp.
    static func fetchResults(in context: NSManagedObjectContext) throws -> [BradykinesiaResult] {
        let request = BradykinesiaResult.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(BradykinesiaResult.timestamp), ascending: false)]
        return try context.fetch(request)
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

        init(metrics: BradykinesiaMetrics) {
            tapInterStats = Self.finiteStats(metrics.tapInterStats)
            tapInterSkew = Self.finiteValue(metrics.skewTapInter)
            driftLeftStats = Self.finiteStats(metrics.driftLeftStats)
            driftLeftSkew = Self.finiteValue(metrics.skewDriftLeft)
            driftRightStats = Self.finiteStats(metrics.driftRightStats)
            driftRightSkew = Self.finiteValue(metrics.skewDriftRight)
            correlationXY = Self.finiteValue(metrics.corXY)

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
            invalidReasons = reasons
        }

        func apply(to result: BradykinesiaResult) {
            apply(tapInterStats, to: (\BradykinesiaResult.tapInterMin, \BradykinesiaResult.tapInterMax, \BradykinesiaResult.tapInterMean, \BradykinesiaResult.tapInterMedian, \BradykinesiaResult.tapInterP25, \BradykinesiaResult.tapInterP75, \BradykinesiaResult.tapInterStdev), result: result)
            result.tapInterSkew = value(tapInterSkew)

            apply(driftLeftStats, to: (\BradykinesiaResult.driftLeftMin, \BradykinesiaResult.driftLeftMax, \BradykinesiaResult.driftLeftMean, \BradykinesiaResult.driftLeftMedian, \BradykinesiaResult.driftLeftP25, \BradykinesiaResult.driftLeftP75, \BradykinesiaResult.driftLeftStdev), result: result)
            result.driftLeftSkew = value(driftLeftSkew)

            apply(driftRightStats, to: (\BradykinesiaResult.driftRightMin, \BradykinesiaResult.driftRightMax, \BradykinesiaResult.driftRightMean, \BradykinesiaResult.driftRightMedian, \BradykinesiaResult.driftRightP25, \BradykinesiaResult.driftRightP75, \BradykinesiaResult.driftRightStdev), result: result)
            result.driftRightSkew = value(driftRightSkew)
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
                    stats.iqr
                  ].allSatisfy(\.isFinite) else {
                return nil
            }
            return stats
        }
    }
}
