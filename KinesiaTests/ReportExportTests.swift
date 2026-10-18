import CoreData
import PDFKit
import SwiftUI
import XCTest
@testable import Kinesia

// The chart views are not unit tested; the derivations carry the logic. These cover the
// things the export can get wrong on its own: page geometry, the white background, the
// footer, and equal margins.
@MainActor
final class ReportExportTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var written: [URL] = []

    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        container = try TestCoreDataStack.makeInMemoryContainer()
        context = container.viewContext
    }

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        context = nil
        container = nil
        super.tearDown()
    }

    private var referenceDay: Date {
        utc.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: referenceDay)!
    }

    private func loadedModel(sessionCount: Int = 5) throws -> ClinicianReportModel {
        // Counting down from 0 rather than a range, so sessionCount 0 is empty instead of
        // building the invalid range 1...0.
        for offset in (0..<sessionCount).map({ -$0 }) {
            let startedAt = utc.date(bySettingHour: 9, minute: 0, second: 0, of: day(offset))!
            let row = TestSession(context: context)
            row.id = UUID()
            row.startedAt = startedAt.timeIntervalSince1970
            row.completedAt = startedAt.addingTimeInterval(300).timeIntervalSince1970
            row.dayStart = day(offset).timeIntervalSince1970

            let tapping = BradykinesiaResult(context: context)
            tapping.id = UUID()
            tapping.hand = "right"
            tapping.timestamp = startedAt.timeIntervalSince1970
            tapping.dayStart = row.dayStart
            tapping.numTaps = 100
            tapping.numCorrectTaps = 90
            tapping.durationSec = 20
            tapping.isValid = true
            tapping.metricsVersion = 1
            tapping.session = row
        }
        try context.save()

        let model = ClinicianReportModel(
            context: context,
            calendar: utc,
            now: { self.utc.date(bySettingHour: 20, minute: 0, second: 0, of: self.day(0))! }
        )
        model.load()
        return model
    }

    private func render(_ model: ClinicianReportModel) throws -> PDFDocument {
        let url = try ReportExport.renderPDF(model: model)
        written.append(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        return try XCTUnwrap(PDFDocument(url: url))
    }

    // MARK: - The file

    func testExportProducesAReadablePDF() throws {
        let document = try render(try loadedModel())
        XCTAssertGreaterThan(document.pageCount, 0)
    }

    func testExportProducesThreePages() throws {
        let document = try render(try loadedModel())
        XCTAssertEqual(document.pageCount, 3)
    }

    func testExportRefusesBeforeAnythingIsLoaded() {
        let model = ClinicianReportModel(context: context, calendar: utc)
        XCTAssertThrowsError(try ReportExport.renderPDF(model: model)) { error in
            XCTAssertEqual(error as? ReportExportError, .nothingToRender)
        }
    }

    func testAnEmptyWindowStillExports() throws {
        let document = try render(try loadedModel(sessionCount: 0))
        XCTAssertEqual(document.pageCount, 3)
    }

    // MARK: - Page geometry

    func testEveryPageIsUSLetter() throws {
        let document = try render(try loadedModel())

        for index in 0..<document.pageCount {
            let bounds = try XCTUnwrap(document.page(at: index)).bounds(for: .mediaBox)
            XCTAssertEqual(bounds.width, ReportLayout.pageSize.width, accuracy: 0.5, "page \(index + 1)")
            XCTAssertEqual(bounds.height, ReportLayout.pageSize.height, accuracy: 0.5, "page \(index + 1)")
        }
    }

    // The margin is one number used on all four sides, so left and right cannot drift apart.
    func testTheSideMarginsAreEqual() {
        let contentWidth = ReportLayout.pageContentWidth
        let leftover = ReportLayout.pageSize.width - contentWidth
        XCTAssertEqual(leftover / 2, ReportLayout.pageMargin, accuracy: 0.001)
    }

    func testTheContentWidthLeavesRoomForBothMargins() {
        XCTAssertEqual(
            ReportLayout.pageContentWidth + ReportLayout.pageMargin * 2,
            ReportLayout.pageSize.width,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(ReportLayout.pageContentWidth, 0)
    }

    // MARK: - What the page says

    // The regulatory guidance asks for this on every page, so the page template draws it
    // rather than each chart remembering to.
    func testEveryPageCarriesTheDisclaimer() throws {
        let document = try render(try loadedModel())

        for index in 0..<document.pageCount {
            let text = try XCTUnwrap(document.page(at: index)).string ?? ""
            XCTAssertTrue(
                text.contains("Not a diagnostic tool"),
                "page \(index + 1) does not carry the disclaimer"
            )
        }
    }

    func testEveryPageIsNumbered() throws {
        let document = try render(try loadedModel())

        for index in 0..<document.pageCount {
            let text = try XCTUnwrap(document.page(at: index)).string ?? ""
            XCTAssertTrue(text.contains("Page \(index + 1) of 3"), "page \(index + 1) is not numbered")
        }
    }

    func testThePagesNameTheTaskNotTheSymptom() throws {
        let document = try render(try loadedModel())
        let banned = ["bradykinesia", "akinesia", "dexterity", "severity"]

        for index in 0..<document.pageCount {
            let text = (try XCTUnwrap(document.page(at: index)).string ?? "").lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "page \(index + 1) contains \"\(word)\"")
            }
        }
    }

    func testTheFirstPageCarriesTheDateRange() throws {
        let document = try render(try loadedModel())
        let text = try XCTUnwrap(document.page(at: 0)).string ?? ""
        XCTAssertTrue(text.contains("Movement report"))
        XCTAssertTrue(text.contains("check-ins"))
    }

    // MARK: - The background

    // Paper is white, not the app's cream.
    func testThePrintThemeIsWhiteAndTheScreenThemeIsNot() {
        XCTAssertEqual(ReportTheme.print.background, Color.white)
        XCTAssertNotEqual(ReportTheme.screen.background, Color.white)
        XCTAssertTrue(ReportTheme.print.isPrint)
        XCTAssertFalse(ReportTheme.screen.isPrint)
    }

    func testTheRenderedPageIsWhiteInsideItsMargin() throws {
        let document = try render(try loadedModel())
        let page = try XCTUnwrap(document.page(at: 0))
        let image = page.thumbnail(of: CGSize(width: 120, height: 155), for: .mediaBox)
        let cgImage = try XCTUnwrap(image.cgImage)

        // A few points in from each corner, which is margin on every page.
        for point in [CGPoint(x: 3, y: 3), CGPoint(x: 116, y: 3), CGPoint(x: 3, y: 151)] {
            let pixel = try XCTUnwrap(colorAt(point, in: cgImage))
            XCTAssertEqual(pixel.red, 1, accuracy: 0.04, "\(point)")
            XCTAssertEqual(pixel.green, 1, accuracy: 0.04, "\(point)")
            XCTAssertEqual(pixel.blue, 1, accuracy: 0.04, "\(point)")
        }
    }

    /// Samples one pixel by drawing it into a 1x1 buffer.
    private func colorAt(_ point: CGPoint, in image: CGImage) -> (red: Double, green: Double, blue: Double)? {
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(
            image,
            in: CGRect(x: -point.x, y: -(CGFloat(image.height) - point.y - 1), width: CGFloat(image.width), height: CGFloat(image.height))
        )
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}
