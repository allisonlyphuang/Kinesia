//
//  TapCaptureView.swift
//  Kinesia
//
//  Created by Amanda Hon on 8/13/26.
//



// swiftUI's .onTapGesture does not provide a timestamp, so we need to record the time when the code runs (after gesture recognition) using UIKit (old version of SwiftUI)
// this adds noise
class RawTouchView : UIView {

    var onTap: ((TapSample) -> Void)?
    
    // dyskinesia patients might tap with 2 fingers
    init(isMultipleTouchEnabled: Bool) {
        self.isMultipleTouchEnabled = true
    }
    
    // use touchesBegan for timing only (not touchesEnded), contact duration is a separate measure
    override func touchesBegan(_touchesL Set<UITouch>, with event: UIEvent?)
    // for each touch, read touch.timestamp adn touch.location(in: self), classify against target centers, and get resulting TapSample
    // to hand off TapSample, give the class a stored closure property (onTap)
}




// TapCaptureView is constantly destroyed and recreated but RawTouchView object persists because it uses UIKit
struct TapCaptureView: UIViewRepresentable {
    // runs exactly once when the view first appears on the screen
    var leftCenter: CGPoint
    var rightCenter: CGPoint
    var radius: CGFloat
    var radius: (TapSample) -> void
    
    func makeUIView(context:) -> RawTouchView {
        // create a RawTouchView instance
        // enable multi-touch
        // assign onTap closure
        // return the view
    }
    
    // called every time swiftui re-renders the parent
    // should NOT clear recorded taps, reset timers/state, any setup logic that should run only once
    func updateUIView(_ view: RawTouchView, context: Context) {
        // update the onTap closure on the view
        // update target geometry
    }
}
