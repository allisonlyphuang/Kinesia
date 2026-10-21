import Foundation

/// Derives a uniform canonical-to-local transform that fits a valid route within a local capture frame.
nonisolated enum DexterityRouteFit {
    static func coordinateSpace(
        for route: DexterityRoute,
        captureWidth: Double,
        captureHeight: Double,
        padding: Double
    ) -> DexterityCoordinateSpace? {
        guard DexterityAnalyzer.isCalculationValid(route: route),
              captureWidth.isFinite,
              captureHeight.isFinite,
              padding.isFinite,
              captureWidth > 0,
              captureHeight > 0,
              padding >= 0,
              captureWidth > padding * 2,
              captureHeight > padding * 2 else {
            return nil
        }

        let minX = route.points.map(\.x).min() ?? .nan
        let maxX = route.points.map(\.x).max() ?? .nan
        let minY = route.points.map(\.y).min() ?? .nan
        let maxY = route.points.map(\.y).max() ?? .nan
        let routeWidth = maxX - minX
        let routeHeight = maxY - minY

        guard [minX, maxX, minY, maxY, routeWidth, routeHeight].allSatisfy(\.isFinite),
              routeWidth >= 0,
              routeHeight >= 0 else {
            return nil
        }

        let availableWidth = captureWidth - padding * 2
        let availableHeight = captureHeight - padding * 2
        var scaleCandidates: [Double] = []
        if routeWidth > 0 {
            scaleCandidates.append(availableWidth / routeWidth)
        }
        if routeHeight > 0 {
            scaleCandidates.append(availableHeight / routeHeight)
        }

        guard let scale = scaleCandidates.min(), scale.isFinite, scale > 0 else {
            return nil
        }

        let offsetX = (captureWidth - routeWidth * scale) / 2 - minX * scale
        let offsetY = (captureHeight - routeHeight * scale) / 2 - minY * scale
        let coordinateSpace = DexterityCoordinateSpace(
            captureWidth: captureWidth,
            captureHeight: captureHeight,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
        return coordinateSpace.isCalculationValid ? coordinateSpace : nil
    }
}
