import SwiftUI
import UIKit

/// One raw sample from the local coordinate space of the Dexterity capture surface.
/// `t` comes from `UITouch.timestamp`, which is monotonic/process-relative rather than wall-clock time.
nonisolated struct DexterityTouchSample: Codable, Equatable {
    var t: TimeInterval
    var x: Double
    var y: Double
}

/// Raw continuous-touch lifecycle events. Route progress and segment ownership intentionally belong to a later model layer.
nonisolated enum DexterityTouchEvent: Equatable {
    case began(DexterityTouchSample)
    case moved([DexterityTouchSample])
    case ended(DexterityTouchSample)
    case cancelled(DexterityTouchSample?)
}

/// Small deterministic state holder used by the UIKit bridge.
/// It deliberately forwards raw samples without validating, transforming, or reordering them.
final class DexterityTouchCaptureState {
    private var activeTouchID: ObjectIdentifier?
    private var isCaptureActive = false

    var isTrackingTouch: Bool {
        activeTouchID != nil
    }

    func configure(isCaptureActive: Bool) {
        self.isCaptureActive = isCaptureActive
        if !isCaptureActive {
            activeTouchID = nil
        }
    }

    func begin(touchID: ObjectIdentifier, sample: DexterityTouchSample) -> DexterityTouchEvent? {
        guard isCaptureActive, activeTouchID == nil else {
            return nil
        }

        activeTouchID = touchID
        return .began(sample)
    }

    func move(touchID: ObjectIdentifier, samples: [DexterityTouchSample]) -> DexterityTouchEvent? {
        guard isCaptureActive, activeTouchID == touchID else {
            return nil
        }

        return .moved(samples)
    }

    func end(touchID: ObjectIdentifier, sample: DexterityTouchSample) -> DexterityTouchEvent? {
        guard activeTouchID == touchID else {
            return nil
        }

        activeTouchID = nil
        return .ended(sample)
    }

    func cancel(touchID: ObjectIdentifier, sample: DexterityTouchSample?) -> DexterityTouchEvent? {
        guard activeTouchID == touchID else {
            return nil
        }

        activeTouchID = nil
        return .cancelled(sample)
    }
}

final class RawDexterityTouchView: UIView {
    var onEvent: ((DexterityTouchEvent) -> Void)?

    private let captureState = DexterityTouchCaptureState()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    func configure(
        isCaptureActive: Bool,
        onEvent: @escaping (DexterityTouchEvent) -> Void
    ) {
        captureState.configure(isCaptureActive: isCaptureActive)
        self.onEvent = onEvent
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let captureEvent = captureState.begin(
                touchID: ObjectIdentifier(touch),
                sample: sample(for: touch)
            ) else {
                continue
            }
            onEvent?(captureEvent)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let primarySample = sample(for: touch)
            let coalescedSamples = event?.coalescedTouches(for: touch)?.map(sample(for:)) ?? []
            let samples = includes(primarySample, in: coalescedSamples) ? coalescedSamples : coalescedSamples + [primarySample]

            guard let captureEvent = captureState.move(
                touchID: ObjectIdentifier(touch),
                samples: samples
            ) else {
                continue
            }
            onEvent?(captureEvent)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let captureEvent = captureState.end(
                touchID: ObjectIdentifier(touch),
                sample: sample(for: touch)
            ) else {
                continue
            }
            onEvent?(captureEvent)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let captureEvent = captureState.cancel(
                touchID: ObjectIdentifier(touch),
                sample: sample(for: touch)
            ) else {
                continue
            }
            onEvent?(captureEvent)
        }
    }

    private func sample(for touch: UITouch) -> DexterityTouchSample {
        let location = touch.location(in: self)
        return DexterityTouchSample(t: touch.timestamp, x: location.x, y: location.y)
    }

    private func includes(_ sample: DexterityTouchSample, in samples: [DexterityTouchSample]) -> Bool {
        samples.contains { candidate in
            candidate.t == sample.t && candidate.x == sample.x && candidate.y == sample.y
        }
    }
}

struct DexterityCaptureView: UIViewRepresentable {
    var isCaptureActive: Bool
    var onEvent: (DexterityTouchEvent) -> Void

    func makeUIView(context: Context) -> RawDexterityTouchView {
        let view = RawDexterityTouchView(frame: .zero)
        view.configure(isCaptureActive: isCaptureActive, onEvent: onEvent)
        return view
    }

    func updateUIView(_ view: RawDexterityTouchView, context: Context) {
        view.configure(isCaptureActive: isCaptureActive, onEvent: onEvent)
    }
}
