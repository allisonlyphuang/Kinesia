import XCTest
@testable import Kinesia

/// Pure arithmetic: no simulator window, no Core Data, no main actor. This is the file that exists
/// because `BradykinesiaTestView` buried its geometry inside the view, where nothing could assert
/// that two targets never overlap on a small phone.
final class AkinesiaBoardLayoutTests: XCTestCase {

    /// Portrait sizes a board is realistically handed, after the screen's own padding.
    private let deviceSizes: [(String, CGSize)] = [
        ("iPhone SE", CGSize(width: 375, height: 500)),
        ("iPhone 17", CGSize(width: 393, height: 600)),
        ("iPhone Pro Max", CGSize(width: 430, height: 700)),
        ("iPad portrait", CGSize(width: 820, height: 1000)),
        ("tight, large type", CGSize(width: 375, height: 300))
    ]

    // MARK: - The invariant

    func testTheNearestSpawnAlwaysClearsTheJar() {
        // If this fails the two circles overlap, a touch in the overlap resolves in the firefly's
        // favour, and a resting finger scores a reaction time of about zero — plausible-looking
        // garbage. `AkinesiaTestConfiguration` also checks it, where it crashes instead.
        for (name, size) in deviceSizes {
            let layout = AkinesiaBoardLayout.fit(in: size)
            let nearestEdge = layout.ring.radius - layout.ring.tolerance - layout.geometry.fireflyRadius
            XCTAssertGreaterThan(
                nearestEdge,
                layout.geometry.homeBaseRadius,
                "\(name): nearest firefly edge \(nearestEdge) does not clear jar \(layout.geometry.homeBaseRadius)"
            )
        }
    }

    func testTheFurthestSpawnStaysOnTheBoard() {
        for (name, size) in deviceSizes {
            let layout = AkinesiaBoardLayout.fit(in: size)
            let furthestEdge = layout.ring.radius + layout.ring.tolerance + layout.geometry.fireflyRadius
            XCTAssertLessThanOrEqual(
                furthestEdge,
                Double(layout.boardSide) / 2,
                "\(name): a firefly would be clipped by the board edge"
            )
        }
    }

    // MARK: - Sizing

    func testTheBoardNeverExceedsTheSpaceItWasGiven() {
        for (name, size) in deviceSizes {
            let layout = AkinesiaBoardLayout.fit(in: size)
            guard layout.boardSide > AkinesiaBoardLayout.minimumBoardSide else { continue }
            XCTAssertLessThanOrEqual(layout.boardSide, min(size.width, size.height), name)
        }
    }

    func testTheSmallerDimensionDecidesTheSide() {
        // A wide, short rectangle must be governed by its height, or the board runs off the bottom.
        let wide = AkinesiaBoardLayout.fit(in: CGSize(width: 900, height: 420))
        XCTAssertLessThanOrEqual(wide.boardSide, 420)

        let tall = AkinesiaBoardLayout.fit(in: CGSize(width: 420, height: 900))
        XCTAssertEqual(wide.boardSide, tall.boardSide, "the same smaller dimension gives the same board")
    }

    func testATinySpaceClampsToTheMinimumRatherThanCollapsing() {
        let layout = AkinesiaBoardLayout.fit(in: CGSize(width: 50, height: 50))
        XCTAssertEqual(layout.boardSide, AkinesiaBoardLayout.minimumBoardSide)
        XCTAssertGreaterThan(layout.geometry.homeBaseRadius, 0)
    }

    func testAZeroSizeDoesNotProduceNonsense() {
        let layout = AkinesiaBoardLayout.fit(in: .zero)
        XCTAssertEqual(layout.boardSide, AkinesiaBoardLayout.minimumBoardSide)
        XCTAssertTrue(layout.geometry.homeBaseRadius.isFinite)
        XCTAssertTrue(layout.ring.radius.isFinite)
    }

    // MARK: - Touch targets

    func testBothCirclesStayAboveTheMinimumTouchTarget() {
        let minimum = Double(AkinesiaBoardLayout.minimumTouchTarget)
        for (name, size) in deviceSizes {
            let layout = AkinesiaBoardLayout.fit(in: size)
            XCTAssertGreaterThanOrEqual(layout.geometry.homeBaseRadius * 2, minimum, "\(name): jar")
            XCTAssertGreaterThanOrEqual(layout.geometry.fireflyRadius * 2, minimum, "\(name): firefly")
        }
    }

    // MARK: - Shape of the result

    func testTheJarSitsAtTheCentreOfTheBoard() {
        for (name, size) in deviceSizes {
            let layout = AkinesiaBoardLayout.fit(in: size)
            let centre = Double(layout.boardSide) / 2
            XCTAssertEqual(layout.geometry.center.x, centre, accuracy: 0.001, name)
            XCTAssertEqual(layout.geometry.center.y, centre, accuracy: 0.001, name)
            XCTAssertEqual(layout.ring.center, layout.geometry.center, "the ring is centred on the jar")
        }
    }

    func testTheRingCoversAFullCircle() {
        let layout = AkinesiaBoardLayout.fit(in: CGSize(width: 400, height: 600))
        XCTAssertEqual(layout.ring.arcEnd - layout.ring.arcStart, 2 * .pi, accuracy: 0.000_001)
    }

    func testFitIsDeterministic() {
        let size = CGSize(width: 393, height: 600)
        XCTAssertEqual(AkinesiaBoardLayout.fit(in: size), AkinesiaBoardLayout.fit(in: size))
    }

    // MARK: - Joined up with the spawn function

    func testEveryRingSpawnLandsInsideTheBoardAndClearOfTheJar() {
        // The layout and the spawn generator are written separately; this is the test that proves
        // they agree. Sweeping the random source covers both extremes of the tolerance band.
        for (name, size) in deviceSizes {
            let layout = AkinesiaBoardLayout.fit(in: size)
            let side = Double(layout.boardSide)

            for sample in stride(from: 0.0, through: 0.999, by: 0.05) {
                let point = AkinesiaTestModel.ringSpawn(in: layout.ring) { sample }
                let r = layout.geometry.fireflyRadius

                XCTAssertGreaterThanOrEqual(point.x - r, 0, "\(name) @\(sample): off the left edge")
                XCTAssertGreaterThanOrEqual(point.y - r, 0, "\(name) @\(sample): off the top edge")
                XCTAssertLessThanOrEqual(point.x + r, side, "\(name) @\(sample): off the right edge")
                XCTAssertLessThanOrEqual(point.y + r, side, "\(name) @\(sample): off the bottom edge")

                let distance = hypot(point.x - layout.geometry.center.x, point.y - layout.geometry.center.y)
                XCTAssertGreaterThan(
                    distance - r,
                    layout.geometry.homeBaseRadius,
                    "\(name) @\(sample): firefly overlaps the jar"
                )
            }
        }
    }
}
