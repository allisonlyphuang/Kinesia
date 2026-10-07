import SwiftUI

/// A configuration-driven tracing surface. It intentionally selects no production route or protocol values.
struct DexterityTraceSurface: View {
    let configuration: DexterityTestConfiguration
    let onSequenceFinished: ((DexteritySequence, TimeInterval) -> Void)?
    private let layout: DexterityRouteLayout?
    @StateObject private var model: DexterityTestModel

    init(
        configuration: DexterityTestConfiguration,
        onSequenceFinished: ((DexteritySequence, TimeInterval) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onSequenceFinished = onSequenceFinished
        layout = DexterityRouteLayout(configuration: configuration)
        _model = StateObject(wrappedValue: DexterityTestModel(configuration: configuration))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Trace the path")
                .font(.displayMedium)
                .foregroundStyle(Color.textDark)

            Text("Start at the first point and trace the path without lifting your finger.")
                .font(.body)
                .foregroundStyle(Color.textDark)
                .fixedSize(horizontal: false, vertical: true)

            if let layout {
                tracingSurface(layout: layout)
                stateFeedback
            } else {
                unavailableContent
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgPrimaryColor.ignoresSafeArea())
        .onChange(of: model.latestSequence) { sequence in
            guard let sequence, let monotonicStartedAt = model.monotonicStartedAt else {
                return
            }
            onSequenceFinished?(sequence, monotonicStartedAt)
        }
    }

    private func tracingSurface(layout: DexterityRouteLayout) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                .fill(Color.bgSecondaryColor)

            routePath(points: layout.localRoutePoints)
                .stroke(Color.secondaryColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)

            ForEach(Array(layout.localRoutePoints.enumerated()), id: \.offset) { index, point in
                targetMarker(index: index, point: point, radius: layout.localTargetRadius)
                    .position(x: point.x, y: point.y)
                    .allowsHitTesting(false)
            }

            tracePath(points: model.currentTracePoints)
                .stroke(Color.accentBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)

            DexterityCaptureView(
                isCaptureActive: isCaptureActive,
                onEvent: model.handle
            )
            .background(Color.clear)
            .accessibilityHidden(true)
        }
        .frame(width: layout.captureWidth, height: layout.captureHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dexterity tracing area")
        .accessibilityHint("Start at point 1, then trace each numbered point in order.")
    }

    private func routePath(points: [DexterityRoutePoint]) -> Path {
        Path { path in
            guard let first = points.first else {
                return
            }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
        }
    }

    private func tracePath(points: [DexterityTracePoint]) -> Path {
        Path { path in
            guard let first = points.first else {
                return
            }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
        }
    }

    private func targetMarker(index: Int, point: DexterityRoutePoint, radius: Double) -> some View {
        let style = markerStyle(for: index)
        return ZStack {
            Circle()
                .fill(style.fill)
            Circle()
                .stroke(style.stroke, lineWidth: style.lineWidth)
            Text("\(index + 1)")
                .font(.label)
                .foregroundStyle(style.text)
                .accessibilityHidden(true)
        }
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityLabel(markerAccessibilityLabel(for: index))
    }

    private func markerStyle(for index: Int) -> MarkerStyle {
        if index == 0 {
            return MarkerStyle(fill: Color.primaryColor, stroke: Color.textLight, text: Color.textLight, lineWidth: 2)
        }
        if let nextTargetIndex = model.nextTargetIndex, index < nextTargetIndex {
            return MarkerStyle(fill: Color.secondaryColor, stroke: Color.textDark, text: Color.textDark, lineWidth: 2)
        }
        if model.nextTargetIndex == index {
            return MarkerStyle(fill: Color.accentBlue, stroke: Color.textDark, text: Color.textDark, lineWidth: 4)
        }
        return MarkerStyle(fill: Color.bgPrimaryColor, stroke: Color.textMedium, text: Color.textDark, lineWidth: 2)
    }

    private func markerAccessibilityLabel(for index: Int) -> String {
        if index == 0 {
            return "Point 1, starting point"
        }
        if let nextTargetIndex = model.nextTargetIndex, index < nextTargetIndex {
            return "Point \(index + 1), reached"
        }
        if model.nextTargetIndex == index {
            return "Point \(index + 1), next target"
        }
        return "Point \(index + 1), future target"
    }

    @ViewBuilder
    private var stateFeedback: some View {
        Group {
            switch model.phase {
            case .ready:
                Text("Start at the highlighted point")
            case .tracing:
                Text("Keep tracing the path")
            case .completed:
                Text("Path complete")
            case .ended:
                Text("Trace ended")
            case .configurationInvalid:
                Text("This tracing surface is unavailable.")
            }
        }
        .font(.subheading)
        .foregroundStyle(Color.textDark)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var unavailableContent: some View {
        Text("This tracing surface is unavailable.")
            .font(.body)
            .foregroundStyle(Color.textDark)
    }

    private var isCaptureActive: Bool {
        switch model.phase {
        case .ready, .tracing:
            return true
        case .completed, .ended, .configurationInvalid:
            return false
        }
    }

    private struct MarkerStyle {
        let fill: Color
        let stroke: Color
        let text: Color
        let lineWidth: CGFloat
    }
}

#Preview("Dexterity trace surface") {
    DexterityTraceSurface(
        configuration: DexterityTestConfiguration(
            route: DexterityRoute(
                identifier: "preview-only-route",
                version: 1,
                points: [
                    .init(x: 30, y: 60),
                    .init(x: 150, y: 60),
                    .init(x: 150, y: 180),
                    .init(x: 260, y: 180)
                ]
            ),
            coordinateSpace: DexterityCoordinateSpace(
                captureWidth: 300,
                captureHeight: 240,
                scale: 1,
                offsetX: 0,
                offsetY: 0
            ),
            targetRadius: 18
        )
    )
}
