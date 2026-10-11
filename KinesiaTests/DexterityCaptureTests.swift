import XCTest
@testable import Kinesia

@MainActor
final class DexterityCaptureTests: XCTestCase {
    func testInactiveCaptureDoesNotBeginATrace() {
        let state = DexterityTouchCaptureState()
        let touch = TouchToken()

        XCTAssertNil(state.begin(touchID: ObjectIdentifier(touch), sample: sample(t: 1, x: 2, y: 3)))
        XCTAssertFalse(state.isTrackingTouch)
    }

    func testActiveTraceForwardsBeganAndOrderedMovementSamplesUnchanged() {
        let state = activeState()
        let touch = TouchToken()
        let began = sample(t: 1.25, x: -2.5, y: 4.75)
        let movement = [sample(t: 1.3, x: -1, y: 5), sample(t: 1.4, x: 8.5, y: -9.25)]

        XCTAssertEqual(state.begin(touchID: ObjectIdentifier(touch), sample: began), .began(began))
        XCTAssertEqual(state.move(touchID: ObjectIdentifier(touch), samples: movement), .moved(movement))
        XCTAssertTrue(state.isTrackingTouch)
    }

    func testSecondTouchCannotReplaceTheActiveTrace() {
        let state = activeState()
        let firstTouch = TouchToken()
        let secondTouch = TouchToken()

        XCTAssertNotNil(state.begin(touchID: ObjectIdentifier(firstTouch), sample: sample(t: 1, x: 0, y: 0)))
        XCTAssertNil(state.begin(touchID: ObjectIdentifier(secondTouch), sample: sample(t: 1, x: 10, y: 10)))
        XCTAssertNil(state.move(touchID: ObjectIdentifier(secondTouch), samples: [sample(t: 2, x: 20, y: 20)]))
        XCTAssertEqual(
            state.move(touchID: ObjectIdentifier(firstTouch), samples: [sample(t: 2, x: 3, y: 4)]),
            .moved([sample(t: 2, x: 3, y: 4)])
        )
    }

    func testEndClearsActiveTouchAndAllowsANewTrace() {
        let state = activeState()
        let firstTouch = TouchToken()
        let secondTouch = TouchToken()

        XCTAssertNotNil(state.begin(touchID: ObjectIdentifier(firstTouch), sample: sample(t: 1, x: 0, y: 0)))
        XCTAssertEqual(
            state.end(touchID: ObjectIdentifier(firstTouch), sample: sample(t: 2, x: 1, y: 1)),
            .ended(sample(t: 2, x: 1, y: 1))
        )
        XCTAssertFalse(state.isTrackingTouch)
        XCTAssertNotNil(state.begin(touchID: ObjectIdentifier(secondTouch), sample: sample(t: 3, x: 2, y: 2)))
    }

    func testCancellationClearsActiveTouch() {
        let state = activeState()
        let touch = TouchToken()
        let cancelled = sample(t: 2, x: 1, y: 1)

        XCTAssertNotNil(state.begin(touchID: ObjectIdentifier(touch), sample: sample(t: 1, x: 0, y: 0)))
        XCTAssertEqual(state.cancel(touchID: ObjectIdentifier(touch), sample: cancelled), .cancelled(cancelled))
        XCTAssertFalse(state.isTrackingTouch)
        XCTAssertNil(state.move(touchID: ObjectIdentifier(touch), samples: [sample(t: 3, x: 2, y: 2)]))
    }

    func testDisablingClearsActiveTrackingAndReactivationStartsIndependently() {
        let state = activeState()
        let firstTouch = TouchToken()
        let secondTouch = TouchToken()

        XCTAssertNotNil(state.begin(touchID: ObjectIdentifier(firstTouch), sample: sample(t: 1, x: 0, y: 0)))
        state.configure(isCaptureActive: false)

        XCTAssertFalse(state.isTrackingTouch)
        XCTAssertNil(state.move(touchID: ObjectIdentifier(firstTouch), samples: [sample(t: 2, x: 1, y: 1)]))

        state.configure(isCaptureActive: true)
        XCTAssertEqual(
            state.begin(touchID: ObjectIdentifier(secondTouch), sample: sample(t: 3, x: 4, y: 5)),
            .began(sample(t: 3, x: 4, y: 5))
        )
    }

    private func activeState() -> DexterityTouchCaptureState {
        let state = DexterityTouchCaptureState()
        state.configure(isCaptureActive: true)
        return state
    }

    private func sample(t: TimeInterval, x: Double, y: Double) -> DexterityTouchSample {
        DexterityTouchSample(t: t, x: x, y: y)
    }
}

private final class TouchToken {}
