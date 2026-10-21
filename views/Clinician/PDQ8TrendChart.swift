import Charts
import SwiftUI

// Based on PDQ8 score, is quality of life changing over months?

struct PDQ8TrendChart: View {
    let answers: [PDQ8Snapshot]
    var theme: ReportTheme = .screen

    // Two years of monthly answers is 24 labels, so these thin out too.
    private var labelStride: Int {
        ReportFormat.labelStride(for: answers.count)
    }

    var body: some View {
        Chart {
            ForEach(answers) { answer in
                LineMark(
                    x: .value("Month answered", answer.completedAt, unit: .month),
                    y: .value("PDQ-8 index", answer.scoreIndex)
                )
                .foregroundStyle(Color.accentBlue)
                .lineStyle(StrokeStyle(lineWidth: ChartTokens.lineWidth))

                PointMark(
                    x: .value("Month answered", answer.completedAt, unit: .month),
                    y: .value("PDQ-8 index", answer.scoreIndex)
                )
                .foregroundStyle(Color.accentBlue)
                .symbolSize(ChartTokens.markSize)
                .annotation(position: .top, spacing: 3) {
                    Text(ReportFormat.axis(answer.scoreIndex.rounded()))
                        .font(.system(size: 7))
                        .foregroundStyle(ChartTokens.annotation)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
            }
            AxisMarks(values: .stride(by: .month, count: labelStride)) { _ in
                AxisValueLabel(format: ReportFormat.monthOnly)
                    .font(.system(size: 8))
                    .foregroundStyle(ChartTokens.axisLabel)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 20, 40, 60, 80, 100]) { value in
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
        .chartXAxisLabel("Month answered", alignment: .center)
        .chartYAxisLabel("PDQ-8 index", position: .leading)
        .frame(height: ChartTokens.shortChartHeight)
        .reportAxisStyle()
    }
}
