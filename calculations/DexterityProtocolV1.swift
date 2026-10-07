import Foundation

/// Kinesia's fixed Dexterity MVP protocol. These are product interaction decisions, not clinical cutoffs or validation claims.
nonisolated enum DexterityProtocolV1 {
    static let identifier = "kinesia-dexterity-v1"
    static let version = 1
    static let route = DexterityRoute(
        identifier: "constellation-v1",
        version: 1,
        points: [
            .init(x: 15, y: 80),
            .init(x: 20, y: 20),
            .init(x: 50, y: 45),
            .init(x: 80, y: 20),
            .init(x: 85, y: 80)
        ]
    )
    static let targetRadius = 8.0
    static let practiceCompletionsRequired = 1
    static let scoredCompletionsRequired = 3
    static let hand = "right"
    static let digit = "index"

    static func configuration(
        captureWidth: Double,
        captureHeight: Double,
        padding: Double
    ) -> DexterityTestConfiguration? {
        guard let coordinateSpace = DexterityRouteFit.coordinateSpace(
            for: route,
            captureWidth: captureWidth,
            captureHeight: captureHeight,
            padding: padding
        ) else {
            return nil
        }

        return DexterityTestConfiguration(
            route: route,
            coordinateSpace: coordinateSpace,
            targetRadius: targetRadius
        )
    }
}
