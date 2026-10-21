import Charts
import SwiftUI

// how does the task change after this done/before the next dose?

struct TimeSinceDoseChart: View {
    let bins: [DoseBin]
    let metric: PrimaryMetric
    var theme: ReportTheme = .screen

    private var labels: [String] { bins.map(\.kind.label) }

    private var upperBound: Double {
        let values = bins.flatMap { $0.points.map(\.value) }
        return max(values.max() ?? 1, 1) * 1.25
    }

    var body: some View {
        Chart {
            // individual readings
            ForEach(bins) { bin in
                ForEach(Array(bin.points.enumerated()), id: \.element.id) { index, point in
                    PointMark(
                        x: .value("Time since dose", bin.kind.label),
                        y: .value(metric.unitLabel, point.value)
                    )
                    .foregroundStyle(Color.secondaryColor)
                    .symbolSize(8)
                    .offset(x: jitter(index: index, count: bin.points.count))
                }
            }

            // interquartile range
            ForEach(bins) { bin in
                if let p25 = bin.p25, let p75 = bin.p75 {
                    RuleMark(
                        x: .value("Time since dose", bin.kind.label),
                        yStart: .value("25th percentile", p25),
                        yEnd: .value("75th percentile", p75)
                    )
                    .foregroundStyle(Color.primaryColor)
                    .lineStyle(StrokeStyle(lineWidth: ChartTokens.whiskerWidth))
                }
            }

            ForEach(bins) { bin in
                if let median = bin.median {
                    PointMark(
                        x: .value("Time since dose", bin.kind.label),
                        y: .value("Median", median)
                    )
                    .foregroundStyle(Color.primaryColor)
                    .symbol(.circle)
                    .symbolSize(ChartTokens.medianMarkSize)
                }
            }
        }
        .chartXScale(domain: labels)
        .chartYScale(domain: 0...upperBound)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: labels) { value in
                AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
                AxisValueLabel {
                    if let label = value.as(String.self),
                       let bin = bins.first(where: { $0.kind.label == label }) {
                        VStack(spacing: 1) {
                            // Only the hour boundaries carry text, but every bin keeps the
                            // row, so a count under an unlabelled bin cannot ride up into
                            // the line of labels beside it.
                            Text(bin.kind.isMajor ? bin.kind.shortLabel : " ")
                                .font(.system(size: 8))
                                .foregroundStyle(ChartTokens.axisLabel)
                            // An empty bin shows nothing rather than a row of n=0.
                            Text(bin.sessionCount > 0 ? "n=\(bin.sessionCount)" : " ")
                                .font(.system(size: 6.5))
                                .foregroundStyle(ChartTokens.annotation)
                        }
                    }
                }
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
        .chartXAxisLabel("Time since last dose (h:mm)", alignment: .center)
        .chartYAxisLabel(metric.axisTitle, position: .leading)
        .frame(height: ChartTokens.chartHeight + 20)
        .reportAxisStyle()
    }

    /// spreads out readings to distinguish multiple data points at same y value 
    private func jitter(index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let step: CGFloat = 4
        let centered = CGFloat(index) - CGFloat(count - 1) / 2
        return centered * step
    }
}
