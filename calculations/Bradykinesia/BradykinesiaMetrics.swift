nonisolated struct BradykinesiaMetrics: Codable {
    
    // identifies formulas that produced these metrics
    static let metricsVersion = 1

    var numTaps: Int

    var tapIntervals: [Double]?
    var tapInterStats: SummaryStats?
    var cvTapInter: Double?
    var skewTapInter: Double?

    var leftDrift: [Double]?
    var rightDrift: [Double]?
    var driftLeftStats: SummaryStats?
    var driftRightStats: SummaryStats?
    var cvDriftLeft: Double?
    var cvDriftRight: Double?
    var skewDriftLeft: Double?
    var skewDriftRight: Double?
    var corXY: Double?
    var numCorrectTaps: Int

    var tapInterSlope: Double?
}
