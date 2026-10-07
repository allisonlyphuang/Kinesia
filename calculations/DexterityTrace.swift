import Foundation

/// One captured trace sample in the local coordinate space of the Dexterity capture view.
nonisolated struct DexterityTracePoint: Codable, Equatable {
    var t: TimeInterval
    var x: Double
    var y: Double
    /// Zero-based active route segment: `route.points[segmentIndex] → route.points[segmentIndex + 1]`.
    var segmentIndex: Int

    var hasFiniteCoordinates: Bool {
        x.isFinite && y.isFinite
    }
}

/// Raw interaction metadata for one continuous trace. Completion and lift status carry no QC meaning here.
nonisolated struct DexteritySequence: Codable, Equatable {
    var samples: [DexterityTracePoint]
    var completed: Bool
    var endedByLift: Bool
}

/// Raw Dexterity data. Wall-clock context belongs to the later persistence layer.
nonisolated struct DexterityTrial: Codable, Equatable {
    var route: DexterityRoute
    var coordinateSpace: DexterityCoordinateSpace
    var sequences: [DexteritySequence]
    var startedAt: TimeInterval
}
