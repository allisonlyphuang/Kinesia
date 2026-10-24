import UIKit
import XCTest
@testable import Kinesia

/// Covers the parts of `FireflyBoard` that can be driven without a real finger:
/// the pure geometry helpers, the spawn arm-and-present logic behind `configure` /
/// `presentPendingSpawn`, character layout, and the frame clock's attach/detach.
///
/// The `touches*` overrides are deliberately not unit-tested: `UITouch` cannot be
/// constructed with a location, and each override is a few lines that the manual
/// simulator checklist exercises directly.
@MainActor
final class FireflyBoardTests: XCTestCase {

    // Fixtures

    /// A 300×300 board with the character in the middle. Ring radius 100 keeps every
    /// spawn point clear of the home circle (100 − 30 > 40).
    private let geometry = FireflyBoardGeometry(
        center: TapPoint(x: 150, y: 150),
        homeBaseRadius: 40,
        fireflyRadius: 30
    )
    private let spawnAbove = TapPoint(x: 150, y: 50)
    private let spawnRight = TapPoint(x: 250, y: 150)

    /// Collects every callback the board makes so a test can assert on exact call counts.
    private final class EventRecorder {
        var touchDowns: [(kind: BoardTouchKind, t: TimeInterval, location: CGPoint)] = []
        var homeLifts: [(reason: HomeLiftReason, t: TimeInterval)] = []
        var cueOnsets: [TimeInterval] = []
        var frameClockRates: [Double] = []
    }

    private func makeBoard() -> FireflyBoard {
        FireflyBoard(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    }

    /// Mirrors what `FireflyBoardView.updateUIView` does on every SwiftUI redraw.
    private func configure(
        _ board: FireflyBoard,
        geometry: FireflyBoardGeometry? = nil,
        isCaptureActive: Bool = true,
        fireflyAt: TapPoint?,
        recorder: EventRecorder
    ) {
        board.configure(
            geometry: geometry ?? self.geometry,
            isCaptureActive: isCaptureActive,
            fireflyAt: fireflyAt,
            onTouchDown: { recorder.touchDowns.append(($0, $1, $2)) },
            onHomeTouchUp: { recorder.homeLifts.append(($0, $1)) },
            onCueDisplayed: { recorder.cueOnsets.append($0) },
            onFrameClockReady: { recorder.frameClockRates.append($0) }
        )
    }

    /// `FireflyBoard.commonInit` adds the character view first and the firefly view
    /// second, so the firefly is always the last subview.
    private func fireflyView(of board: FireflyBoard) throws -> UIImageView {
        try XCTUnwrap(board.subviews.last as? UIImageView, "firefly view should be the last subview")
    }

    private func characterView(of board: FireflyBoard) throws -> UIImageView {
        try XCTUnwrap(board.subviews.first as? UIImageView, "character view should be the first subview")
    }

    /// A window to attach the board to so `didMoveToWindow` runs and the display link starts.
    /// The test host is the Kinesia app, so a window scene always exists.
    private func makeWindow() throws -> UIWindow {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "test host has no window scene"
        )
        return UIWindow(windowScene: scene)
    }

    // isWithin: testing correct evaluation of where the finger taps

