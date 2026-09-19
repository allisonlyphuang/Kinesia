//
//  BradykinesiaMetrics.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

nonisolated struct BradykinesiaMetrics: Codable {
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

    /// `nil` when any raw coordinate is invalid; otherwise preserves the paper-derived left drift sequence.
    var leftDrift: [Double]?
    /// `nil` when any raw coordinate is invalid; otherwise preserves the paper-derived right drift sequence.
    var rightDrift: [Double]?
    /// Descriptive statistics for paper-derived left drift, when at least two drift values exist.
    var driftLeftStats: SummaryStats?
    /// Descriptive statistics for paper-derived right drift, when at least two drift values exist.
    var driftRightStats: SummaryStats?
    /// Paper-defined population CV for paper-derived left drift, expressed as a percentage.
    var cvDriftLeft: Double?
    /// Paper-defined population CV for paper-derived right drift, expressed as a percentage.
    var cvDriftRight: Double?
    /// Paper-defined population-moment skewness for paper-derived left drift.
    var skewDriftLeft: Double?
    /// Paper-defined population-moment skewness for paper-derived right drift.
    var skewDriftRight: Double?
    /// Pearson correlation across all raw finite x/y coordinate pairs.
    var corXY: Double?
    /// Taps that land inside the target the protocol expects next. The sequence opens on the
    /// right and alternates. Misses and wrong-target hits are not counted and do not advance
    /// the expected target. Always computable, so never `nil`.
    var numCorrectTaps: Int
}
