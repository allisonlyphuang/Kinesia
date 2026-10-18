import SwiftUI

// for each chart: the title, line of context, chart,
// legend, caption, and link to method and the readings

struct ChartSection<Content: View>: View {
    let title: String
    let subtitle: String
    var methodLabel: String = "Method and readings"
    var caption: String?
    var legend: [LegendEntry] = []
    var theme: ReportTheme = .screen
    var onMethodTap: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textDark)

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.textMedium)
                .padding(.top, ReportLayout.titleSpacing)

            content()
                .padding(.top, ReportLayout.chartSpacing)

            if !legend.isEmpty {
                ChartLegendRow(entries: legend)
                    .padding(.top, 8)
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMedium)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            // allows clinician to review the basis of any output
            // on paper, these must be printed out
            if !theme.isPrint {
                Button(methodLabel) { onMethodTap?() }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentBlue)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LegendEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case symbol(ChartSymbol)
        case line(dash: [CGFloat])
        case band
    }

    let id = UUID()
    let label: String
    let color: Color
    let kind: Kind

    static func symbol(_ label: String, _ color: Color, _ symbol: ChartSymbol) -> LegendEntry {
        LegendEntry(label: label, color: color, kind: .symbol(symbol))
    }

    static func line(_ label: String, _ color: Color, dash: [CGFloat] = []) -> LegendEntry {
        LegendEntry(label: label, color: color, kind: .line(dash: dash))
    }

    static func band(_ label: String, _ color: Color) -> LegendEntry {
        LegendEntry(label: label, color: color, kind: .band)
    }

    static func == (lhs: LegendEntry, rhs: LegendEntry) -> Bool {
        lhs.label == rhs.label && lhs.kind == rhs.kind
    }
}

struct ChartLegendRow: View {
    let entries: [LegendEntry]

    var body: some View {
        // wrap instead of scroll to accomodate for paper + narrower phones
        FlowLayout(spacing: 14, lineSpacing: 6) {
            ForEach(entries) { entry in
                HStack(spacing: 5) {
                    LegendSwatch(entry: entry)
                    Text(entry.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textDark)
                }
            }
        }
    }
}

private struct LegendSwatch: View {
    let entry: LegendEntry

    var body: some View {
        switch entry.kind {
        case .symbol(let symbol):
            SymbolMark(symbol: symbol, color: entry.color)
                .frame(width: 10, height: 10)
        case .line(let dash):
            Path { path in
                path.move(to: CGPoint(x: 0, y: 4))
                path.addLine(to: CGPoint(x: 18, y: 4))
            }
            .stroke(entry.color, style: StrokeStyle(lineWidth: ChartTokens.lineWidth, dash: dash))
            .frame(width: 18, height: 8)
        case .band:
            Rectangle()
                .fill(entry.color)
                .frame(width: 18, height: 8)
        }
    }
}

struct SymbolMark: View {
    let symbol: ChartSymbol
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            switch symbol {
            case .circle:
                Circle().fill(color)
            case .square:
                Rectangle().fill(color)
            case .diamond:
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                    p.addLine(to: CGPoint(x: w / 2, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h / 2))
                    p.closeSubpath()
                }
                .fill(color)
            case .triangle:
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(color)
            case .cross:
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.move(to: CGPoint(x: w, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: h))
                }
                .stroke(color, lineWidth: 1.4)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in layout(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
