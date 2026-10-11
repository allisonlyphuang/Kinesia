//
//  TapSample.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import Foundation

nonisolated enum CurrentHand: String, Codable, CaseIterable {
    case left
    case right
}

nonisolated enum TapTarget: Codable, Equatable {
    case left
    case right
    case miss
}

nonisolated struct TapSample: Codable {
    /// Raw `UITouch.timestamp` captured at touch-down.
    var t: TimeInterval
    var x: Double
    var y: Double
    var target: TapTarget
}

/// A Codable target center stored in the same coordinate space as `TapSample`.
nonisolated struct TapPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

/// Complete record of one intended 20-second tapping attempt.
nonisolated struct TapTrial: Codable {
    var samples: [TapSample]
    var leftCenter: TapPoint
    var rightCenter: TapPoint
    var targetRadius: Double
    var startedAt: TimeInterval
    var hand: CurrentHand
    var screenScale: Double
}
