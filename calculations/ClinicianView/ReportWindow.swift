// define a date range for the report
// give a start and end instant to fetch CoreData sessions between the ends
// list every day in the range, including days with no sessions, for the chart

// note that in a timezone with daylihgt savings, a day is not always 86,400 seconds --> all date calculations go throuhg Calendar

import Foundation

nonisolated enum ReportWindowLength: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case twoWeeks = 14
    case month = 30
    case threeMonths = 90
    case sixMonths = 182
    case year = 365
    case twoYears = 730

    var id: Int { rawValue }
    var days: Int { rawValue }

    var label: String {
        switch self {
        case .week: return "7 days"
        case .twoWeeks: return "14 days"
        case .month: return "30 days"
        case .threeMonths: return "90 days"
        case .sixMonths: return "6 months"
        case .year: return "12 months"
        case .twoYears: return "24 months"
        }
    }
}

// each chart picks its own span, so the 7/14/30 selector at the top of the report does not
// govern the two charts that answer questions about weeks and months
nonisolated enum ReportWindowScale: String, CaseIterable, Identifiable, Sendable {
    // daily timeline, time since dose, dose timing
    case day
    // tapping day by day
    case trend
    // PDQ-8
    case survey

    var id: String { rawValue }

    var lengths: [ReportWindowLength] {
        switch self {
        case .day: return [.week, .twoWeeks, .month]
        case .trend: return [.month, .threeMonths, .sixMonths]
        case .survey: return [.sixMonths, .year, .twoYears]
        }
    }

    // 7 days is the report default: one week of diary data predicted four-week results well
    var defaultLength: ReportWindowLength {
        switch self {
        case .day: return .week
        case .trend: return .month
        case .survey: return .sixMonths
        }
    }
}

// start = local midnight of first day
// end = local midnight of day after end day, so end day is fully included
nonisolated struct ReportWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    let calendar: Calendar
    
    init?(days: Int, endingOn instant: Date = Date(), calendar: Calendar = .current) {
        guard days > 0 else { return nil }
        
        let lastDay = calendar.startOfDay(for: instant)
        
        guard let firstDay = calendar.date(byAdding: .day, value: -(days-1), to: lastDay),
              let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
        self.start = firstDay
        self.end = dayAfterLast
        self.calendar = calendar
    }
    
    var days: [Date] {
        var result: [Date] = []
        var day = start
        while day < end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
    
    var dayCount: Int {
        days.count
    }
    
    func contains(_ instant: Date) -> Bool {
        instant >= start && instant < end
    }
    
    var startEpoch: TimeInterval {start.timeIntervalSince1970}
    var endEpoch: TimeInterval {end.timeIntervalSince1970}
    
}

extension ReportWindow {
    static func trailing(
        _ length: ReportWindowLength = .week,
        endingOn instant: Date = Date(),
        calendar: Calendar = .current
    ) -> ReportWindow? {
        ReportWindow(days: length.rawValue, endingOn: instant, calendar: calendar)
    }

    // the window a chart starts on before the reader changes its span
    static func trailing(
        scale: ReportWindowScale,
        endingOn instant: Date = Date(),
        calendar: Calendar = .current
    ) -> ReportWindow? {
        trailing(scale.defaultLength, endingOn: instant, calendar: calendar)
    }
}


