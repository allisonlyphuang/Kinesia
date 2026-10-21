import Foundation

nonisolated struct DailyValue: Equatable, Sendable {
    let day: Date
    let value: Double
}


nonisolated struct Baseline: Equatable, Sendable {
    let hand: CurrentHand
    let center: Double // median of the daily values
    let lower: Double // p25
    let upper: Double // p75
    let spread: Double // sample standard deviation used for z-scores
    let dayCount: Int
    let establishedOn: Date // last day included in the baseline

    func contains(_ value: Double) -> Bool {
        value >= lower && value <= upper
    }
}

nonisolated enum BaselineState: Equatable, Sendable {
    case familiarization(dayNumber: Int, of: Int)
    case building(dayNumber: Int, of: Int)
    case established(Baseline)

    var baseline: Baseline? {
        guard case .established(let baseline) = self else { return nil }
        return baseline
    }
}

nonisolated enum BaselineRule {

    
    static let familiarizationDays = 5

    // Roche PD Mobile showed good to excellent test retest reliability between two 2-week periods, therefore baseline is 14 days
    static let baselineDays = 14

    static var requiredDays: Int { familiarizationDays + baselineDays }


    // days are counted as days that produced data; skipping days takes longer to reach baseline
    // baseline always remains the first 14 days
    static func state(from dailyValues: [DailyValue], hand: CurrentHand) -> BaselineState {
        let ordered = dailyValues
            .filter { $0.value.isFinite }
            .sorted { $0.day < $1.day }

        if ordered.count < familiarizationDays {
            return .familiarization(dayNumber: ordered.count, of: familiarizationDays)
        }

        let afterFamiliarization = ordered.dropFirst(familiarizationDays)

        if afterFamiliarization.count < baselineDays {
            return .building(dayNumber: afterFamiliarization.count, of: baselineDays)
        }

        let baselineDaysSlice = Array(afterFamiliarization.prefix(baselineDays))
        guard let stats = SummaryStats.compute(baselineDaysSlice.map(\.value)),
              let establishedOn = baselineDaysSlice.last?.day else {
            // 14 finite values always produce stats, so this is unreachable in practice.
            return .building(dayNumber: afterFamiliarization.count, of: baselineDays)
        }

        return .established(
            Baseline(
                hand: hand,
                center: stats.median,
                lower: stats.p25,
                upper: stats.p75,
                spread: stats.stdev,
                dayCount: baselineDaysSlice.count,
                establishedOn: establishedOn
            )
        )
    }

 
    static func dailyValues(
        sessions: [SessionSnapshot],
        hand: CurrentHand,
        calendar: Calendar = .current,
        value: (SessionSnapshot, CurrentHand) -> Double?
    ) -> [DailyValue] {
        let byDay = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.dayStart)
        }

        return byDay.compactMap { day, daySessions in
            guard let median = DailyAggregation.median(daySessions.compactMap { value($0, hand) }) else {
                return nil
            }
            return DailyValue(day: day, value: median)
        }
        .sorted { $0.day < $1.day }
    }
}
