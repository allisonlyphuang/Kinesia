import Foundation

nonisolated struct DexterityMetrics: Codable {
    var numSequences: Int
    var doneSequences: Int
    var liftCount: Int

    /// Root mean square point-to-active-segment error in canonical route coordinates.
    var rmsError: Double?
    /// Computed only. Its relationship to the schema's `rmsErrorMax` remains unresolved.
    var maxPointError: Double?

    /// Summary statistics for canonical-route-unit-per-second samples.
    var swipeSpeedStats: SummaryStats?
    /// Sample-SD coefficient of variation, computed in memory only.
    var cvSwipeSpeed: Double?

    /// A deterministic description of malformed path-analysis input, distinct from insufficient data.
    var pathInvalidReason: String?
    /// A deterministic description of malformed temporal/speed-analysis input, distinct from insufficient data.
    var speedInvalidReason: String?

    var calculationInvalidReason: String? {
        let reasons = [pathInvalidReason, speedInvalidReason].compactMap { $0 }
        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }
}
