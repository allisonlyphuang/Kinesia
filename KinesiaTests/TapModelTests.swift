import XCTest
@testable import Kinesia

@MainActor
final class TapModelTests: XCTestCase {
    func testTapTrialCodableRoundTripPreservesRawCaptureData() throws {
        let trial = TapTrial(
            samples: [
                TapSample(t: 10.25, x: 12.5, y: 30.75, target: .left),
                TapSample(t: 10.75, x: 90.25, y: 31.5, target: .right),
                TapSample(t: 11.25, x: 55, y: 80, target: .miss)
            ],
            leftCenter: TapPoint(x: 20, y: 40),
            rightCenter: TapPoint(x: 100, y: 40),
            targetRadius: 24,
            startedAt: 10,
            hand: "left",
            screenScale: 3
        )

        let decoded = try JSONDecoder().decode(TapTrial.self, from: JSONEncoder().encode(trial))

        XCTAssertEqual(decoded.samples.count, 3)
        XCTAssertEqual(decoded.samples.map(\.t), [10.25, 10.75, 11.25])
        XCTAssertEqual(decoded.samples.map(\.x), [12.5, 90.25, 55])
        XCTAssertEqual(decoded.samples.map(\.y), [30.75, 31.5, 80])
        assertTargets(decoded.samples.map(\.target))
        XCTAssertEqual(decoded.leftCenter.x, 20, accuracy: 0.000_001)
        XCTAssertEqual(decoded.leftCenter.y, 40, accuracy: 0.000_001)
        XCTAssertEqual(decoded.rightCenter.x, 100, accuracy: 0.000_001)
        XCTAssertEqual(decoded.rightCenter.y, 40, accuracy: 0.000_001)
        XCTAssertEqual(decoded.targetRadius, 24, accuracy: 0.000_001)
        XCTAssertEqual(decoded.startedAt, 10, accuracy: 0.000_001)
        XCTAssertEqual(decoded.hand, "left")
        XCTAssertEqual(decoded.screenScale, 3, accuracy: 0.000_001)
    }

    private func assertTargets(_ targets: [TapTarget], file: StaticString = #filePath, line: UInt = #line) {
        guard case [.left, .right, .miss] = targets else {
            XCTFail("Tap target classifications did not round-trip", file: file, line: line)
            return
        }
    }
}
