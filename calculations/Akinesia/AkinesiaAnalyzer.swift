import Foundation

nonisolated enum AkinesiaAnalyzer {

    nonisolated struct ScoredRound: Equatable {
        var outcome: ScoredOutcome
        var reactionTime: Double?
        var movementTime: Double?
    }

    nonisolated static func analyze(
        _ trial: AkinesiaTrial,
        thresholds: AkinesiaThresholds = .default
    ) -> AkinesiaMetrics {
        var numPracticeRounds = 0
        var numRounds = 0
        var numValidRounds = 0
        var numAnticipations = 0
        var numFalseStarts = 0
        var numLapses = 0
        var numMissed = 0
        var numSlips = 0
        var numMalformed = 0
        var reactionTimes: [Double] = []
        var movementTimes: [Double] = []

        for round in trial.rounds {
            guard !round.isPractice else {
                numPracticeRounds += 1
                continue
            }

            numRounds += 1
            let scored = score(round, thresholds: thresholds)

            switch scored.outcome {
            case .valid: numValidRounds += 1
            case .anticipation: numAnticipations += 1
            case .falseStart: numFalseStarts += 1
            case .lapse: numLapses += 1
            case .missed: numMissed += 1
            case .slip: numSlips += 1
            case .malformed: numMalformed += 1
            }

            if let reactionTime = scored.reactionTime {
                reactionTimes.append(reactionTime)
            }
            if let movementTime = scored.movementTime {
                movementTimes.append(movementTime)
            }
        }

        // a session below the minimum still reports counts and raw interval, it just does not
        // produce summary statistics, which is what makes the store mark the result as invalid
        let meetsMinimum = numValidRounds >= thresholds.minimumValidRounds

        return AkinesiaMetrics(
            numRounds: numRounds,
            numPracticeRounds: numPracticeRounds,
            numValidRounds: numValidRounds,
            numAnticipations: numAnticipations,
            numFalseStarts: numFalseStarts,
            numLapses: numLapses,
            numMissed: numMissed,
            numSlips: numSlips,
            numMalformed: numMalformed,
            reactionTimes: reactionTimes,
            reactionTimeStats: meetsMinimum ? SummaryStats.compute(reactionTimes) : nil,
            movementTimes: movementTimes,
            movementTimeStats: meetsMinimum ? SummaryStats.compute(movementTimes) : nil
        )
    }

  
    nonisolated static func score(
        _ round: RoundRecord,
        thresholds: AkinesiaThresholds = .default
    ) -> ScoredRound {
        switch round.captureOutcome {
        case .falseStart:
            return ScoredRound(outcome: .falseStart, reactionTime: nil, movementTime: nil)
        case .slip:
            return ScoredRound(outcome: .slip, reactionTime: nil, movementTime: nil)
        case .missed:
            return ScoredRound(outcome: .missed, reactionTime: nil, movementTime: nil)
        case .completed:
            break
        }

        // A completed round without a usable cue-to-lift interval contradicts its own capture
        // outcome. That is a data fault, so it is kept out of `numMissed`.
        guard let reactionTime = rawReactionTime(of: round) else {
            return ScoredRound(outcome: .malformed, reactionTime: nil, movementTime: nil)
        }

        if reactionTime < thresholds.anticipationCeiling {
            return ScoredRound(outcome: .anticipation, reactionTime: nil, movementTime: nil)
        }
        if reactionTime > thresholds.lapseFloor {
            return ScoredRound(outcome: .lapse, reactionTime: nil, movementTime: nil)
        }

        return ScoredRound(
            outcome: .valid,
            reactionTime: reactionTime,
            movementTime: rawMovementTime(of: round)
        )
    }
    
    nonisolated static func rawReactionTime(of round: RoundRecord) -> Double? {
        interval(from: round.cueOnsetAt, to: round.liftOffAt)
    }

    
    nonisolated static func rawMovementTime(of round: RoundRecord) -> Double? {
        interval(from: round.liftOffAt, to: round.catchAt)
    }

    nonisolated private static func interval(from start: TimeInterval?, to end: TimeInterval?) -> Double? {
        guard let start, let end, start.isFinite, end.isFinite else {
            return nil
        }
        let elapsed = end - start
        guard elapsed.isFinite, elapsed > 0 else {
            return nil
        }
        return elapsed
    }
}

// holds the adjustable numbers so they are all in one place and can be implemented into the tests:
nonisolated struct AkinesiaThresholds {

    // reaction time >= anticipationCeiling   = valid
    var anticipationCeiling: TimeInterval = 0.120
     
    // reaction time > lapseFloor   = inattention/distracted
    var lapseFloor: TimeInterval = 2.0
    
    // rounds < minimumValidRounds  = records counts/raw times  but no summary stats
    var minimumValidRounds: Int = 8
    static let `default` = AkinesiaThresholds()
}
