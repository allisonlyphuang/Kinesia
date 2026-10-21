nonisolated enum PrimaryMetric: String, CaseIterable, Identifiable {
    case tapRate        // taps / sec
    case reactionTime   // ms
    case tracingError   // in route units
    
    var id: String { rawValue }
    
    var unitLabel: String {
        switch self {
        case .tapRate: return "taps/sec"
        case .reactionTime: return "ms"
        case .tracingError: return "route units"
        }
    }
    var higherIsBetter: Bool {
        switch self {
        case .tapRate: return true
        case .reactionTime: return false
        case . tracingError: return false
        }
    }
    
    // for orienting longitudinal charts for "improvement"
    func value(_ session: SessionSnapshot, hand: CurrentHand) -> Double? {
        switch self {
        case .tapRate:
            guard let tapping = session.tapping.first(where: { $0.hand == hand }),
                tapping.durationSec > 0 else { return nil }
            return Double(tapping.numTaps) / tapping.durationSec
        case .reactionTime:
            guard let firefly = session.firefly, firefly.hand == hand else { return nil }
            return firefly.reactionTimeMedian.map { $0 * 1000 }
        case .tracingError:
            guard let tracing = session.tracing, tracing.hand == hand else { return nil }
            return tracing.rmsError
        }
    }
}
