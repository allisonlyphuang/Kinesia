import CoreGraphics
import Foundation
import SwiftUI

nonisolated enum ReportExportError: Error, Equatable {
    case couldNotCreateFile
    case nothingToRender
}

// Section 9. Renders the same chart views into a PDF.
//
// Reusing the views is the point: there is no second drawing path to keep in step, so what
// the clinician reads on paper is what the patient saw on screen.
@MainActor
enum ReportExport {

    static func renderPDF(model: ClinicianReportModel) throws -> URL {
        guard model.window != nil else { throw ReportExportError.nothingToRender }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinesia-movement-report-\(Int(Date().timeIntervalSince1970)).pdf")

        var mediaBox = CGRect(origin: .zero, size: ReportLayout.pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ReportExportError.couldNotCreateFile
        }

        for page in pages(for: model) {
            render(page, into: pdf)
        }

        pdf.closePDF()
        return url
    }

    /// one page per group of sections, split by hand
    private static func pages(for model: ClinicianReportModel) -> [AnyView] {
        var result: [AnyView] = []

        result.append(AnyView(
            ReportPage(pageNumber: 1, of: 3, model: model) {
                VStack(alignment: .leading, spacing: ReportLayout.sectionSpacing) {
                    if let quality = model.quality {
                        DataQualitySection(quality: quality, theme: .print)
                    }
                }
            }
        ))

        result.append(AnyView(
            ReportPage(pageNumber: 2, of: 3, model: model) {
                VStack(alignment: .leading, spacing: ReportLayout.sectionSpacing) {
                    ChartSection(
                        title: "\(model.metric.shortTitle) by time since dose",
                        subtitle: "All \(model.days.count) days pooled, \(model.hand.rawValue) hand",
                        caption: "A group with one reading has a median and no range",
                        legend: [
                            .symbol("One check-in", Color.secondaryColor, .circle),
                            .symbol("Median", Color.primaryColor, .circle),
                            .line("25th to 75th percentile", Color.primaryColor)
                        ],
                        theme: .print
                    ) {
                        TimeSinceDoseChart(bins: model.doseBins, metric: model.metric, theme: .print)
                    }

                    ChartSection(
                        title: "Dose timing",
                        subtitle: "\(model.adherence.count) scheduled doses",
                        caption: "Dots on the line were taken on schedule, dots above the line indicate late dose",
                        theme: .print
                    ) {
                        AdherenceChart(
                            points: model.adherence,
                            window: model.window ?? .trailing()!,
                            theme: .print
                        )
                    }
                }
            }
        ))

        result.append(AnyView(
            ReportPage(pageNumber: 3, of: 3, model: model) {
                VStack(alignment: .leading, spacing: ReportLayout.sectionSpacing) {
                    ChartSection(
                        title: "\(model.metric.shortTitle) per day",
                        subtitle: "Daily median, \(model.hand.rawValue) hand",
                        caption: "The line breaks across days with no check-in",
                        legend: model.baseline == nil ? [] : [.band("Baseline, 25th to 75th percentile", ChartTokens.baselineBand)],
                        theme: .print
                    ) {
                        LongitudinalTrendChart(
                            aggregates: model.dailyAggregates,
                            baseline: model.baseline,
                            hand: model.hand,
                            metric: model.metric,
                            theme: .print
                        )
                    }

                    ChartSection(
                        title: "Quality of life",
                        subtitle: "PDQ-8 short form",
                        theme: .print
                    ) {
                        PDQ8TrendChart(answers: model.questionnaires, theme: .print)
                    }
                }
            }
        ))

        return result
    }

    private static func render(_ page: AnyView, into pdf: CGContext) {
        let renderer = ImageRenderer(
            content: page
                .frame(width: ReportLayout.pageSize.width, height: ReportLayout.pageSize.height)
                .environment(\.colorScheme, .light)
        )
        renderer.proposedSize = ProposedViewSize(ReportLayout.pageSize)

        renderer.render { _, draw in
            pdf.beginPDFPage(nil)
            // paper pdf background is white
            //this guards the margin area if something renders a transparent background
            pdf.setFillColor(CGColor(gray: 1, alpha: 1))
            pdf.fill(CGRect(origin: .zero, size: ReportLayout.pageSize))
            draw(pdf)
            pdf.endPDFPage()
        }
    }
}

struct ReportPage<Content: View>: View {
    let pageNumber: Int
    let of: Int
    @ObservedObject var model: ClinicianReportModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pageNumber == 1 {
                Text("Movement report")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.textDark)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMedium)
                    .padding(.top, 3)
                    .padding(.bottom, ReportLayout.sectionSpacing)
            }

            content()

            Spacer(minLength: 0)

            HStack {
                Text("Not a diagnostic tool.")
                Spacer()
                Text("Page \(pageNumber) of \(of)")
            }
            .font(.system(size: 9))
            .foregroundStyle(Color.textMedium)
            .padding(.top, 12)
        }
        .frame(width: ReportLayout.pageContentWidth, alignment: .topLeading)
        // Equal margins on all four sides of the sheet.
        .padding(ReportLayout.pageMargin)
        .frame(
            width: ReportLayout.pageSize.width,
            height: ReportLayout.pageSize.height,
            alignment: .topLeading
        )
        .background(ReportTheme.print.background)
    }

    private var subtitle: String {
        guard let window = model.window else { return "" }
        let range = "\(window.start.formatted(ReportFormat.dayMonth)) to \(window.days.last?.formatted(ReportFormat.dayMonth) ?? "")"
        return "\(range). \(model.sessions.count) check-ins, \(model.hand.rawValue.capitalizedFirst) hand"
    }
}
