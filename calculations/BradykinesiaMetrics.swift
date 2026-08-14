//
//  BradykinesiaMetrics.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

struct BradykinesiaMetrics: Codable {
    /// Number of raw taps captured, including left, right, and miss classifications.
    var numTaps: Int

    /// `nil` when timestamps are invalid; otherwise preserves the ordered interval sequence.
    var tapIntervals: [Double]?
    /// `nil` when fewer than two valid intervals are available.
    var tapInterStats: SummaryStats?
    /// Paper-defined population CV for tap intervals, expressed as a percentage.
    var cvTapInter: Double?
    /// Paper-defined population-moment skewness for tap intervals.
    var skewTapInter: Double?

    /// TODO: Define whether this counts target hits or correctly alternating target hits.
    var numCorrectTaps: Int?
}
