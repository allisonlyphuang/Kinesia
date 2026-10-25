import SwiftUI

/// A configuration-driven tracing surface. It intentionally selects no production route or protocol values.
struct DexterityTraceSurface: View {
    let configuration: DexterityTestConfiguration
    let onSequenceFinished: ((DexteritySequence, TimeInterval) -> Void)?
    let onPhaseChanged: ((DexterityTestModel.Phase) -> Void)?
    private let layout: DexterityRouteLayout?
    @StateObject private var model: DexterityTestModel

    init(
        configuration: DexterityTestConfiguration,
        onSequenceFinished: ((DexteritySequence, TimeInterval) -> Void)? = nil,
        onPhaseChanged: ((DexterityTestModel.Phase) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.onSequenceFinished = onSequenceFinished
        self.onPhaseChanged = onPhaseChanged
        layout = DexterityRouteLayout(configuration: configuration)
        _model = StateObject(wrappedValue: DexterityTestModel(configuration: configuration))
    }

    /// The surface draws the board and the line under it, and nothing else. The screen around it
    /// owns the page, the heading and the instruction: when this view carried its own title and
    /// its own cream background, a patient saw two headings and a card inside a card.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let layout {
                tracingSurface(layout: layout)
                stateFeedback
            } else {
                unavailableContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            onPhaseChanged?(model.phase)
        }
        .onChange(of: model.phase) { _, phase in
            onPhaseChanged?(phase)
        }
        .onChange(of: model.latestSequence) { _, sequence in
            guard let sequence, let monotonicStartedAt = model.monotonicStartedAt else {
                return
            }
            onSequenceFinished?(sequence, monotonicStartedAt)
        }
    }

    private func tracingSurface(layout: DexterityRouteLayout) -> some View {
        ZStack {
            PlaySurface()

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

    /// A route point is a star, one drawing for all of them, so the state of the point cannot be
    /// the colour of the star: a point still to come is the same star faded, and the next one to
    /// reach wears a ring. `fill` and `stroke` are for the drawn star used when there is no art.
    /// The number stays on top either way: it is how the order is read.
    private func targetMarker(index: Int, point: DexterityRoutePoint, radius: Double) -> some View {
        let style = markerStyle(for: index)
        return ZStack {
            if style.isNext {
                Circle()
                    .fill(Color.accentBlue.opacity(0.16))
                    .overlay { Circle().stroke(Color.accentBlue, lineWidth: 3) }
            }

            ArtImage(name: GameArtName.star) {
                StarGlyph(fill: style.fill, stroke: style.stroke, lineWidth: style.lineWidth)
            }
            .opacity(style.opacity)

            Text("\(index + 1)")
                .font(.label)
                .foregroundStyle(GameArtName.hasArt(GameArtName.star) ? Color.textDark : style.text)
                .accessibilityHidden(true)
        }
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityLabel(markerAccessibilityLabel(for: index))
    }

    private func markerStyle(for index: Int) -> MarkerStyle {
        let isNext = Self.highlightedTargetIndex(
            for: model.phase,
            nextTargetIndex: model.nextTargetIndex
        ) == index

        if index == 0 {
            return MarkerStyle(
                fill: Color.primaryColor,
                stroke: Color.textLight,
                text: Color.textLight,
                opacity: 1,
                isNext: isNext,
                lineWidth: 2
            )
        }
        if let nextTargetIndex = model.nextTargetIndex, index < nextTargetIndex {
            return MarkerStyle(
                fill: Color.secondaryColor,
                stroke: Color.textDark,
                text: Color.textDark,
                opacity: 1,
                isNext: false,
                lineWidth: 2
            )
        }
        if isNext {
            return MarkerStyle(
                fill: Color.accentBlue,
                stroke: Color.textDark,
                text: Color.textDark,
                opacity: 1,
                isNext: true,
                lineWidth: 4
            )
        }
        return MarkerStyle(
            fill: Color.bgPrimaryColor,
            stroke: Color.textMedium,
            text: Color.textDark,
            opacity: 0.4,
            isNext: false,
            lineWidth: 2
        )
    }

    static func highlightedTargetIndex(
        for phase: DexterityTestModel.Phase,
        nextTargetIndex: Int?
    ) -> Int? {
        switch phase {
        case .ready:
            return 0
        case .tracing:
            return nextTargetIndex
        case .completed, .ended, .configurationInvalid:
            return nil
        }
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
                Text("Start at the first point")
            case .tracing:
                Text("Keep tracing the path")
            case .completed:
                Text("Constellation complete")
            case .ended:
                Text("Trace ended")
            case .configurationInvalid:
                Text("This tracing surface is unavailable.")
            }
        }
        .font(.subheading)
        .foregroundStyle(Color.textDark)
        .frame(maxWidth: .infinity, alignment: .center)
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
        /// How much of the star is shown. A point still to come is faded.
        let opacity: Double
        /// The point to reach next, which wears a ring.
        let isNext: Bool
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
