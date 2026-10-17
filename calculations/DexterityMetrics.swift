import Foundation

nonisolated struct DexterityMetrics: Codable {
    
    // identifies set of formulas that produced these metrics 
    static let metricsVersion = 1

    var numSequences: Int
    var doneSequences: Int
    var liftCount: Int

    /// Root mean square point-to-active-segment error in canonical route coordinates.
    var rmsError: Double?
    /// Computed only. This is distinct from persisted `rmsErrorMax`, which is maximum per-sequence RMSE.
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

/// Derived values whose persisted meanings are defined by the completed scored sequences only.
nonisolated struct DexterityScoredMetrics {
    var aggregate: DexterityMetrics
    var perSequenceRMSE: [Double]?
    var perSequencePathLengths: [Double]?

    var rmsErrorMax: Double? {
        perSequenceRMSE?.max()
    }

    var swipeDist: Double? {
        guard let perSequencePathLengths,
              !perSequencePathLengths.isEmpty,
              perSequencePathLengths.allSatisfy(\.isFinite) else {
            return nil
        }
        let result = perSequencePathLengths.reduce(0, +) / Double(perSequencePathLengths.count)
        return result.isFinite ? result : nil
    }
}
