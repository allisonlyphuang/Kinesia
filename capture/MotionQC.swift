//
//  Untitled.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

import CoreMotion

class MotionQC {
    let motionManager = CMMotionManager()
    
    func start() {
        // use startDeviceMotionUpdates and read userAcceleration
        // accumulate the magnitude of distance/movement per sample
    }
    
    func stop() {
        
    }
    
    struct MotionQCResults {
        var meanG: Double
        var maxG: Double
        var moved: Bool
    }
}
