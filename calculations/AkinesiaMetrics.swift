//
//  AkinesiaMetrics.swift
//  Kinesia
//
//  Created by Allison Huang on 9/20/26.
//

nonisolated struct AkinesiaMetrics: Codable {
    static let metricsVersion = 1
    
    /// Scored rounds attempted. Practice rounds are not included.
    var numRounds: Int
    /// Practice rounds seen. Counted, never scored.
    var numPracticeRounds: Int
    var numValidRounds: Int
    var numAnticipations: Int
    var numFalseStarts: Int
    var numLapses: Int
    var numMissed: Int
    var numSlips: Int
    /// Rounds the capture layer called completed whose timestamps were unusable.
    /// Deliberately separate from `numMissed`: this is a data fault, not a motor one.
    var numMalformed: Int
    
    /// Reaction times of rounds scored `.valid`, in round order. Always non-nil;
    /// empty when no round scored valid.
    var reactionTimes: [Double]?
    var reactionTimeStats: SummaryStats?
    
    /// Lift-off to catch, for rounds scored `.valid` that also have a usable catch
    /// timestamp, so this can be shorter than `reactionTimes`. A bradykinesia measure:
    /// stored beside the reaction times, never averaged into them.
    var movementTimes: [Double]?
    var movementTimeStats: SummaryStats?
}
