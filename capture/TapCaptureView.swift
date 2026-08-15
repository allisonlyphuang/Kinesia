//
//  TapCaptureView.swift
//  Kinesia
//
//  Created by Amanda Hon on 8/13/26.
//

// Turns touches into TapSample

import SwiftUI
import UIKit

final class RawTouchView: UIView {
    var onTap: ((TapSample) -> Void)?

    private var leftCenter = TapPoint(x: 0, y: 0)
    private var rightCenter = TapPoint(x: 0, y: 0)
    private var targetRadius: Double = 0
    private var isCaptureActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    func configure(
        leftCenter: TapPoint,
        rightCenter: TapPoint,
        targetRadius: Double,
        isCaptureActive: Bool,
        onTap: @escaping (TapSample) -> Void
    ) {
        self.leftCenter = leftCenter
        self.rightCenter = rightCenter
        self.targetRadius = targetRadius
        self.isCaptureActive = isCaptureActive
        self.onTap = onTap
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isCaptureActive else {
            return
        }

        for touch in touches {
            let location = touch.location(in: self)
            let sample = TapSample(
                t: touch.timestamp,
                x: location.x,
                y: location.y,
                target: Self.classify(
                    point: location,
                    leftCenter: leftCenter,
                    rightCenter: rightCenter,
                    targetRadius: targetRadius
                )
            )
            onTap?(sample)
        }
    }

    /// UI hit classification is intentionally independent from the paper mean-X partition used by the analyzer.
    /// If target circles overlap, the nearest in-radius target wins deterministically.
    static func classify(
        point: CGPoint,
        leftCenter: TapPoint,
        rightCenter: TapPoint,
        targetRadius: Double
    ) -> TapTarget {
        guard targetRadius.isFinite, targetRadius >= 0,
              point.x.isFinite, point.y.isFinite,
              leftCenter.x.isFinite, leftCenter.y.isFinite,
              rightCenter.x.isFinite, rightCenter.y.isFinite else {
            return .miss
        }

        let leftDistance = distance(from: point, to: leftCenter)
        let rightDistance = distance(from: point, to: rightCenter)
        let leftHit = leftDistance <= targetRadius
        let rightHit = rightDistance <= targetRadius

        switch (leftHit, rightHit) {
        case (true, true):
            return leftDistance <= rightDistance ? .left : .right
        case (true, false):
            return .left
        case (false, true):
            return .right
        case (false, false):
            return .miss
        }
    }

    private static func distance(from point: CGPoint, to center: TapPoint) -> Double {
        let deltaX = Double(point.x) - center.x
        let deltaY = Double(point.y) - center.y
        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}

struct TapCaptureView: UIViewRepresentable {
    var leftCenter: TapPoint
    var rightCenter: TapPoint
    var targetRadius: Double
    var isCaptureActive: Bool
    var onTap: (TapSample) -> Void

    func makeUIView(context: Context) -> RawTouchView {
        let view = RawTouchView(frame: .zero)
        view.configure(
            leftCenter: leftCenter,
            rightCenter: rightCenter,
            targetRadius: targetRadius,
            isCaptureActive: isCaptureActive,
            onTap: onTap
        )
        return view
    }

    func updateUIView(_ view: RawTouchView, context: Context) {
        view.configure(
            leftCenter: leftCenter,
            rightCenter: rightCenter,
            targetRadius: targetRadius,
            isCaptureActive: isCaptureActive,
            onTap: onTap
        )
    }
}
