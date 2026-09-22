//
//  AkinesiaRoundRecord.swift
//  Kinesia
//
//  Created by Allison Huang on 9/19/26.
//

import Foundation

// mirrors TapSample.swift



nonisolated enum CaptureOutcome: String, Codable { case completed, falseStart, slip, missed }
/// The analyzer's verdict for one scored round. `malformed` means the round claimed to be
/// completed but its timestamps could not produce a usable reaction time; it is kept separate
/// from `missed` so a data problem is never read as a patient failing to initiate.
nonisolated enum ScoredOutcome: String, Codable { case valid, anticipation, lapse, falseStart, slip, missed, malformed }

nonisolated struct SpawnPoint: Codable { var x: Double; var y: Double}

nonisolated struct RoundRecord: Codable {
    var index: Int // 0-based round index
    var isPractice: Bool
    var homeSettledAt: TimeInterval // monotonic, thumb stable on home base?
    var plannedForeperiod: TimeInterval // what RNG draws
    var cueOnsetAt: TimeInterval? // monotonic, frame the firefly displayed, nil if false start
    var liftOffAt: TimeInterval? // monotonic, UITouch.timestamp
    var catchAt: TimeInterval? // monotonic, UITouch.timestamp
    var returnedHomeAt: TimeInterval? // monotonic, start of next foreperiod
    var spawn: SpawnPoint?
    var captureOutcome: CaptureOutcome
    var scoredOutcome: ScoredOutcome
    
}

nonisolated struct AkinesiaTrial: Codable { // one trial per session, mirror taptrial structure
    
    var rounds: [RoundRecord]
    var homeBaseCenter: SpawnPoint
    var homeBaseRadius: Double
    var fireflyRadius: Double
    var hand: CurrentHand
    var digit: String
    var screenScale: Double
    var refreshRateHz: Double
    var cueModality: String //"visual" for now
    var startedAt: TimeInterval // monotonic
    var spawnRing:  SpawnRing

}

nonisolated struct SpawnRing: Codable {
    var center: TapPoint // home base
    var radius: Double // nominal distance D, in points
    var tolerance: Double
    var arcStart: Double
    var arcEnd: Double
}


