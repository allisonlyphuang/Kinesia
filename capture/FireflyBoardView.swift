//
//  FireflyBoardView.swift
//  Kinesia
//
//  Created by Allison Huang on 9/20/26.
//

// draws the character at the home base and the firefly
// makes hte firefly appear in one frame and reports the timestamp of that frame
// watches for touches and reports 4 kinds of events using hardware timestamps
// tells hits from misses using positions/geometry

import SwiftUI
import UIKit

// Board layout build
nonisolated struct FireflyBoardGeometry: Equatable {
    var center: TapPoint
    var homeBaseRadius: Double
    var fireflyRadius: Double
}

// where a touch landed based on position
enum BoardTouchKind: Equatable {
    case home
    case firefly
    case elsewhere
}

// why the touch is not at home
enum HomeLiftReason: Equatable {
    case lifted // finger left the glass
    case draggedOut // finger slid out of the home radius
    case cancelled // ios took away the touch
}

struct FireflyBoardAppearance: Equatable {
    var boardFill: UIColor
    var jarFill: UIColor
    /// Whatever the board is, this has to be the thing on it that is hardest to miss.
    var fireflyFill: UIColor

    /// The board is white, like every other play surface in the app, so the firefly is the dark
    /// mark on it rather than the bright one. What matters to the measurement is contrast, not
    /// which way round it runs: a cue that takes longer to notice lengthens the reaction time it
    /// is supposed to measure.
    static let `default` = FireflyBoardAppearance(
        boardFill: .kinesiaAsset("cream", fallback: (0xFF, 0xFD, 0xF8)),
        jarFill: .kinesiaAsset("sage", fallback: (0xA8, 0xB3, 0xA0)),
        fireflyFill: .kinesiaAsset("pine", fallback: (0x3A, 0x42, 0x3A))
    )
}

private extension UIColor {
    static func kinesiaAsset(_ name: String, fallback: (CGFloat, CGFloat, CGFloat)) -> UIColor {
        UIColor(named: name) ?? UIColor(
            red: fallback.0 / 255,
            green: fallback.1 / 255,
            blue: fallback.2 / 255,
            alpha: 1
        )
    }
}



final class FireflyBoard: UIView {
    var onTouchDown: ((BoardTouchKind, TimeInterval, CGPoint) -> Void)?
    var onHomeTouchUp: ((HomeLiftReason, TimeInterval) -> Void)?
    var onCueDisplayed: ((TimeInterval) -> Void)?
    var onFrameClockReady: ((Double) -> Void)? // reports refresh rate in Hz
    
    // layout
    private var geometry = FireflyBoardGeometry(center: TapPoint(x: 0, y: 0), homeBaseRadius: 1, fireflyRadius: 1)
    private var isCaptureActive = false
    
    // firefly command, nil = hidden
    private var requestedSpawn: TapPoint?
    private var pendingSpawn: TapPoint?
    private var visibleSpawn: TapPoint?
    
    // touch identity
    private var homeTouch: UITouch?
    private var dragTouch: UITouch?
    
    private var displayLink: CADisplayLink?
    
    private let characterView = UIImageView() // CALayer has implicit animations that cause delay, UIImageView does not
    private let fireflyView = UIImageView()

