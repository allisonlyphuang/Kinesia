import Charts
import SwiftUI

// relative to doses, when in the day is the task slowest?
/// x is hours since local midnight, so the axis is a fixed 0 to 24
struct DailyTimelineChart: View {
    struct Point: Identifiable, Equatable {
        let id: UUID
        let hour: Double
        let value: Double
        let hand: CurrentHand
    }

    struct DoseMarker: Identifiable, Equatable {
        let id: UUID
        let hour: Double
        let wasSkipped: Bool
        let label: String
    }

    let points: [Point]
    let doses: [DoseMarker]
    let metric: PrimaryMetric
    var theme: ReportTheme = .screen

    private var upperBound: Double {
        max(points.map(\.value).max() ?? 1, 1) * 1.25
    }

    var body: some View {
        Chart {
            ForEach(doses) { dose in
                RuleMark(x: .value("Dose", dose.hour))
                    .foregroundStyle(ChartTokens.doseMarker)
                    .lineStyle(dose.wasSkipped ? ChartTokens.doseSkippedStroke : ChartTokens.doseTakenStroke)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(dose.label)
                            .font(.system(size: 7.5))
                            .foregroundStyle(Color.textDark)
                    }
            }

            ForEach(points) { point in
                PointMark(
                    x: .value("Time of day", point.hour),
                    y: .value(metric.unitLabel, point.value)
                )
                .foregroundStyle(ChartTokens.handColor(point.hand))
                .symbol(ChartTokens.handSymbol(point.hand).shape)
                .symbolSize(ChartTokens.markSize)
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...upperBound)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 0, through: 24, by: 2))) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
                if let hour = value.as(Double.self), Int(hour) % 4 == 0 {
                    AxisValueLabel {
                        Text(String(format: "%02d", Int(hour)))
                            .font(.system(size: 8))
                            .foregroundStyle(ChartTokens.axisLabel)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(ChartTokens.gridLine)
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
        .chartXAxisLabel("Time of day (hours)", alignment: .center)
        .chartYAxisLabel(metric.axisTitle, position: .leading)
        .frame(height: ChartTokens.chartHeight)
        .reportAxisStyle()
    }
}
