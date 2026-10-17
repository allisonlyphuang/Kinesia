nonisolated struct AkinesiaMetrics: Codable {
    static let metricsVersion = 1
    
    var numRounds: Int
    var numPracticeRounds: Int
    var numValidRounds: Int
    var numAnticipations: Int
    var numFalseStarts: Int
    var numLapses: Int
    var numMissed: Int
    var numSlips: Int
    var numMalformed: Int
    var reactionTimes: [Double]?
    var reactionTimeStats: SummaryStats?
    var movementTimes: [Double]?
    var movementTimeStats: SummaryStats?
}
