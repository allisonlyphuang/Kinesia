//
//  BradykinesiaAnalyzer.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import Foundation

enum BradykinesiaAnalyzer {
    /// Computes the temporal subset of Bradykinesia metrics without reordering or filtering taps.
    static func analyze(_ trial: TapTrial) -> BradykinesiaMetrics {
        let intervals = tapIntervals(from: trial.samples)

        return BradykinesiaMetrics(
            numTaps: trial.samples.count,
            tapIntervals: intervals,
            tapInterStats: intervals.flatMap(SummaryStats.compute),
            cvTapInter: intervals.flatMap(SummaryStats.paperCoefficientOfVariation),
            skewTapInter: intervals.flatMap(SummaryStats.paperPopulationSkewness),
            numCorrectTaps: nil
        )
    }

    /// Returns nil when any timestamp is non-finite or not strictly increasing.
    /// Supplied sample order is preserved; samples are never sorted or discarded.
    static func tapIntervals(from samples: [TapSample]) -> [Double]? {
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
}