    func testIsWithinIncludesTheCenterAndTheBoundary() {
        let center = TapPoint(x: 0, y: 0)

        XCTAssertTrue(FireflyBoard.isWithin(CGPoint(x: 0, y: 0), of: center, radius: 5))
        // 3-4-5 triangle: exactly on the boundary counts as inside.
        XCTAssertTrue(FireflyBoard.isWithin(CGPoint(x: 3, y: 4), of: center, radius: 5))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: 3, y: 4.001), of: center, radius: 5))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: -5.01, y: 0), of: center, radius: 5))
    }

    func testIsWithinWithZeroRadiusAcceptsOnlyTheExactCenter() {
        let center = TapPoint(x: 10, y: 10)

        XCTAssertTrue(FireflyBoard.isWithin(CGPoint(x: 10, y: 10), of: center, radius: 0))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: 10.0001, y: 10), of: center, radius: 0))
    }

    func testIsWithinRejectsNonFiniteInputsAndInvalidRadii() {
        let center = TapPoint(x: 0, y: 0)

        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: CGFloat.nan, y: 0), of: center, radius: 5))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: 0, y: CGFloat.infinity), of: center, radius: 5))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: 0, y: 0), of: TapPoint(x: .nan, y: 0), radius: 5))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: 0, y: 0), of: center, radius: -1))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: 0, y: 0), of: center, radius: .infinity))
        XCTAssertFalse(FireflyBoard.isWithin(CGPoint(x: 0, y: 0), of: center, radius: .nan))
    }

    // classify: testing tap classification

    func testClassifyWithFireflyHiddenSeesOnlyHomeAndElsewhere() {
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 150, y: 150), geometry: geometry, fireflyAt: nil), .home)
        // Boundary of the home circle.
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 190, y: 150), geometry: geometry, fireflyAt: nil), .home)
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 190.5, y: 150), geometry: geometry, fireflyAt: nil), .elsewhere)
        // Where a firefly *would* be is still "elsewhere" while nothing is shown.
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 150, y: 50), geometry: geometry, fireflyAt: nil), .elsewhere)
    }

    func testClassifyWithFireflyVisibleReportsCatchesInsideItsRadius() {
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 150, y: 50), geometry: geometry, fireflyAt: spawnAbove), .firefly)
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 150, y: 80), geometry: geometry, fireflyAt: spawnAbove), .firefly)
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 150, y: 80.5), geometry: geometry, fireflyAt: spawnAbove), .elsewhere)
        // Home base is unaffected by a visible firefly elsewhere.
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 150, y: 150), geometry: geometry, fireflyAt: spawnAbove), .home)
    }

    func testClassifyPrefersTheFireflyWhenCirclesOverlap() {
        // Misconfigured geometry: firefly spawned inside the home circle. A point in both
        // must classify as a catch, never as a phantom home touch.
        let overlapping = TapPoint(x: 160, y: 150)
        XCTAssertEqual(FireflyBoard.classify(CGPoint(x: 155, y: 150), geometry: geometry, fireflyAt: overlapping), .firefly)
    }

    // spawn presentation: testing firefly spawning position and timing

    func testPresentingWithNothingPendingDoesNothing() throws {
        let board = makeBoard()
        let recorder = EventRecorder()
        configure(board, fireflyAt: nil, recorder: recorder)

        board.presentPendingSpawn(at: 1)

        XCTAssertTrue(recorder.cueOnsets.isEmpty)
        XCTAssertTrue(try fireflyView(of: board).isHidden)
    }

    func testConfiguringASpawnArmsItAndTheNextFramePresentsItExactlyOnce() throws {
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, fireflyAt: spawnAbove, recorder: recorder)

        // Armed but not yet on screen: nothing is visible and no onset has been reported.
        XCTAssertTrue(try fireflyView(of: board).isHidden)
        XCTAssertTrue(recorder.cueOnsets.isEmpty)

        board.presentPendingSpawn(at: 42)

        XCTAssertEqual(recorder.cueOnsets, [42])
        let firefly = try fireflyView(of: board)
        XCTAssertFalse(firefly.isHidden)
        XCTAssertEqual(firefly.center, CGPoint(x: 150, y: 50))

        // A later frame with nothing new pending must not report a second onset.
        board.presentPendingSpawn(at: 43)
        XCTAssertEqual(recorder.cueOnsets, [42])
    }

    func testRepeatedConfigureWithTheSameSpawnDoesNotRearm() {
        // SwiftUI calls updateUIView on every redraw with the same fireflyAt value.
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, fireflyAt: spawnAbove, recorder: recorder)
        board.presentPendingSpawn(at: 42)

        for _ in 0..<3 {
            configure(board, fireflyAt: spawnAbove, recorder: recorder)
        }
        board.presentPendingSpawn(at: 50)

        XCTAssertEqual(recorder.cueOnsets, [42])
    }

    func testLatestSpawnWinsWhenReconfiguredBeforeTheFrame() throws {
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, fireflyAt: spawnAbove, recorder: recorder)
        configure(board, fireflyAt: spawnRight, recorder: recorder)
        board.presentPendingSpawn(at: 42)

        XCTAssertEqual(recorder.cueOnsets, [42])
        XCTAssertEqual(try fireflyView(of: board).center, CGPoint(x: 250, y: 150))
    }

    func testConfiguringNilBeforeTheFrameCancelsThePendingSpawn() throws {
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, fireflyAt: spawnAbove, recorder: recorder)
        configure(board, fireflyAt: nil, recorder: recorder)
        board.presentPendingSpawn(at: 42)

        XCTAssertTrue(recorder.cueOnsets.isEmpty)
        XCTAssertTrue(try fireflyView(of: board).isHidden)
    }

    func testConfiguringNilHidesAVisibleFireflyImmediately() throws {
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, fireflyAt: spawnAbove, recorder: recorder)
        board.presentPendingSpawn(at: 42)
        XCTAssertFalse(try fireflyView(of: board).isHidden)

        configure(board, fireflyAt: nil, recorder: recorder)

        // Hiding does not wait for a frame and is never reported as an onset.
        XCTAssertTrue(try fireflyView(of: board).isHidden)
        board.presentPendingSpawn(at: 43)
        XCTAssertEqual(recorder.cueOnsets, [42])
    }

    func testTheSameSpawnPointCanBePresentedAgainAfterHiding() {
        // A fixed-spawn layout produces identical coordinates every round; nil in between
        // is what makes the second request distinguishable from a redraw.
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, fireflyAt: spawnAbove, recorder: recorder)
        board.presentPendingSpawn(at: 42)
        configure(board, fireflyAt: nil, recorder: recorder)
        configure(board, fireflyAt: spawnAbove, recorder: recorder)
        board.presentPendingSpawn(at: 60)

        XCTAssertEqual(recorder.cueOnsets, [42, 60])
    }

    func testSpawnPresentationIsIndependentOfTheCaptureFlag() throws {
        // isCaptureActive gates touch reporting only; the board shows whatever it is told to.
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, isCaptureActive: false, fireflyAt: spawnAbove, recorder: recorder)
        board.presentPendingSpawn(at: 42)

        XCTAssertEqual(recorder.cueOnsets, [42])
        XCTAssertFalse(try fireflyView(of: board).isHidden)
    }

    func testConfigureReplacesCallbacksSoOnlyTheLatestOwnerIsNotified() {
        // updateUIView hands the board fresh closures on every redraw; stale ones must not fire.
        let board = makeBoard()
        let stale = EventRecorder()
        let current = EventRecorder()

        configure(board, fireflyAt: spawnAbove, recorder: stale)
        configure(board, fireflyAt: spawnAbove, recorder: current)
        board.presentPendingSpawn(at: 42)

        XCTAssertTrue(stale.cueOnsets.isEmpty)
        XCTAssertEqual(current.cueOnsets, [42])
    }

    // Layout: does the geometry/layout render correctly

    func testGeometryPositionsTheCharacterAndSizesBothCircles() throws {
        let board = makeBoard()
        let recorder = EventRecorder()

        configure(board, fireflyAt: nil, recorder: recorder)

        let character = try characterView(of: board)
        XCTAssertEqual(character.center, CGPoint(x: 150, y: 150))
        XCTAssertEqual(character.bounds.size, CGSize(width: 80, height: 80))
        XCTAssertEqual(try fireflyView(of: board).bounds.size, CGSize(width: 60, height: 60))
    }

    func testGeometryChangeRelayoutsTheCharacter() throws {
        let board = makeBoard()
        let recorder = EventRecorder()
        configure(board, fireflyAt: nil, recorder: recorder)

        let moved = FireflyBoardGeometry(
            center: TapPoint(x: 100, y: 120),
            homeBaseRadius: 25,
            fireflyRadius: 22
        )
        configure(board, geometry: moved, fireflyAt: nil, recorder: recorder)

        let character = try characterView(of: board)
        XCTAssertEqual(character.center, CGPoint(x: 100, y: 120))
        XCTAssertEqual(character.bounds.size, CGSize(width: 50, height: 50))
        XCTAssertEqual(try fireflyView(of: board).bounds.size, CGSize(width: 44, height: 44))
    }

    func testFireflyStartsHiddenBeforeAnyConfiguration() throws {
        XCTAssertTrue(try fireflyView(of: makeBoard()).isHidden)
    }

    // Frame clock: screen refresh/frame tick

    func testAttachingToAWindowReportsTheRefreshRateOnce() throws {
        let board = makeBoard()
        let recorder = EventRecorder()
        configure(board, fireflyAt: nil, recorder: recorder)

        let window = try makeWindow()
        window.addSubview(board)

        XCTAssertEqual(recorder.frameClockRates.count, 1)
        let rate = recorder.frameClockRates.first ?? 0
        XCTAssertTrue(rate.isFinite)
        XCTAssertGreaterThanOrEqual(rate, 60, "every iOS display refreshes at 60 Hz or faster")

        // Detaching stops the clock without reporting again.
        board.removeFromSuperview()
        XCTAssertEqual(recorder.frameClockRates.count, 1)
    }

    func testARealDisplayLinkPresentsAPendingSpawnOnTheUptimeClock() throws {
        let board = makeBoard()
        let window = try makeWindow()
        window.addSubview(board)

        let presented = expectation(description: "firefly presented by the display link")
        var onsets: [TimeInterval] = []
        board.configure(
            geometry: geometry,
            isCaptureActive: true,
            fireflyAt: spawnAbove,
            onTouchDown: { _, _, _ in },
            onHomeTouchUp: { _, _ in },
            onCueDisplayed: { t in
                onsets.append(t)
                if onsets.count == 1 { presented.fulfill() }
            },
            onFrameClockReady: { _ in }
        )

        let armedAt = ProcessInfo.processInfo.systemUptime
        wait(for: [presented], timeout: 2)

        XCTAssertEqual(onsets.count, 1)
        let onset = try XCTUnwrap(onsets.first)
        XCTAssertFalse(try fireflyView(of: board).isHidden)

        // targetTimestamp is on the same seconds-since-boot clock as UITouch.timestamp and
        // ProcessInfo.systemUptime, so the two can be subtracted directly. A Date-based
        // value would be ~1.7 billion seconds off; a stale `timestamp` would precede arming.
        XCTAssertGreaterThanOrEqual(onset, armedAt - 0.05)
        XCTAssertLessThan(onset - armedAt, 1.0)

        board.removeFromSuperview()
    }

    // The board originally used bare UIImageViews with no image and no fill, so the jar and the
    // firefly rendered as invisible rectangles. Nothing caught it because every test above checks
    // isHidden and center rather than whether anything is actually drawn. These do.

    func testTheJarAndTheFireflyAreActuallyDrawn() throws {
        let board = makeBoard()
        let recorder = EventRecorder()
        configure(board, fireflyAt: nil, recorder: recorder)

        let jar = try characterView(of: board)
        let firefly = try fireflyView(of: board)

        assertDrawn(jar, "jar")
        assertDrawn(firefly, "firefly")
        XCTAssertNotNil(board.backgroundColor)
    }

    /// An overridden fill applies only where there is no art. Art replaces the fill, so the view
    /// goes clear instead.
    private func assertFill(_ view: UIImageView, _ expected: UIColor, _ name: String) {
        if view.image == nil {
            XCTAssertEqual(view.backgroundColor, expected, "the \(name) fill was not applied")
        } else {
            XCTAssertEqual(view.backgroundColor, .clear, "\(name) art should replace the fill")
        }
    }

    /// Either the art is in the catalogue or the plain fill stands in for it. Neither one and the
    /// view is an invisible rectangle, which is the bug this guards.
    private func assertDrawn(_ view: UIImageView, _ name: String) {
        if view.image != nil { return }
        XCTAssertNotNil(view.backgroundColor, "an unfilled \(name) with no art is invisible")
        XCTAssertNotEqual(view.backgroundColor, .clear, "an unfilled \(name) with no art is invisible")
    }

    func testBothViewsAreRoundedIntoCircles() throws {
        let board = makeBoard()
        let recorder = EventRecorder()
        configure(board, fireflyAt: nil, recorder: recorder)

        // A circle is a square view whose corner radius is half its width.
        let jar = try characterView(of: board)
        XCTAssertEqual(jar.layer.cornerRadius, 40, accuracy: 0.001)
        XCTAssertEqual(jar.bounds.width, 80, accuracy: 0.001)

        let firefly = try fireflyView(of: board)
        XCTAssertEqual(firefly.layer.cornerRadius, 30, accuracy: 0.001)
        XCTAssertEqual(firefly.bounds.width, 60, accuracy: 0.001)
    }

    func testCornerRadiusFollowsAGeometryChange() throws {
        let board = makeBoard()
        let recorder = EventRecorder()
        configure(board, fireflyAt: nil, recorder: recorder)

        let smaller = FireflyBoardGeometry(
            center: TapPoint(x: 100, y: 120),
            homeBaseRadius: 28,
            fireflyRadius: 26
        )
        configure(board, geometry: smaller, fireflyAt: nil, recorder: recorder)

        // Stale radii would leave both views as rounded rectangles rather than circles.
        XCTAssertEqual(try characterView(of: board).layer.cornerRadius, 28, accuracy: 0.001)
        XCTAssertEqual(try fireflyView(of: board).layer.cornerRadius, 26, accuracy: 0.001)
    }

    func testTheFireflyStandsOutMoreThanTheJarDoes() throws {
        // Not a style preference: a low-contrast cue takes longer to notice, which lengthens the
        // measurement and makes it depend on ambient light. This is written as contrast rather
        // than brightness because the board went from pine to cream, and a rule that says the
        // firefly is the lightest thing would have passed an invisible cream firefly on it.
        func luminance(_ color: UIColor?) throws -> CGFloat {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            let converted = try XCTUnwrap(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            XCTAssertTrue(converted, "colour could not be read as RGB")

            func channel(_ value: CGFloat) -> CGFloat {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

        func contrast(_ one: CGFloat, _ other: CGFloat) -> CGFloat {
            let lighter = max(one, other)
            let darker = min(one, other)
            return (lighter + 0.05) / (darker + 0.05)
        }

        let appearance = FireflyBoardAppearance.default
        let board = try luminance(appearance.boardFill)
        let firefly = contrast(try luminance(appearance.fireflyFill), board)
        let jar = contrast(try luminance(appearance.jarFill), board)

        XCTAssertGreaterThan(firefly, jar, "the jar competes with the cue")
        XCTAssertGreaterThan(firefly, 4.5, "the cue is too close to the board to be seen quickly")
    }

    func testAnOverriddenAppearanceIsAppliedImmediately() throws {
        // The SwiftUI screen passes `.clear` for the board once it draws its own backdrop.
        let board = makeBoard()
        let recorder = EventRecorder()
        configure(board, fireflyAt: nil, recorder: recorder)

        board.appearance = FireflyBoardAppearance(
            boardFill: .clear,
            jarFill: .systemRed,
            fireflyFill: .systemYellow
        )

        XCTAssertEqual(board.backgroundColor, .clear)
        assertFill(try characterView(of: board), .systemRed, "jar")
        assertFill(try fireflyView(of: board), .systemYellow, "firefly")
    }
}
