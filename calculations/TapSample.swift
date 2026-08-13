//
//  Bradykinesia.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

// codable allows json encoding, which is important in r

// target options
enum TapTarget: Codable {
    case left
    case right
    case miss
}

// for each tap, collect the following:
struct TapSample: Codable {
    var t: TimeInterval // raw UITouch.timestamp
    var x: Double
    var y: Double
    var target: TapTarget
    
}

// complete record of one 20-second attempt
struct TapTrial: Codable {
    var samples: [TapSample]
    var leftCenter:
    var rightCenter:
    var targetRadius:
    var startedAt:
    var hand:
    var screenScale:
}
