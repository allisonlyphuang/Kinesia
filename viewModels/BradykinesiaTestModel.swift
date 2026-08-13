//
//  BradykinesiaTestModel.swift
//  Kinesia
//
//  Created by Allison Huang on 8/13/26.
//

final class BradykinesiaTestModel: ObservableObject {
    enum Phase {
        case ready
        case countdown
        case running
        case finished
    }
    
    // @Published = redraw the UI whenever this changes
    @Published var phase: Phase
    @Published var secondsRemaining: Int
    // taps should not be @Published; would introduce noise into the timing
    private var taps: [TapSample]
    func recordTap(_sample: TapSample){
        
    }
    func beginCountdown() {
        
    }
    func finish() -> TapTrial? {
        
    }
}

