//
//  BradykinesiaMetrics.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

struct BradykinesiaMetrics: Codable {
    var tapInter: Double
    var driftLeft: Double
    var driftRight: Double
    var tapInterSkew: Double
    var driftLeftSkew: Double
    var driftRightSkew: Double
    var corXY: Double
    var numTaps: Double
    var numCorrectTaps: Double
    // calculated properties
    var cvTapInter: Double {
        tapInter.stdev / tapInter.mean
    }
    
}
