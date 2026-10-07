// mathematical layout of the Akinesia board
// any tappable thing should be at least 44x44pt (Apple guidance and WCAG enhanced target size)

import CoreFoundation

struct AkinesiaBoardLayout: Equatable {
    
    // layout is immutable
    let boardSide: CGFloat
    let geometry: FireflyBoardGeometry
    let ring: SpawnRing
    
    // constants that can be tuned
    static let minimumBoardSide: CGFloat = 280
    static let minimumTouchTarget: CGFloat = 44
    private static let jarRadiusFraction = 0.11
    private static let fireflyRadiusFraction = 0.10
    private static let ringRadiusFraction = 0.34
    private static let ringTolerance: Double = 8 // the firefly can appear on the edge of a circle with radius r +- 8
    
    static func fit(in available: CGSize) -> AkinesiaBoardLayout {
        let side = max(minimumBoardSide, min(available.width, available.height) - 2 * Spacing.lg)
        let center = Double(side) / 2
        let jarRadius = max(28, Double(side) * jarRadiusFraction)
        let fireflyRadius = max(26, Double(side) * fireflyRadiusFraction)
        let ringRadius = Double(side) * ringRadiusFraction
        
        // the nearest possible spawn must not overlap with the jar
        assert(
            ringRadius - ringTolerance - fireflyRadius > jarRadius, "ring too tight for board side \(side)"
        )
        
        return AkinesiaBoardLayout(
            boardSide: side,
            geometry: FireflyBoardGeometry(
                center: TapPoint(x: center, y: center),
                homeBaseRadius: jarRadius,
                fireflyRadius: fireflyRadius
            ),
            ring: SpawnRing(
                center: TapPoint(x: center, y: center),
                radius: ringRadius,
                tolerance: ringTolerance,
                arcStart: 0,
                arcEnd: 2 * .pi // full circle
            )
        )
    }
}
