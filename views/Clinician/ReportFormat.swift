import Charts
import SwiftUI

// shared formatting and axis styling
nonisolated enum ReportFormat {

    /// add decimals on the axis values when not an int
    static func axis(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        return value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }

    static func signed(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == 0 { return "0" }
        return (value > 0 ? "+" : "−") + axis(abs(value))
    }

    static func minutes(_ value: Double) -> String {
        signed(value)
    }

    /// h:mm for duration
    static func clock(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// "1 reading", "3 readings". Stops subtitles reading "1 readings".
    static func count(_ number: Int, _ singular: String, plural: String? = nil) -> String {
        "\(number) \(number == 1 ? singular : plural ?? singular + "s")"
    }

    /// Days between x-axis labels. A 30 day window cannot print 30 of them across a phone,
    /// so labels thin out while every day keeps its tick.
    static func labelStride(for count: Int, maximumLabels: Int = 7) -> Int {
        guard count > maximumLabels else { return 1 }
        return Int((Double(count) / Double(maximumLabels)).rounded(.up))
    }

    /// "Fri 18" reads better on a short window; "18 Oct" is needed once the window spans
    /// more than one month.
    static func dayLabel(for dayCount: Int) -> Date.FormatStyle {
        dayCount <= 14 ? weekdayDay : dayMonth
    }

    static let dayMonth: Date.FormatStyle = .dateTime.day().month(.abbreviated)
    static let weekdayDay: Date.FormatStyle = .dateTime.weekday(.abbreviated).day()
    static let monthOnly: Date.FormatStyle = .dateTime.month(.abbreviated)
    static let timeOnly: Date.FormatStyle = .dateTime.hour().minute()
}

extension PrimaryMetric {
    /// Axis title with the unit in brackets, the way a clinical chart labels an axis.
    var axisTitle: String {
        switch self {
        case .tapRate: return "Tap rate (taps/s)"
        case .reactionTime: return "Reaction time (ms)"
        case .tracingError: return "Distance from route (units)"
        }
    }

    /// For the Measure control, which has one line. `lineLimit` does not reach a menu
    /// picker's own label, so the text has to be short enough on its own.
    var pickerTitle: String {
        switch self {
        case .tapRate: return "Tapping"
        case .reactionTime: return "Fireflies"
        case .tracingError: return "Tracing"
        }
    }

    var shortTitle: String {
        switch self {
        case .tapRate: return "Tapping"
        case .reactionTime: return "Fireflies"
        case .tracingError: return "Constellation tracing"
        }
    }
}

extension View {
    /// general setup shared by each report chart
    func reportAxisStyle() -> some View {
        self
            .font(.system(size: 9.5))
            .foregroundStyle(ChartTokens.axisLabel)
            .chartPlotStyle { plot in
                // Not clipped. `.clipped()` also removes RuleMark annotations, which sit just
                // outside the plot area: it dropped the dose times from the timeline. Marks are
                // kept inside by each chart's y domain following its own data instead.
                plot.background(Color.clear)
            }
    }
}
