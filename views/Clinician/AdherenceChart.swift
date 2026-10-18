import Charts
import SwiftUI

// Are doses taken and taken on schedule?

struct AdherenceChart: View {
    let points: [AdherencePoint]
    let window: ReportWindow
    var theme: ReportTheme = .screen

    private var taken: [AdherencePoint] { points.filter { $0.delayMinutes != nil } }
    private var skipped: [AdherencePoint] { points.filter(\.wasSkipped) }

    private var labelStride: Int {
        ReportFormat.labelStride(for: window.dayCount)
    }

    private var bound: Double {
        let worst = taken.compactMap(\.delayMinutes).map(abs).max() ?? 60
        return max(worst * 1.2, 60)
    }

    private var slotColors: [Int: Color] {
        let palette: [Color] = [.primaryColor, .accentBlue, Color(.sRGB, red: 0xC4/255, green: 0xA7/255, blue: 0x7D/255), .textDark]
        let slots = Adherence.slots(in: points)
        return Dictionary(uniqueKeysWithValues: slots.enumerated().map { ($1, palette[$0 % palette.count]) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Chart {
                RuleMark(y: .value("On schedule", 0))
                    .foregroundStyle(ChartTokens.referenceLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.1))
                    .annotation(position: .top, alignment: .trailing, spacing: 1) {
                        Text("on schedule")
                            .font(.system(size: 7))
                            .foregroundStyle(ChartTokens.annotation)
                    }

                ForEach(taken) { point in
                    PointMark(
                        x: .value("Day", point.dayStart, unit: .day),
                        y: .value("Minutes from scheduled", point.delayMinutes ?? 0)
                    )
                    .foregroundStyle(slotColors[point.slotMinutesIntoDay] ?? Color.primaryColor)
                    .symbolSize(ChartTokens.markSize)
                }
            }
            .chartYScale(domain: -bound...bound)
            .chartXScale(domain: window.start...window.end)
            .chartLegend(.hidden)
            .chartXAxis {
                // A tick for every day, a label only every few, so a 30 day window stays
                // readable without losing the daily grid.
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisTick(length: 4).foregroundStyle(ChartTokens.axisLine)
                }
                AxisMarks(values: .stride(by: .day, count: labelStride)) { _ in
                    AxisValueLabel(format: ReportFormat.dayLabel(for: window.dayCount))
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
                            Text(ReportFormat.signed(raw))
                                .font(.system(size: 8))
                                .foregroundStyle(ChartTokens.axisLabel)
                        }
                    }
                }
            }
            .chartYAxisLabel("Taken minus scheduled (min)", position: .leading)
            .frame(height: ChartTokens.chartHeight)
            .reportAxisStyle()

            // shows skipped doses
            Chart {
                ForEach(skipped) { point in
                    PointMark(
                        x: .value("Day", point.dayStart, unit: .day),
                        y: .value("Skipped", 0)
                    )
                    .foregroundStyle(slotColors[point.slotMinutesIntoDay] ?? Color.primaryColor)
                    .symbol(.triangle)
                    .symbolSize(ChartTokens.markSize)
                }
            }
            .chartXScale(domain: window.start...window.end)
            .chartYScale(domain: -1...1)
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0]) { _ in
                    AxisValueLabel {
                        Text("skipped")
                            .font(.system(size: 7.5))
                            .foregroundStyle(ChartTokens.annotation)
                    }
                }
            }
            .frame(height: 26)
            .reportAxisStyle()

            Text("Date")
                .font(.system(size: 9.5))
                .foregroundStyle(ChartTokens.axisLabel)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

 
    func legend() -> [LegendEntry] {
        let slots = Adherence.slots(in: points)
        var entries = slots.map { slot in
            LegendEntry.symbol(
                ReportFormat.clock(minutes: slot),
                slotColors[slot] ?? Color.primaryColor,
                .circle
            )
        }
        if !skipped.isEmpty {
            entries.append(.symbol("Skipped", ChartTokens.annotation, .triangle))
        }
        return entries
    }
}
