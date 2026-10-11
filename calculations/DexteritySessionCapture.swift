import Foundation

/// Full raw history for one Dexterity protocol-v1 session. Scored analysis uses only the indexed completed attempts.
nonisolated struct DexteritySessionCapture: Codable, Equatable {
    var protocolIdentifier: String
    var protocolVersion: Int
    var route: DexterityRoute
    var coordinateSpace: DexterityCoordinateSpace
    var targetRadius: Double
    var hand: String
    var digit: String
    var practiceAttempts: [DexteritySequence]
    var scoredAttempts: [DexteritySequence]
    var completedScoredAttemptIndexes: [Int]
    var startedAt: TimeInterval

    init(
        protocolIdentifier: String = DexterityProtocolV1.identifier,
        protocolVersion: Int = DexterityProtocolV1.version,
        route: DexterityRoute,
        coordinateSpace: DexterityCoordinateSpace,
        targetRadius: Double,
        hand: String = DexterityProtocolV1.hand,
        digit: String = DexterityProtocolV1.digit,
        practiceAttempts: [DexteritySequence],
        scoredAttempts: [DexteritySequence],
        completedScoredAttemptIndexes: [Int],
        startedAt: TimeInterval
    ) {
        self.protocolIdentifier = protocolIdentifier
        self.protocolVersion = protocolVersion
        self.route = route
        self.coordinateSpace = coordinateSpace
        self.targetRadius = targetRadius
        self.hand = hand
        self.digit = digit
        self.practiceAttempts = practiceAttempts
        self.scoredAttempts = scoredAttempts
        self.completedScoredAttemptIndexes = completedScoredAttemptIndexes
        self.startedAt = startedAt
    }

    var completedScoredSequences: [DexteritySequence]? {
        guard completedScoredAttemptIndexes.count == Set(completedScoredAttemptIndexes).count,
              completedScoredAttemptIndexes.allSatisfy({ scoredAttempts.indices.contains($0) }) else {
            return nil
        }

        let sequences = completedScoredAttemptIndexes.map { scoredAttempts[$0] }
        return sequences.allSatisfy(\.completed) ? sequences : nil
    }
}
