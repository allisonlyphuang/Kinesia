import Foundation


nonisolated enum TapComponent: String, CaseIterable, Identifiable, Sendable {
    case speed
    case rhythm
    case decrement

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speed: return "Speed"
        case .rhythm: return "Rhythm"
        case .decrement: return "Decrement"
        }
    }

    var unitLabel: String {
        switch self {
        case .speed: return "taps/sec"
        case .rhythm: return "% variation"
        case .decrement: return "sec/tap"
        }
    }


    var higherIsWorse: Bool {
        switch self {
        case .speed: return false // more taps per second is better
        case .rhythm: return true // more variable intervals is worse
        case .decrement: return true // intervals lengthening faster is worse
        }
    }

    func value(_ tapping: TappingSnapshot) -> Double? {
        switch self {
        case .speed:
            guard tapping.durationSec > 0 else { return nil }
            return Double(tapping.numTaps) / tapping.durationSec
        case .rhythm:
            return tapping.cvTapInter
        case .decrement:
            return tapping.tapInterSlope
        }
    }

    func value(_ session: SessionSnapshot, hand: CurrentHand) -> Double? {
        guard let tapping = session.tapping.first(where: { $0.hand == hand }) else { return nil }
        return value(tapping)
    }
}

nonisolated struct TapComponentPoint: Equatable, Sendable, Identifiable {
    let dayStart: Date
    let component: TapComponent
    let hand: CurrentHand
    let rawValue: Double?
    let z: Double?

    var id: String { "\(component.rawValue)-\(hand.rawValue)-\(dayStart.timeIntervalSince1970)" }
}

nonisolated struct TapAccuracyPoint: Equatable, Sendable, Identifiable {
    let dayStart: Date
    let hand: CurrentHand
    let accuracy: Double? // 0 to 1

    var id: Date { dayStart }
}

nonisolated enum TapComponents {

    // one baseline per component
    static func baselineStates(
        history: [SessionSnapshot],
        hand: CurrentHand,
        calendar: Calendar = .current
    ) -> [TapComponent: BaselineState] {
        var result: [TapComponent: BaselineState] = [:]
        for component in TapComponent.allCases {
            let values = BaselineRule.dailyValues(
                sessions: history,
                hand: hand,
                calendar: calendar,
                value: component.value
            )
            result[component] = BaselineRule.state(from: values, hand: hand)
        }
        return result
    }

    static func points(
        sessions: [SessionSnapshot],
        window: ReportWindow,
        hand: CurrentHand,
        baselines: [TapComponent: BaselineState]
    ) -> [TapComponentPoint] {
        TapComponent.allCases.flatMap { component in
            let medians = DailyAggregation.medians(
                sessions: sessions,
                window: window,
                hand: hand,
                value: component.value
            )
            let baseline = baselines[component]?.baseline

            return window.days.map { day in
                let raw = medians[day]
                return TapComponentPoint(
                    dayStart: day,
                    component: component,
                    hand: hand,
                    rawValue: raw,
                    z: zScore(raw, baseline: baseline, component: component)
                )
            }
        }
    }

    static func zScore(
        _ value: Double?,
        baseline: Baseline?,
        component: TapComponent
    ) -> Double? {
        guard let value, let baseline, value.isFinite else { return nil }
        guard baseline.spread.isFinite, baseline.spread > 0 else { return nil }

        let distance = (value - baseline.center) / baseline.spread
        let signed = component.higherIsWorse ? distance : -distance
        return signed.isFinite ? signed : nil
    }

    static func accuracy(
        sessions: [SessionSnapshot],
        window: ReportWindow,
        hand: CurrentHand
    ) -> [TapAccuracyPoint] {
        let medians = DailyAggregation.medians(
            sessions: sessions,
            window: window,
            hand: hand,
            value: { session, hand in
                guard let tapping = session.tapping.first(where: { $0.hand == hand }),
                      tapping.numTaps > 0 else {
                    return nil
                }
                return Double(tapping.numCorrectTaps) / Double(tapping.numTaps)
            }
        )

        return window.days.map { day in
            TapAccuracyPoint(dayStart: day, hand: hand, accuracy: medians[day])
        }
    }
}
