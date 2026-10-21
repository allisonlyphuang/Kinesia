import CoreGraphics
import Foundation
import SwiftUI

nonisolated enum ReportExportError: Error, Equatable {
    case couldNotCreateFile
    case nothingToRender
}

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

    /// One page per group in `ReportSections.pageGroups`. The sections themselves come from
    /// the same list the screen renders, so a heading or caption cannot differ between them.
    private static func pages(for model: ClinicianReportModel) -> [AnyView] {
        let all = ReportSections.all(for: model)

        return ReportSections.pageGroups.enumerated().map { index, ids in
            let pageSpecs = ReportSections.specs(for: ids, in: all)

            return AnyView(
                ReportPage(pageNumber: index + 1, of: pageCount, model: model) {
                    VStack(alignment: .leading, spacing: ReportLayout.sectionSpacing) {
                        if index == 0, let quality = model.quality {
                            DataQualitySection(quality: quality, theme: .print)
                        }

                        ForEach(pageSpecs) { spec in
                            ChartSection(spec: spec, theme: .print)
                        }
                    }
                }
            )
        }
    }

    static var pageCount: Int { ReportSections.pageGroups.count }

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
        ReportSections.headerSubtitle(for: model)
    }
}
