//
//  SummaryStats.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import Foundation

struct SummaryStats {
    var min: Double
    var max: Double
    var mean: Double
    var median: Double
    var p25: Double
    var p75: Double
    var stdev: Double
    var range: Double
    var iqr: Double

    static func compute(_ values: [Double]) -> SummaryStats? {
        // ? allows for returning nil if samples < 2
        guard values.count >= 2 else { return nil }

        // make a sorted copy of the input
        let sorted = values.sorted()
        let n = values.count

        // Min and max
        let min = sorted.first!
        let max = sorted.last!

        // Mean: sum all values, divide by count
        let mean = values.reduce(0, +) / Double(n)

        // Median: middle value, or average of two middle values if even count
        let median: Double
        if n % 2 == 1 {
            median = sorted[n / 2]
        } else {
            median = (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        }

        // Quartiles using linear interpolation
        let p25 = percentile(sorted: sorted, fraction: 0.25)
        let p75 = percentile(sorted: sorted, fraction: 0.75)

        // Sample standard deviation: sqrt of average squared deviation (divide by n-1)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(n - 1)
        let stdev = Foundation.sqrt(variance)

        return SummaryStats(
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
    }

    // Returns the value at a given fraction (0.0–1.0) through a sorted array,
    // interpolating between neighbours when the index falls between two values.
    private static func percentile(sorted: [Double], fraction: Double) -> Double {
        let index = fraction * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = min(lower + 1, sorted.count - 1)
        let weight = index - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}
