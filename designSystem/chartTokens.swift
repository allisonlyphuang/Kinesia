import SwiftUI


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

    static let baselineBand = Color.secondaryColor.opacity(0.22)
    static let baselineCenter = Color.secondaryColor

    // MARK: Dose markers

    static let doseTakenStroke = StrokeStyle(lineWidth: 1.5)
    static let doseSkippedStroke = StrokeStyle(lineWidth: 1.5, dash: [4, 3])
    static let doseMarker = Color.textDark            // pine #3A423A

    // MARK: Structure

    static let gridLine = Color(.sRGB, red: 0xE8/255, green: 0xE4/255, blue: 0xDA/255)  // mist
    static let axisLabel = Color.textDark
    static let referenceLine = Color(.sRGB, red: 0xC4/255, green: 0xA7/255, blue: 0x7D/255)  // dusk

    static let annotation = Color.textMedium

    // MARK: Geometry

    static let markSize: CGFloat = 36
    static let lineWidth: CGFloat = 2
    static let whiskerWidth: CGFloat = 1.5
    static let minimumChartHeight: CGFloat = 220
}

nonisolated enum ChartSymbol: String, CaseIterable {
    case circle
    case square
    case triangle
    case diamond
    case cross
}
