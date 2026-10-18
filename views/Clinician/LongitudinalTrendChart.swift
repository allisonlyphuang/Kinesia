import Charts
import SwiftUI

// How is the task changing over weeks?

struct LongitudinalTrendChart: View {
    let aggregates: [DailyAggregate]
    let baseline: Baseline?
    let hand: CurrentHand
    let metric: PrimaryMetric
    var theme: ReportTheme = .screen

    private struct Reading: Identifiable {
        let id = UUID()
        let day: Date
        let value: Double
        let run: Int
    }

    /// groups days into consecutive unbroken stretches
    private var readings: [Reading] {
        var result: [Reading] = []
        var run = 0
        var previousHadValue = false

        for aggregate in aggregates {
            guard let value = aggregate.value(for: hand) else {
                previousHadValue = false
                continue
            }
            if !previousHadValue { run += 1 }
            result.append(Reading(day: aggregate.dayStart, value: value, run: run))
            previousHadValue = true
        }
        return result
    }

    private var emptyDays: [Date] {
        aggregates.filter { $0.value(for: hand) == nil }.map(\.dayStart)
    }

    private var upperBound: Double {
        let values = readings.map(\.value) + [baseline?.upper ?? 0]
        return max(values.max() ?? 1, 1) * 1.25
    }

    var body: some View {
        Chart {
            if let baseline, let first = aggregates.first?.dayStart, let last = aggregates.last?.dayStart {
                RectangleMark(
                    xStart: .value("From", first),
                    xEnd: .value("To", last),
                    yStart: .value("25th percentile", baseline.lower),
                    yEnd: .value("75th percentile", baseline.upper)
                )
                .foregroundStyle(ChartTokens.baselineBand)

                RuleMark(y: .value("Baseline", baseline.center))
                    .foregroundStyle(ChartTokens.baselineCenter)
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            }

            ForEach(readings) { reading in
                LineMark(
                    x: .value("Date", reading.day, unit: .day),
                    y: .value(metric.unitLabel, reading.value),
                    series: .value("Run", reading.run)
                )
                .foregroundStyle(Color.primaryColor)
                .lineStyle(StrokeStyle(lineWidth: ChartTokens.lineWidth))

                PointMark(
                    x: .value("Date", reading.day, unit: .day),
                    y: .value(metric.unitLabel, reading.value)
                )
                .foregroundStyle(Color.primaryColor)
                .symbolSize(10)
            }
        }
        .chartYScale(domain: 0...upperBound)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
                AxisValueLabel(format: ReportFormat.dayMonth)
                    .font(.system(size: 8))
                    .foregroundStyle(ChartTokens.axisLabel)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(ChartTokens.gridLine)
                AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(ReportFormat.axis(raw))
                            .font(.system(size: 8))
                            .foregroundStyle(ChartTokens.axisLabel)
                    }
                }
            }
        }
        .chartXAxisLabel("Date", alignment: .center)
        .chartYAxisLabel("Daily median \(metric.axisTitle)", position: .leading)
        .frame(height: ChartTokens.chartHeight)
        .reportAxisStyle()
        .overlay(alignment: .bottomTrailing) {
            if !emptyDays.isEmpty {
                Text("\(aggregates.count - emptyDays.count) of \(aggregates.count) days have a check-in")
                    .font(.system(size: 8))
                    .foregroundStyle(ChartTokens.annotation)
            }
        }
    }
}