    var appearance: FireflyBoardAppearance = .default {
        didSet { applyAppearance() }
    }
    
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        isMultipleTouchEnabled = true      //  catching finger may not be the resting thumb
        isAccessibilityElement = false     // the SwiftUI container carries the label
        addSubview(characterView)
        addSubview(fireflyView)
        fireflyView.isHidden = true
        applyAppearance()
    }

    private func applyAppearance() {
        backgroundColor = appearance.boardFill
        apply(artNamed: GameArtName.jar, to: characterView, plainFill: appearance.jarFill)
        apply(artNamed: GameArtName.firefly, to: fireflyView, plainFill: appearance.fireflyFill)
    }

    /// The jar and the firefly are plain circles until their art is in the asset catalogue. This
    /// is the UIKit half of what `ArtImage` does for the SwiftUI games: adding the file to
    /// gameJar.imageset is the whole substitution.
    ///
    /// The image is set here and not when the firefly spawns. A spawn only moves the view and
    /// unhides it, so the cue still appears in a single frame.
    private func apply(artNamed name: String, to view: UIImageView, plainFill: UIColor) {
        let art = UIImage(named: name)
        view.image = art
        view.contentMode = .scaleAspectFit
        view.backgroundColor = art == nil ? plainFill : .clear
        // Both are circles, drawn and measured as circles. The mask stays on with art in place:
        // art that carries its own background would otherwise show as a square on the board.
        view.layer.masksToBounds = true
    }
    deinit {
        displayLink?.invalidate()
    }
    
    func configure(
        geometry: FireflyBoardGeometry,
        isCaptureActive: Bool,
        fireflyAt: TapPoint?,
        onTouchDown: @escaping (BoardTouchKind, TimeInterval, CGPoint) -> Void,
        onHomeTouchUp: @escaping (HomeLiftReason, TimeInterval) -> Void,
        onCueDisplayed: @escaping (TimeInterval) -> Void,
        onFrameClockReady: @escaping (Double) -> Void
    ) {
        self.onTouchDown = onTouchDown
        self.onHomeTouchUp = onHomeTouchUp
        self.onCueDisplayed = onCueDisplayed
        self.onFrameClockReady = onFrameClockReady
        self.isCaptureActive = isCaptureActive
        
        if geometry != self.geometry {
            self.geometry = geometry
            layoutCharacter()
        }
        
        if fireflyAt != requestedSpawn {
            requestedSpawn = fireflyAt
            // if fireflyAt exists,
            if let point = fireflyAt {
                pendingSpawn = point
            } else {
                pendingSpawn = nil
                hideFirefly()
            }
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            startFrameClock(on: window.screen)
        } else {
            stopFrameClock()
        }
    }
    
    private func startFrameClock(on screen: UIScreen) {
        stopFrameClock()
        let link = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        let maxFPS = Float(screen.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: maxFPS, preferred: maxFPS)
        link.add(to: .main, forMode: .common) // .common so it keeps ticking during scrolling/gestures
        displayLink = link
        onFrameClockReady?(Double(screen.maximumFramesPerSecond))
        
    }
    
    private func stopFrameClock() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func frameTick(_ link: CADisplayLink) {
        presentPendingSpawn(at: link.targetTimestamp)
    }
    
    func presentPendingSpawn(at targetTimestamp: TimeInterval) {
        guard let point = pendingSpawn else { return }
        pendingSpawn = nil
        fireflyView.center = CGPoint(x: point.x, y: point.y)
        fireflyView.isHidden = false
        visibleSpawn = point
        onCueDisplayed?(targetTimestamp)
    }
    
    private func hideFirefly() {
        fireflyView.isHidden = true
        visibleSpawn = nil
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isCaptureActive else { return }
        for touch in touches {
            let location = touch.location(in: self)
            let kind = Self.classify(location, geometry: geometry, fireflyAt: visibleSpawn)
            if kind == .home, homeTouch == nil {
                homeTouch = touch
            }
            onTouchDown?(kind, touch.timestamp, location)
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == homeTouch {
                homeTouch = nil
                onHomeTouchUp?(.lifted, touch.timestamp)
            }
            else if touch == dragTouch {
                dragTouch = nil
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == homeTouch {
                homeTouch = nil
                onHomeTouchUp?(.cancelled, touch.timestamp)
            }
            else if touch == dragTouch {
                dragTouch = nil
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            if touch == homeTouch,
               !FireflyBoard.isWithin(location, of: geometry.center, radius: geometry.homeBaseRadius) {
                homeTouch = nil
                dragTouch = touch
                onHomeTouchUp?(.draggedOut, touch.timestamp)
            }
            else if touch == dragTouch,
                    let spawn = visibleSpawn,
                    Self.isWithin(location, of: spawn, radius: geometry.fireflyRadius) {
                dragTouch = nil
                onTouchDown?(.firefly, touch.timestamp, location)
            }
        }
    }
    
    static func isWithin(_ point: CGPoint, of center: TapPoint, radius: Double) -> Bool {
        guard radius.isFinite, radius >= 0,
              point.x.isFinite, point.y.isFinite,
              center.x.isFinite, center.y.isFinite else { return false }
        let dx = Double(point.x) - center.x
        let dy = Double(point.y) - center.y
        return (dx * dx + dy * dy) <= radius * radius
    }

    static func classify(_ point: CGPoint, geometry: FireflyBoardGeometry, fireflyAt: TapPoint?) -> BoardTouchKind {
        if let fireflyAt, isWithin(point, of: fireflyAt, radius: geometry.fireflyRadius) {
            return .firefly
        }
        if isWithin(point, of: geometry.center, radius: geometry.homeBaseRadius) {
            return .home
        }
        return .elsewhere
    }

    
    // sizes & corner rounding to turn it into a circle
    // whether the circle is clipped is decided in applyAppearance, which knows if art is in use

    private func layoutCharacter() {
        let d = CGFloat(geometry.homeBaseRadius * 2)
        characterView.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        characterView.center = CGPoint(x: geometry.center.x, y: geometry.center.y)
        characterView.layer.cornerRadius = d / 2

        let f = CGFloat(geometry.fireflyRadius * 2)
        fireflyView.bounds = CGRect(x: 0, y: 0, width: f, height: f)
        fireflyView.layer.cornerRadius = f / 2
    }
}

struct FireflyBoardView: UIViewRepresentable {
    var geometry: FireflyBoardGeometry
    var isCaptureActive: Bool
    var fireflyAt: TapPoint?
    var onTouchDown: (BoardTouchKind, TimeInterval, CGPoint) -> Void
    var onHomeTouchUp: (HomeLiftReason, TimeInterval) -> Void
    var onCueDisplayed: (TimeInterval) -> Void
    var onFrameClockReady: (Double) -> Void

    func makeUIView(context: Context) -> FireflyBoard {
        let board = FireflyBoard(frame: .zero)
        apply(to: board)
        return board
    }

    func updateUIView(_ board: FireflyBoard, context: Context) {
        apply(to: board)
    }

    private func apply(to board: FireflyBoard) {
        board.configure(
            geometry: geometry,
            isCaptureActive: isCaptureActive,
            fireflyAt: fireflyAt,
            onTouchDown: onTouchDown,
            onHomeTouchUp: onHomeTouchUp,
            onCueDisplayed: onCueDisplayed,
            onFrameClockReady: onFrameClockReady
        )
    }
}





