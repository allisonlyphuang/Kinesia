import XCTest
@testable import Kinesia

final class DexterityRouteLayoutTests: XCTestCase {
    func testCanonicalRoutePointsMapToLocalRenderPoints() throws {
        let layout = try XCTUnwrap(
            DexterityRouteLayout(configuration: configuration(
                route: route(points: [.init(x: 5, y: 4), .init(x: 6, y: 4)]),
                coordinateSpace: .init(captureWidth: 100, captureHeight: 100, scale: 2, offsetX: 10, offsetY: 20),
                targetRadius: 1.5
            ))
        )

        XCTAssertEqual(layout.localRoutePoints, [.init(x: 20, y: 28), .init(x: 22, y: 28)])
    }

    func testTargetRadiusUsesUniformConfiguredScale() throws {
        let layout = try XCTUnwrap(
            DexterityRouteLayout(configuration: configuration(
                coordinateSpace: .init(captureWidth: 100, captureHeight: 100, scale: 4, offsetX: 0, offsetY: 0),
                targetRadius: 1.5
            ))
        )

        XCTAssertEqual(layout.localTargetRadius, 6, accuracy: 0.000_001)
    }

    func testNonzeroOffsetAppliesToEveryPointWithoutChangingOrder() throws {
        let canonicalRoute = route(points: [.init(x: 0, y: 0), .init(x: 3, y: 5), .init(x: -2, y: 4)])
        let layout = try XCTUnwrap(
            DexterityRouteLayout(configuration: configuration(
                route: canonicalRoute,
                coordinateSpace: .init(captureWidth: 100, captureHeight: 100, scale: 2, offsetX: 10, offsetY: -4)
            ))
        )

        XCTAssertEqual(layout.localRoutePoints, [.init(x: 10, y: -4), .init(x: 16, y: 6), .init(x: 6, y: 4)])
        XCTAssertEqual(canonicalRoute.points, [.init(x: 0, y: 0), .init(x: 3, y: 5), .init(x: -2, y: 4)])
    }

    func testLayoutRejectsConfigurationThatCannotRenderSafely() {
        let invalid = configuration(
            coordinateSpace: .init(captureWidth: 100, captureHeight: 100, scale: 0, offsetX: 0, offsetY: 0)
        )

        XCTAssertNil(DexterityRouteLayout(configuration: invalid))
    }

    private func configuration(
        route: DexterityRoute? = nil,
        coordinateSpace: DexterityCoordinateSpace = .init(captureWidth: 100, captureHeight: 100, scale: 1, offsetX: 0, offsetY: 0),
        targetRadius: Double = 1
    ) -> DexterityTestConfiguration {
        DexterityTestConfiguration(route: route ?? self.route(), coordinateSpace: coordinateSpace, targetRadius: targetRadius)
    }

    private func route(points: [DexterityRoutePoint] = [.init(x: 0, y: 0), .init(x: 10, y: 0)]) -> DexterityRoute {
        DexterityRoute(identifier: "layout-test", version: 1, points: points)
    }
}
