import Foundation

nonisolated struct DexterityRoutePoint: Codable, Equatable {
    var x: Double
    var y: Double

    var hasFiniteCoordinates: Bool {
        x.isFinite && y.isFinite
    }
}

nonisolated struct DexterityRoute: Codable, Equatable {
    var identifier: String
    var version: Int
    var points: [DexterityRoutePoint]
}

/// The uniform transform used to draw canonical route coordinates in the local capture view.
nonisolated struct DexterityCoordinateSpace: Codable, Equatable {
    var captureWidth: Double
    var captureHeight: Double
    var scale: Double
    var offsetX: Double
    var offsetY: Double

    var isCalculationValid: Bool {
        [captureWidth, captureHeight, scale, offsetX, offsetY].allSatisfy(\.isFinite)
            && captureWidth > 0
            && captureHeight > 0
            && scale > 0
    }

    func localPoint(from canonical: DexterityRoutePoint) -> DexterityRoutePoint? {
        guard isCalculationValid, canonical.hasFiniteCoordinates else {
            return nil
        }

        let point = DexterityRoutePoint(
            x: canonical.x * scale + offsetX,
            y: canonical.y * scale + offsetY
        )
        return point.hasFiniteCoordinates ? point : nil
    }

    func canonicalPoint(localX: Double, localY: Double) -> DexterityRoutePoint? {
        guard isCalculationValid, localX.isFinite, localY.isFinite else {
            return nil
        }

        let point = DexterityRoutePoint(
            x: (localX - offsetX) / scale,
            y: (localY - offsetY) / scale
        )
        return point.hasFiniteCoordinates ? point : nil
    }
}
