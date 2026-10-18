import CoreData
import SwiftUI


struct ClinicianReportView: View {
    @StateObject private var model: ClinicianReportModel
    @State private var exportedPDF: URL?
    @State private var exportError: String?

    init(model: ClinicianReportModel? = nil) {
        let resolved = model ?? ClinicianReportModel(
            context: PersistenceController.shared.container.viewContext
        )
        _model = StateObject(wrappedValue: resolved)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ReportLayout.sectionSpacing) {
                header
                controls
                Divider().overlay(ChartTokens.gridLine)

                ReportBody(model: model, theme: .screen)

                exportSection
#if DEBUG
                seedControl
#endif
                Text("Not a diagnostic tool.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
            // The one place the side margin is applied, so both sides match everywhere.
            .padding(.horizontal, ReportLayout.margin)
            .padding(.top, 22)
        }
        .background(ReportTheme.screen.background.ignoresSafeArea())
        .onAppear { if model.window == nil { model.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Movement report")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.textDark)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.textMedium)
        }
    }

    private var subtitle: String {
        guard let window = model.window else { return "Loading" }
        let range = "\(window.start.formatted(ReportFormat.dayMonth)) to \(window.days.last?.formatted(ReportFormat.dayMonth) ?? "")"
        return "\(range). \(ReportFormat.count(model.sessions.count, "check-in"))"
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                ForEach(ReportWindowScale.day.lengths) { length in
                    Button {
                        model.show(length: length)
                    } label: {
                        Text(length.label)
                            .font(.system(size: 14))
                            .foregroundStyle(model.dayLength == length ? Color.white : Color.textDark)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(model.dayLength == length ? Color.primaryColor : Color.clear)
                                    .stroke(model.dayLength == length ? Color.clear : Color.secondaryColor, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 5) {
                Text("Measure")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondaryColor)
                    .fixedSize()

                // One line each, one height for the row. "Constellation tracing, route units"
                // wrapped to four lines and ran into the section below. The unit is dropped
                // because every chart already carries it on its y axis.
                Picker("Measure", selection: $model.metric) {
                    ForEach(PrimaryMetric.allCases) { metric in
                        Text(metric.pickerTitle).tag(metric)
                    }
                }
                .labelsHidden()
                .tint(Color.textMedium)
                .font(.system(size: 12.5))
                .lineLimit(1)

                Spacer(minLength: 4)

                Picker("Hand", selection: $model.hand) {
                    ForEach(CurrentHand.allCases, id: \.self) { hand in
                        Text("\(hand.rawValue.capitalizedFirst) hand").tag(hand)
                    }
                }
                .labelsHidden()
                .tint(Color.textMedium)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .fixedSize()
            }
            .frame(height: 44)
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(ChartTokens.gridLine)

            Text("Send this to your clinician")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textDark)
                .padding(.top, ReportLayout.sectionSpacing)

            Text("All data is stored locally on your phone only.")
                .font(.system(size: 12))
                .foregroundStyle(Color.textMedium)
                .padding(.top, 2)

            if let exportedPDF {
                ShareLink(item: exportedPDF) {
                    Text("Share the PDF")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primaryColor)
                        }
                }
                .padding(.top, 12)
            } else {
                Button(action: makePDF) {
                    Text("Make a PDF")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primaryColor)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }

            if let exportError {
                Text(exportError)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMedium)
                    .padding(.top, 8)
            }
        }
    }

#if DEBUG
    // Debug builds only. Fills the store so the charts can be looked at on a device.
    private var seedControl: some View {
        Button("Fill with sample history") {
            try? ReportSeed.populate(in: PersistenceController.shared.container.viewContext)
            model.load()
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.accentBlue)
    }
#endif

    private func makePDF() {
        do {
            exportedPDF = try ReportExport.renderPDF(model: model)
            exportError = nil
        } catch {
            exportedPDF = nil
            exportError = "Failed to save. Try again."
        }
    }
}

struct ReportBody: View {
    @ObservedObject var model: ClinicianReportModel
    let theme: ReportTheme

    var body: some View {
        VStack(alignment: .leading, spacing: ReportLayout.sectionSpacing) {
            if let quality = model.quality {
                DataQualitySection(quality: quality, theme: theme)
                Divider().overlay(ChartTokens.gridLine)
            }

            dailyTimeline
            Divider().overlay(ChartTokens.gridLine)

            timeSinceDose
            Divider().overlay(ChartTokens.gridLine)

            adherence
            Divider().overlay(ChartTokens.gridLine)

            trend
            Divider().overlay(ChartTokens.gridLine)

            pdq8
            Divider().overlay(ChartTokens.gridLine)

            components
        }
    }

