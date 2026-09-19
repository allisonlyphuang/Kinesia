//
//  SummaryStats.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import Foundation

struct SummaryStats: Codable {
    var min: Double
    var max: Double
    var mean: Double
    var median: Double
    var p25: Double
    var p75: Double
    /// Sample standard deviation, using a denominator of N - 1.
    var stdev: Double
    var range: Double
    var iqr: Double

    nonisolated static func compute(_ values: [Double]) -> SummaryStats? {
        guard values.count >= 2, values.allSatisfy(\.isFinite) else {
            return nil
        }

        let sorted = values.sorted()
        let count = values.count
        let min = sorted[0]
        let max = sorted[count - 1]
        let mean = values.reduce(0, +) / Double(count)

        let median: Double
        if count.isMultiple(of: 2) {
            median = (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            median = sorted[count / 2]
        }

        // Linear interpolation at fraction * (N - 1).
        let p25 = percentile(sorted: sorted, fraction: 0.25)
        let p75 = percentile(sorted: sorted, fraction: 0.75)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(count - 1)
        let stdev = sqrt(variance)

        let result = SummaryStats(
            min: min,
            max: max,
            mean: mean,
            median: median,
            p25: p25,
            p75: p75,
            stdev: stdev,
            range: max - min,
            iqr: p75 - p25
        )

        let allValuesAreFinite = [
            result.min,
            result.max,
            result.mean,
            result.median,
            result.p25,
            result.p75,
            result.stdev,
            result.range,
            result.iqr
        ].allSatisfy(\.isFinite)
        return allValuesAreFinite ? result : nil
    }

    /// Population standard deviation, using a denominator of N.
    nonisolated static func populationStandardDeviation(_ values: [Double]) -> Double? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
            return nil
        }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        let result = sqrt(variance)

        return result.isFinite ? result : nil
    }

    /// Paper-defined coefficient of variation: (population SD / mean) * 100.
    nonisolated static func paperCoefficientOfVariation(_ values: [Double]) -> Double? {
        guard values.count >= 2, values.allSatisfy(\.isFinite) else {
            return nil
        }

        let mean = values.reduce(0, +) / Double(values.count)
        guard mean != 0, let populationStdev = populationStandardDeviation(values) else {
            return nil
        }

        let result = (populationStdev / mean) * 100
        return result.isFinite ? result : nil
    }

    /// Paper-defined population-moment skewness.
    nonisolated static func paperPopulationSkewness(_ values: [Double]) -> Double? {
        guard values.count >= 2,
              values.allSatisfy(\.isFinite),
              let populationStdev = populationStandardDeviation(values),
              populationStdev > 0 else {
            return nil
        }

        let mean = values.reduce(0, +) / Double(values.count)
        let thirdCentralMoment = values.reduce(0) { partial, value in
            partial + pow(value - mean, 3)
        } / Double(values.count)
        let result = thirdCentralMoment / pow(populationStdev, 3)

        return result.isFinite ? result : nil
    }

    nonisolated private static func percentile(sorted: [Double], fraction: Double) -> Double {
        let index = fraction * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let weight = index - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
