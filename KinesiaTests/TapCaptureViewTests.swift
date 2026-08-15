import UIKit
import XCTest
@testable import Kinesia

@MainActor
final class TapCaptureViewTests: XCTestCase {
    private let leftCenter = TapPoint(x: 20, y: 40)
    private let rightCenter = TapPoint(x: 100, y: 40)
    private let radius = 20.0

    func testTargetClassificationUsesTargetGeometryIncludingBoundary() {
        XCTAssertTarget(
            RawTouchView.classify(
                point: CGPoint(x: 20, y: 40),
                leftCenter: leftCenter,
                rightCenter: rightCenter,
                targetRadius: radius
            ),
            is: .left
        )
        XCTAssertTarget(
            RawTouchView.classify(
                point: CGPoint(x: 100, y: 40),
                leftCenter: leftCenter,
                rightCenter: rightCenter,
                targetRadius: radius
            ),
            is: .right
        )
        XCTAssertTarget(
            RawTouchView.classify(
                point: CGPoint(x: 60, y: 100),
                leftCenter: leftCenter,
                rightCenter: rightCenter,
                targetRadius: radius
            ),
            is: .miss
        )
        XCTAssertTarget(
            RawTouchView.classify(
                point: CGPoint(x: 40, y: 40),
                leftCenter: leftCenter,
                rightCenter: rightCenter,
                targetRadius: radius
            ),
            is: .left
        )
    }

    private func XCTAssertTarget(
        _ actual: TapTarget,
        is expected: TapTarget,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.left, .left), (.right, .right), (.miss, .miss):
            break
        default:
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}
