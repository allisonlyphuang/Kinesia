import SwiftUI
import Charts


nonisolated enum ChartTokens {

    // MARK: Series

    static func handColor(_ hand: CurrentHand) -> Color {
        switch hand {
        case .right: return .primaryColor      // moss  #576155
        case .left:  return .accentBlue        // pond  #7C99A6
        }
    }

    static func handSymbol(_ hand: CurrentHand) -> ChartSymbol {
        switch hand {
        case .right: return .circle
        case .left:  return .triangle
        }
    }

    // MARK: Baseline

    static let baselineBand = Color.secondaryColor.opacity(0.2)
    static let baselineCenter = Color.secondaryColor

    // MARK: Dose markers

    static let doseTakenStroke = StrokeStyle(lineWidth: 0.9)
    static let doseSkippedStroke = StrokeStyle(lineWidth: 0.9, dash: [3, 2.5])
    static let doseMarker = Color.textDark            // pine #3A423A

    // MARK: Structure

    static let gridLine = Color(.sRGB, red: 0xE8/255, green: 0xE4/255, blue: 0xDA/255)  // mist
    static let majorGridLine = Color(.sRGB, red: 0xC9/255, green: 0xC3/255, blue: 0xB4/255)
    static let axisLine = Color.textDark
    static let axisLabel = Color.textDark
    static let referenceLine = Color(.sRGB, red: 0xC4/255, green: 0xA7/255, blue: 0x7D/255)  // dusk

    static let annotation = Color.textMedium

    // MARK: Geometry

    /// Swift Charts symbol size is an area, so these are smaller than they look.
    static let markSize: CGFloat = 18
    static let medianMarkSize: CGFloat = 30
    static let lineWidth: CGFloat = 1.2
    static let thinLineWidth: CGFloat = 0.9
    static let whiskerWidth: CGFloat = 0.9
    static let axisLineWidth: CGFloat = 0.9
    static let gridLineWidth: CGFloat = 0.5

    static let chartHeight: CGFloat = 200
    static let shortChartHeight: CGFloat = 170
}

nonisolated enum ChartSymbol: String, CaseIterable {
    case circle
    case square
    case triangle
    case diamond
    case cross

    /// The chart layer maps the token onto a concrete mark, so the design system does not
    /// depend on Swift Charts for its own definitions.
    var shape: BasicChartSymbolShape {
        switch self {
        case .circle: return .circle
        case .square: return .square
        case .triangle: return .triangle
        case .diamond: return .diamond
        case .cross: return .cross
        }
    }
}

/// Where the report is being drawn.
///
/// The app is drawn on cream; a PDF is drawn on white paper. Everything else is shared, so the
/// chart views take a theme rather than existing twice.
nonisolated enum ReportTheme: Equatable, Sendable {
    case screen
    case print

    var background: Color {
        switch self {
        case .screen: return .bgPrimaryColor   // cream
        case .print: return .white
        }
    }

    var isPrint: Bool { self == .print }
}

/// One set of spacing numbers for the whole report, so the side margins are equal on screen
/// and on paper and every section lines up with every other.
nonisolated enum ReportLayout {
    /// Applied once, to the scroll content and to the PDF page. Never per section.
    static let margin: CGFloat = 16
    static let sectionSpacing: CGFloat = 22
    static let titleSpacing: CGFloat = 2
    static let chartSpacing: CGFloat = 12

    /// US Letter at 72 points per inch.
    static let pageSize = CGSize(width: 612, height: 792)
    static let pageMargin: CGFloat = 48
    static var pageContentWidth: CGFloat { pageSize.width - pageMargin * 2 }
}
