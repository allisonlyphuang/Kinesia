import XCTest
@testable import Kinesia

final class DexterityRouteFitTests: XCTestCase {
    func testUsesOneUniformScaleAndPreservesAspectRatio() throws {
        let route = makeRoute(points: [.init(x: 0, y: 0), .init(x: 100, y: 50)])
        let space = try XCTUnwrap(DexterityRouteFit.coordinateSpace(
            for: route,
            captureWidth: 300,
            captureHeight: 300,
            padding: 20
        ))

        XCTAssertEqual(space.scale, 2.6, accuracy: 0.000_001)
        let start = try XCTUnwrap(space.localPoint(from: route.points[0]))
        let end = try XCTUnwrap(space.localPoint(from: route.points[1]))
        XCTAssertEqual(end.x - start.x, 260, accuracy: 0.000_001)
        XCTAssertEqual(end.y - start.y, 130, accuracy: 0.000_001)
    }

    func testFittedRouteRespectsRequestedPadding() throws {
        let route = makeRoute(points: [.init(x: 0, y: 0), .init(x: 100, y: 50)])
        let space = try XCTUnwrap(DexterityRouteFit.coordinateSpace(
            for: route,
            captureWidth: 300,
            captureHeight: 300,
            padding: 20
        ))
        let localPoints = try route.points.map { try XCTUnwrap(space.localPoint(from: $0)) }

        XCTAssertGreaterThanOrEqual(localPoints.map(\.x).min() ?? 0, 20)
        XCTAssertLessThanOrEqual(localPoints.map(\.x).max() ?? .infinity, 280)
        XCTAssertGreaterThanOrEqual(localPoints.map(\.y).min() ?? 0, 20)
        XCTAssertLessThanOrEqual(localPoints.map(\.y).max() ?? .infinity, 280)
    }

    func testFittedRouteIsCenteredInCaptureFrame() throws {
        let route = makeRoute(points: [.init(x: 0, y: 0), .init(x: 100, y: 50)])
        let space = try XCTUnwrap(DexterityRouteFit.coordinateSpace(
            for: route,
            captureWidth: 300,
            captureHeight: 300,
            padding: 20
        ))
        let points = try route.points.map { try XCTUnwrap(space.localPoint(from: $0)) }
        let centerX = ((points.map(\.x).min() ?? 0) + (points.map(\.x).max() ?? 0)) / 2
        let centerY = ((points.map(\.y).min() ?? 0) + (points.map(\.y).max() ?? 0)) / 2

        XCTAssertEqual(centerX, 150, accuracy: 0.000_001)
        XCTAssertEqual(centerY, 150, accuracy: 0.000_001)
    }

    func testInverseTransformReproducesCanonicalPoints() throws {
        let route = makeRoute(points: [.init(x: 15, y: 80), .init(x: 20, y: 20), .init(x: 85, y: 80)])
        let space = try XCTUnwrap(DexterityRouteFit.coordinateSpace(
            for: route,
            captureWidth: 320,
            captureHeight: 400,
            padding: 40
        ))

        for canonical in route.points {
            let local = try XCTUnwrap(space.localPoint(from: canonical))
            let restored = try XCTUnwrap(space.canonicalPoint(localX: local.x, localY: local.y))
            XCTAssertEqual(restored.x, canonical.x, accuracy: 0.000_001)
            XCTAssertEqual(restored.y, canonical.y, accuracy: 0.000_001)
        }
    }

    func testInvalidFrameDimensionsReturnNil() {
        XCTAssertNil(DexterityRouteFit.coordinateSpace(
            for: makeRoute(),
            captureWidth: 0,
            captureHeight: 400,
            padding: 40
        ))
    }

    private func makeRoute(points: [DexterityRoutePoint] = [.init(x: 0, y: 0), .init(x: 100, y: 50)]) -> DexterityRoute {
        DexterityRoute(identifier: "fit-test", version: 1, points: points)
    }
}