    @ViewBuilder
    private var dailyTimeline: some View {
        if let day = model.timelineDay {
            VStack(alignment: .leading, spacing: 0) {
                ChartSection(
                    title: "\(model.metric.shortTitle) throughout the day",
                    subtitle: "\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(ReportFormat.count(model.timelinePoints(for: day).count, "reading"))",
                    caption: nil,
                    legend: [
                        .symbol("Right hand", ChartTokens.handColor(.right), ChartTokens.handSymbol(.right)),
                        .symbol("Left hand", ChartTokens.handColor(.left), ChartTokens.handSymbol(.left)),
                        .line("Dose taken", ChartTokens.doseMarker),
                        .line("Dose skipped", ChartTokens.doseMarker, dash: [3, 2.5])
                    ],
                    theme: theme
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !theme.isPrint { daySelector(selected: day) }
                        DailyTimelineChart(
                            points: model.timelinePoints(for: day),
                            doses: model.doseMarkers(for: day),
                            metric: model.metric,
                            theme: theme
                        )
                    }
                }
            }
        }
    }

    private func daySelector(selected: Date) -> some View {
        HStack(spacing: 3) {
            ForEach(model.days.suffix(7), id: \.self) { day in
                Button {
                    model.show(day: day)
                } label: {
                    Text(day.formatted(ReportFormat.weekdayDay))
                        .font(.system(size: 11))
                        .foregroundStyle(day == selected ? Color.white : Color.textDark)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(day == selected ? Color.primaryColor : Color.clear)
                                .stroke(day == selected ? Color.clear : ChartTokens.gridLine, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeSinceDose: some View {
        ChartSection(
            title: "\(model.metric.shortTitle) by time since dose",
            subtitle: "All \(ReportFormat.count(model.days.count, "day")) pooled. \(ReportFormat.count(model.doseBins.reduce(0) { $0 + $1.sessionCount }, "reading")), \(model.hand.rawValue) hand",
            caption: "Groups are 30 minutes wide; a group with one reading has a median and no range",
            legend: [
                .symbol("One check-in", Color.secondaryColor, .circle),
                .symbol("Median", Color.primaryColor, .circle),
                .line("25th to 75th percentile", Color.primaryColor)
            ],
            theme: theme
        ) {
            TimeSinceDoseChart(bins: model.doseBins, metric: model.metric, theme: theme)
        }
    }

    private var adherence: some View {
        let chart = AdherenceChart(points: model.adherence, window: model.window ?? .trailing()!, theme: theme)
        return ChartSection(
            title: "Dose timing",
            subtitle: "\(ReportFormat.count(model.adherence.count, "scheduled dose"))",
            legend: chart.legend(),
            theme: theme
        ) {
            chart
        }
    }

    private var trend: some View {
        ChartSection(
            title: "\(model.metric.shortTitle) day by day",
            subtitle: trendSubtitle,
            legend: model.baseline == nil ? [] : [.band("Baseline, 25th to 75th percentile", ChartTokens.baselineBand)],
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LongitudinalTrendChart(
                    aggregates: model.dailyAggregates,
                    baseline: model.baseline,
                    hand: model.hand,
                    metric: model.metric,
                    theme: theme
                )
                if model.baseline == nil {
                    BaselineProgress(state: model.baselineState)
                }
            }
        }
    }

    private var trendSubtitle: String {
        switch model.baselineState {
        case .established(let baseline):
            return "Daily median, \(model.hand.rawValue) hand, baseline set \(baseline.establishedOn.formatted(ReportFormat.dayMonth))"
        default:
            return "Daily median, \(model.hand.rawValue) hand, no baseline yet"
        }
    }

    private var pdq8: some View {
        ChartSection(
            title: "Quality of life",
            subtitle: "PDQ-8 short form, \(ReportFormat.count(model.questionnaires.count, "answer"))",
            theme: theme
        ) {
            PDQ8TrendChart(answers: model.questionnaires, theme: theme)
        }
    }

    private var components: some View {
        let chart = TapComponentChart(
            points: model.componentPoints,
            accuracy: model.accuracyPoints,
            theme: theme
        )
        return ChartSection(
            title: "Tapping Task: Component Breakdown",
            subtitle: "\(model.hand.rawValue.capitalizedFirst) hand, distance from baseline in standard deviations",
            legend: chart.legend(),
            theme: theme
        ) {
            chart
        }
    }
}

struct BaselineProgress: View {
    let state: BaselineState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(fraction * 100))%")
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.textDark)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ChartTokens.gridLine)
                    Capsule().fill(Color.primaryColor)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
    }

    private var label: String {
        switch state {
        case .familiarization(let day, let total):
            return "Familiarization, day \(day) of \(total)"
        case .building(let day, let total):
            return "Building baseline, day \(day) of \(total)"
        case .established:
            return "Baseline set"
        }
    }

    private var fraction: Double {
        switch state {
        case .familiarization(let day, let total):
            return total == 0 ? 0 : Double(day) / Double(total)
        case .building(let day, let total):
            return total == 0 ? 0 : Double(day) / Double(total)
        case .established:
            return 1
        }
    }
}

#Preview {
    ClinicianReportView(
        model: ClinicianReportModel(context: PersistenceController.preview.container.viewContext)
    )
}
