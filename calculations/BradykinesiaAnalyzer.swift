//
//  BradykinesiaAnalyzer.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import Foundation

enum BradykinesiaAnalyzer {
    /// Computes paper-derived temporal and spatial metrics without reordering or filtering taps.
    
    nonisolated static func analyze(_ trial: TapTrial) -> BradykinesiaMetrics {
        let intervals = tapIntervals(from: trial.samples)
        let spatial = spatialOutputs(from: trial.samples)
        let leftDrift = spatial?.leftDrift
        let rightDrift = spatial?.rightDrift

        return BradykinesiaMetrics(
            numTaps: trial.samples.count,
            tapIntervals: intervals,
            tapInterStats: intervals.flatMap(SummaryStats.compute),
            cvTapInter: intervals.flatMap(SummaryStats.paperCoefficientOfVariation),
            skewTapInter: intervals.flatMap(SummaryStats.paperPopulationSkewness),
            leftDrift: leftDrift,
            rightDrift: rightDrift,
            driftLeftStats: leftDrift.flatMap(SummaryStats.compute),
            driftRightStats: rightDrift.flatMap(SummaryStats.compute),
            cvDriftLeft: leftDrift.flatMap(SummaryStats.paperCoefficientOfVariation),
            cvDriftRight: rightDrift.flatMap(SummaryStats.paperCoefficientOfVariation),
            skewDriftLeft: leftDrift.flatMap(SummaryStats.paperPopulationSkewness),
            skewDriftRight: rightDrift.flatMap(SummaryStats.paperPopulationSkewness),
            corXY: spatial?.correlationXY,
            numCorrectTaps: correctTapCount(from: trial.samples)
        )
    }

    /// Returns nil when any timestamp is non-finite or not strictly increasing.
    /// Supplied sample order is preserved; samples are never sorted or discarded.
    nonisolated static func tapIntervals(from samples: [TapSample]) -> [Double]? {
        guard samples.allSatisfy({ $0.t.isFinite }) else {
            return nil
        }

        guard samples.count >= 2 else {
            return []
        }

        var intervals: [Double] = []
        intervals.reserveCapacity(samples.count - 1)

        for index in 1..<samples.count {
            let interval = samples[index].t - samples[index - 1].t
            guard interval.isFinite, interval > 0 else {
                return nil
            }
            intervals.append(interval)
        }

        return intervals
    }

    /// Paper-derived coordinate grouping: x values below the raw mean x are left; values at or above it are right.
    /// TapTarget is intentionally not used, so target hits and misses remain independent UI/QC metadata.
    nonisolated static func paperSpatialPartition(from samples: [TapSample]) -> PaperSpatialPartition? {
        guard !samples.isEmpty, samples.allSatisfy(hasFiniteCoordinates) else {
            return nil
        }

        let meanX = samples.reduce(0) { $0 + $1.x } / Double(samples.count)
        guard meanX.isFinite else {
            return nil
        }

        return PaperSpatialPartition(
            meanX: meanX,
            leftSamples: samples.filter { $0.x < meanX },
            rightSamples: samples.filter { $0.x >= meanX }
        )
    }

    /// Euclidean distance between two raw samples, unavailable for non-finite coordinates or a non-finite result.
    nonisolated static func euclideanDistance(from first: TapSample, to second: TapSample) -> Double? {
        guard hasFiniteCoordinates(first), hasFiniteCoordinates(second) else {
            return nil
        }

        let deltaX = second.x - first.x
        let deltaY = second.y - first.y
        let result = sqrt(deltaX * deltaX + deltaY * deltaY)
        return result.isFinite ? result : nil
    }

    /// Consecutive Euclidean distances in the supplied order, without sorting or dropping samples.
    nonisolated static func driftSequence(from samples: [TapSample]) -> [Double]? {
        guard samples.allSatisfy(hasFiniteCoordinates) else {
            return nil
        }

        guard samples.count >= 2 else {
            return []
        }

        var drift: [Double] = []
        drift.reserveCapacity(samples.count - 1)
        for index in 1..<samples.count {
            guard let distance = euclideanDistance(from: samples[index - 1], to: samples[index]) else {
                return nil
            }
            drift.append(distance)
        }
        return drift
    }

    /// Pearson correlation across all raw coordinate pairs, independent of paper partitions and TapTarget labels.
    nonisolated static func pearsonCorrelationXY(from samples: [TapSample]) -> Double? {
        guard samples.count >= 2, samples.allSatisfy(hasFiniteCoordinates) else {
            return nil
        }

        let count = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / count
        let meanY = samples.reduce(0) { $0 + $1.y } / count
        guard meanX.isFinite, meanY.isFinite else {
            return nil
        }

        let components = samples.reduce(into: (covariance: 0.0, xVariance: 0.0, yVariance: 0.0)) { partial, sample in
            let deltaX = sample.x - meanX
            let deltaY = sample.y - meanY
            partial.covariance += deltaX * deltaY
            partial.xVariance += deltaX * deltaX
            partial.yVariance += deltaY * deltaY
        }
        let denominator = sqrt(components.xVariance * components.yVariance)
        guard components.covariance.isFinite, denominator.isFinite, denominator > 0 else {
            return nil
        }

        let correlation = components.covariance / denominator
        guard correlation.isFinite else {
            return nil
        }

        let roundingTolerance = 1e-12
        if correlation > 1, correlation <= 1 + roundingTolerance {
            return 1
        }
        if correlation < -1, correlation >= -1 - roundingTolerance {
            return -1
        }
        return (-1...1).contains(correlation) ? correlation : nil
    }

    nonisolated private static func spatialOutputs(from samples: [TapSample]) -> SpatialOutputs? {
        guard samples.allSatisfy(hasFiniteCoordinates) else {
            return nil
        }

        guard let partition = paperSpatialPartition(from: samples) else {
            return SpatialOutputs(leftDrift: [], rightDrift: [], correlationXY: nil)
        }
        guard let leftDrift = driftSequence(from: partition.leftSamples),
              let rightDrift = driftSequence(from: partition.rightSamples) else {
            return nil
        }

        return SpatialOutputs(
            leftDrift: leftDrift,
            rightDrift: rightDrift,
            correlationXY: pearsonCorrelationXY(from: samples)
        )
    }

    nonisolated private static func hasFiniteCoordinates(_ sample: TapSample) -> Bool {
        sample.x.isFinite && sample.y.isFinite
    }
    
    
    // a correct sequence starts on the right and alternates right left right etc.
    // anything that is not the expected target is a miss and does not advance the expected target.
    // this is the only metric that reads `TapTarget`
    nonisolated static func correctTapCount(from samples: [TapSample]) -> Int {
        var count = 0
        var expected: TapTarget = .right

        for sample in samples {
            guard sample.target == expected else {
                continue
            }
            count += 1
            expected = (expected == .right) ? .left : .right
        }

        return count
    }

    private struct SpatialOutputs {
        let leftDrift: [Double]
        let rightDrift: [Double]
        let correlationXY: Double?
    }
}

struct PaperSpatialPartition {
    let meanX: Double
    let leftSamples: [TapSample]
    let rightSamples: [TapSample]
}
