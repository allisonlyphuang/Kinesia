import SwiftUI

struct DataQualitySection: View {
    let quality: DataQuality
    var theme: ReportTheme = .screen

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Data in this report")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.textDark)

            VStack(spacing: 0) {
                row("Check-ins completed", "\(quality.daysWithSessions) of \(quality.daysInWindow) days")
                row("Days with logged dose", "\(quality.daysWithAtLeastOneDoseLogged) of \(quality.daysInWindow) days")
                row("Baseline", baselineText)
                row("Readings left out", "\(quality.excludedSessions.count)", isLast: !quality.definitionChanged)
                if quality.definitionChanged {
                    row("Measurement changed", "see below", isLast: true)
                }
            }
            .padding(.top, 8)

            if quality.isSparse {
                caption("Fewer than 5 days have a check-in")
            }

            ForEach(exclusionLines, id: \.self) { line in
                caption(line)
            }

            if quality.daysWithoutSessions > 0 {
                caption("\(ReportFormat.count(quality.daysWithoutSessions, "day")) of \(quality.daysInWindow) have no check-in and are shown as no data")
            }

            if quality.definitionChanged {
                caption("A measurement calculation changed within this date range")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Several readings on one day can fail for the same reason. One line each reads as a
    // duplicate, so identical ones are counted instead.
    private var exclusionLines: [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]

        for excluded in quality.excludedSessions {
            let key = "\(excluded.date.formatted(ReportFormat.dayMonth)), \(excluded.task.lowercased()), \(excluded.hand.rawValue) hand|\(excluded.reason)"
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }

        return order.map { key in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let number = counts[key] ?? 1
            let readings = number == 1 ? "" : " \(ReportFormat.count(number, "reading"))."
            return "\(parts[0]).\(readings) \(parts[1].capitalizedFirst)."
        }
    }

    private var baselineText: String {
        switch quality.baselineState {
        case .familiarization(let day, let total):
            return "Familiarization, day \(day) of \(total)"
        case .building(let day, let total):
            return "Building baseline, day \(day) of \(total)"
        case .established(let baseline):
            return "Set \(baseline.establishedOn.formatted(ReportFormat.dayMonth)), \(baseline.dayCount) days"
        }
    }

    private func row(_ label: String, _ value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                Spacer(minLength: 12)
                Text(value)
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.textDark)
            .padding(.vertical, 7)

            if !isLast {
                Rectangle()
                    .fill(ChartTokens.gridLine)
                    .frame(height: 1)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.textMedium)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
