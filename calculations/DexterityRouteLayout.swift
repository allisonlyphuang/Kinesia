import Foundation

/// Local render-space geometry derived solely from the saved canonical route transform.
nonisolated struct DexterityRouteLayout: Equatable {
    let localRoutePoints: [DexterityRoutePoint]
    let localTargetRadius: Double
    let captureWidth: Double
    let captureHeight: Double

    init?(configuration: DexterityTestConfiguration) {
        guard configuration.invalidReason == nil else {
            return nil
        }

        let localRoutePoints = configuration.route.points.compactMap {
            configuration.coordinateSpace.localPoint(from: $0)
        }
        let localTargetRadius = configuration.targetRadius * configuration.coordinateSpace.scale

        guard localRoutePoints.count == configuration.route.points.count,
              localTargetRadius.isFinite,
              localTargetRadius > 0 else {
            return nil
        }

        self.localRoutePoints = localRoutePoints
        self.localTargetRadius = localTargetRadius
        self.captureWidth = configuration.coordinateSpace.captureWidth
        self.captureHeight = configuration.coordinateSpace.captureHeight
    }
}
