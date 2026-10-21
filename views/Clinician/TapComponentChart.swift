import Charts
import SwiftUI

//Which part of tapping is changing: speed, rhythm, or decrement?

struct TapComponentChart: View {
    let points: [TapComponentPoint]
    let accuracy: [TapAccuracyPoint]
    var theme: ReportTheme = .screen

    // Follows the data, with a floor of 2 so an ordinary week still reads on a +/-2 scale.
    // A fixed domain let an outlying day draw its line outside the plot area.
    private var bound: Double {
        let worst = points.compactMap(\.z).map(abs).max() ?? 2
        return Swift.max(2, worst.rounded(.up))
    }

    private var dayCount: Int { Set(points.map(\.dayStart)).count }
    private var labelStride: Int { ReportFormat.labelStride(for: dayCount) }

    private let accuracyFloor: Double = 0.80
    private let accuracyCeiling: Double = 1.00

    private func mapped(_ accuracy: Double) -> Double {
        let fraction = (accuracy - accuracyFloor) / (accuracyCeiling - accuracyFloor)
        return (fraction * 2 - 1) * bound
    }

    private func accuracyLabel(for z: Double) -> String {
        let fraction = (z / bound + 1) / 2
        let percent = (accuracyFloor + fraction * (accuracyCeiling - accuracyFloor)) * 100
        return "\(Int(percent.rounded()))%"
    }

    private var axisValues: [Double] {
        stride(from: -bound, through: bound, by: bound / 2).map { $0 }
    }

    private func style(_ component: TapComponent) -> (Color, [CGFloat]) {
        switch component {
        case .speed: return (.primaryColor, [])
        case .rhythm: return (.accentBlue, [5, 3])
        case .decrement: return (.textDark, [1.5, 2.5])
        }
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Baseline", 0))
                .foregroundStyle(ChartTokens.referenceLine)
                .lineStyle(StrokeStyle(lineWidth: 1.1))
                .annotation(position: .top, alignment: .trailing, spacing: 1) {
                    Text("baseline")
                        .font(.system(size: 7))
                        .foregroundStyle(ChartTokens.annotation)
                }

            ForEach(points.filter { $0.z != nil }) { point in
                LineMark(
                    x: .value("Date", point.dayStart, unit: .day),
                    y: .value("Distance from baseline", point.z ?? 0),
                    series: .value("Component", point.component.label)
                )
                .foregroundStyle(style(point.component).0)
                .lineStyle(StrokeStyle(lineWidth: ChartTokens.lineWidth, dash: style(point.component).1))
            }

            ForEach(accuracy.filter { $0.accuracy != nil }) { point in
                LineMark(
                    x: .value("Date", point.dayStart, unit: .day),
                    y: .value("Accuracy", mapped(point.accuracy ?? 0)),
                    series: .value("Component", "Accuracy")
                )
                .foregroundStyle(Color.secondaryColor)
                .lineStyle(StrokeStyle(lineWidth: ChartTokens.thinLineWidth))
            }
        }
        .chartYScale(domain: -bound...bound)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
            }
            AxisMarks(values: .stride(by: .day, count: labelStride)) { _ in
                AxisValueLabel(format: ReportFormat.dayLabel(for: dayCount))
                    .font(.system(size: 8))
                    .foregroundStyle(ChartTokens.axisLabel)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: axisValues) { value in
                AxisGridLine().foregroundStyle(ChartTokens.gridLine)
                AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(ReportFormat.signed(raw))
                            .font(.system(size: 8))
                            .foregroundStyle(ChartTokens.axisLabel)
                    }
                }
            }
            AxisMarks(position: .trailing, values: axisValues) { value in
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(accuracyLabel(for: raw))
                            .font(.system(size: 8))
                            .foregroundStyle(ChartTokens.annotation)
                    }
                }
            }
        }
        .chartXAxisLabel("Date", alignment: .center)
        .chartYAxisLabel("Distance from baseline (SD)", position: .leading)
        .chartYAxisLabel("Accuracy (%)", position: .trailing)
        .frame(height: ChartTokens.chartHeight)
        .reportAxisStyle()
        .padding(.bottom, 18)
    }

    func legend() -> [LegendEntry] {
        TapComponent.allCases.map { component in
            LegendEntry.line(component.label, style(component).0, dash: style(component).1)
        } + [.line("Accuracy, right axis", Color.secondaryColor)]
    }
}
