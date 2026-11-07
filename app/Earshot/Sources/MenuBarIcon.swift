import AppKit

/// Badge overlay kind for the menu bar icon.
///
/// `String`-backed + `Codable` so the RPC `/state` snapshot can expose the
/// current badge directly (it encodes to the case-name raw value), letting a
/// driver script assert the menu-bar state deterministically instead of
/// pixel-matching a screenshot.
enum BadgeKind: String, CaseIterable, Codable {
    case inactive
    case recording
    case transcribing
    case diarizing
    case processing
    // SwiftFormat strips a redundant `= "userAction"`, which then trips the
    // camel-cased-Codable rule; the implicit rawValue already matches, so
    // disable rather than fight the formatter (same as JobState / AppSettings).
    // swiftlint:disable:next raw_value_for_camel_cased_codable_enum
    case userAction
    case done
    case error
    // swiftlint:disable:next raw_value_for_camel_cased_codable_enum
    case updateAvailable

    /// Whether this badge paints a red mark, which a template image cannot carry.
    var drawsRed: Bool {
        self == .error || self == .recording
    }

    /// Whether this badge kind uses animation.
    var isAnimated: Bool {
        switch self {
        case .recording, .transcribing, .diarizing, .processing: true

        default: false
        }
    }
}

/// Composites the menu bar icon: one ear glyph, the same in every state so it
/// is recognised at a glance, plus a small mark for the state.
/// - `.recording`: a red dot that pulses
/// - `.transcribing` / `.diarizing` / `.processing`: three dots, one lit in turn
/// - `.userAction`: a filled dot
/// - `.error`: a red "!"; `.updateAvailable`: an up arrow
///
/// Rendered as a template image where no red is drawn, so macOS handles light
/// and dark mode. `@MainActor` because cache initialisation and NSApp /
/// NSAppearance reads need the main actor; every call site already is.
@MainActor
enum MenuBarIcon {
    /// Number of distinct animation frames. Pure constant.
    nonisolated static let frameCount = 6

    /// Run-loop mode for the menu-bar animation timer (`AnimatedMenuBarIcon`).
    ///
    /// `.default`, not `.common`: `.common` includes `.eventTracking`, so the
    /// timer would fire while the status-bar menu is tracked and deliver its
    /// `@MainActor` tick from inside that nested run loop — which crashes in the
    /// Swift concurrency executor check (`swift_task_isCurrentExecutor` →
    /// EXC_BAD_ACCESS). Trade-off: the badge animation pauses while a menu is
    /// open (cosmetic, sub-second) and resumes when tracking ends.
    nonisolated static let animationRunLoopMode: RunLoop.Mode = .default

    /// Returns the next animation frame for `badge`, or `current` if `badge`
    /// is non-animated. Static badges (idle, error, …) ignore the timer tick
    /// so the App scene's body does not re-evaluate every 0.4 s. Pure math —
    /// `nonisolated` so it can be called from any context (tests, off-main).
    nonisolated static func nextFrame(_ current: Int, badge: BadgeKind) -> Int {
        guard badge.isAnimated else { return current }
        return (current + 1) % frameCount
    }

    /// The ear, sized to leave the bottom-right corner to the state marks.
    private static let glyph: NSImage? = NSImage(systemSymbolName: "ear", accessibilityDescription: "Earshot")?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))

    // MARK: - Cache

    /// Pre-rendered frames keyed by BadgeKind. Populated once eagerly when
    /// the type is first referenced. The type is `@MainActor`, so the
    /// initialiser runs on MainActor and can safely read NSApp/NSAppearance.
    private static let cache: [BadgeKind: [NSImage]] = {
        var result: [BadgeKind: [NSImage]] = [:]
        for badge in BadgeKind.allCases {
            let count = badge.isAnimated ? frameCount : 1
            result[badge] = (0 ..< count).map { frame in renderImage(badge: badge, frame: frame) }
        }
        return result
    }()

    // MARK: - Public

    /// Returns a pre-rendered 18x18pt `NSImage` for the given badge and animation frame.
    ///
    /// If `permissionOverlay` or `recordOnlyOverlay` is true, a red badge is composited over
    /// the base icon. If `micSilentOverlay` is true, the **top half** of the ear is red —
    /// signalling the mic channel went silent. If `appSilentOverlay` is true, the **bottom
    /// half** is red — signalling the app-audio channel went silent. Any of these bypass the
    /// pre-rendered cache and force a non-template image, because red would not survive
    /// template rendering.
    static func image(
        badge: BadgeKind,
        animationFrame: Int = 0,
        permissionOverlay: Bool = false,
        recordOnlyOverlay: Bool = false,
        micSilentOverlay: Bool = false,
        appSilentOverlay: Bool = false,
    ) -> NSImage {
        // Anything with red in it is drawn in the menu bar's current colour,
        // so it is rendered now rather than cached: a cached one would keep
        // the appearance of launch after a switch to or from dark mode.
        if badge.drawsRed || permissionOverlay || recordOnlyOverlay || micSilentOverlay || appSilentOverlay {
            let frame = badge.isAnimated ? animationFrame : 0
            return renderImage(
                badge: badge, frame: frame,
                permissionOverlay: permissionOverlay,
                recordOnlyOverlay: recordOnlyOverlay,
                micSilentOverlay: micSilentOverlay,
                appSilentOverlay: appSilentOverlay,
            )
        }
        guard let frames = cache[badge] else { return renderImage(badge: badge, frame: animationFrame) }
        return frames[animationFrame % frames.count]
    }

    // MARK: - Rendering

    private static func renderImage(
        badge: BadgeKind,
        frame: Int,
        permissionOverlay: Bool = false,
        recordOnlyOverlay: Bool = false,
        micSilentOverlay: Bool = false,
        appSilentOverlay: Bool = false,
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        // Red marks need an explicit foreground matching the menu bar, because
        // a template image would turn them black or white.
        let needsExplicitForeground = badge.drawsRed
            || permissionOverlay || recordOnlyOverlay || micSilentOverlay || appSilentOverlay
        // Read on the calling (main) thread: the drawing handler may run off-main.
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let foreground: NSColor = needsExplicitForeground && isDark ? .white : .black
        let glyph = glyph
        let image = NSImage(size: size, flipped: false) { rect in
            drawGlyph(glyph, in: rect, color: foreground)
            if micSilentOverlay { drawGlyph(glyph, in: rect, color: .systemRed, clippedTo: .top) }
            if appSilentOverlay { drawGlyph(glyph, in: rect, color: .systemRed, clippedTo: .bottom) }

            foreground.setFill()
            drawStateMark(badge: badge, frame: frame, in: rect)

            // Overlay precedence: permission errors win over record-only because a permission
            // problem actually breaks recording, so the user must see it first.
            if permissionOverlay || badge == .error {
                drawExclamationBadge(in: rect)
            } else if recordOnlyOverlay {
                drawRecordOnlyBadge(in: rect)
            }
            return true
        }
        image.isTemplate = !needsExplicitForeground
        return image
    }

    private enum Half { case top, bottom }

    /// The ear in `color`, shifted up and left to leave the corner to a mark,
    /// optionally only its top or bottom half (the per-channel silence tint).
    nonisolated private static func drawGlyph(_ glyph: NSImage?, in rect: NSRect, color: NSColor, clippedTo half: Half? = nil) {
        guard let glyph, let ctx = NSGraphicsContext.current else { return }
        let glyphRect = NSRect(
            x: (rect.width - glyph.size.width) / 2 - 1,
            y: (rect.height - glyph.size.height) / 2 + 1,
            width: glyph.size.width, height: glyph.size.height,
        )
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }
        if let half {
            let centerY = glyphRect.midY
            let clip = switch half {
            case .top: NSRect(x: 0, y: centerY - 0.5, width: rect.width, height: rect.height - centerY + 0.5)
            case .bottom: NSRect(x: 0, y: 0, width: rect.width, height: centerY + 0.5)
            }
            NSBezierPath(rect: clip).setClip()
        }
        ctx.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        glyph.draw(in: glyphRect)
        color.set()
        glyphRect.fill(using: .sourceIn)
        ctx.cgContext.endTransparencyLayer()
    }

    /// The mark beside the ear that says what the app is doing.
    nonisolated private static func drawStateMark(badge: BadgeKind, frame: Int, in rect: NSRect) {
        switch badge {
        case .recording:
            // Pulses between two sizes.
            let size: CGFloat = frame.isMultiple(of: 2) ? 5.5 : 4.5
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: rect.maxX - 3.5 - size / 2, y: rect.maxY - 3.5 - size / 2, width: size, height: size,
            )).fill()

        case .transcribing, .diarizing, .processing:
            // Three dots in the corner, each lit for two ticks in turn.
            let lit = frame / 2 % 3
            for index in 0 ..< 3 {
                let dot: CGFloat = 2
                let path = NSBezierPath(ovalIn: NSRect(
                    x: rect.maxX - 8.5 + CGFloat(index) * 3, y: rect.minY + 0.5, width: dot, height: dot,
                ))
                if index == lit {
                    path.fill()
                } else {
                    path.lineWidth = 0.6
                    path.stroke()
                }
            }

        case .userAction:
            let size: CGFloat = 5
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - size - 0.5, y: rect.maxY - size - 0.5, width: size, height: size))
                .fill()

        case .updateAvailable:
            drawUpdateArrow(in: rect)

        case .inactive, .done, .error:
            break
        }
    }

    // MARK: - Error Badge (exclamation mark in bottom-right)

    nonisolated private static func drawExclamationBadge(in rect: NSRect) {
        let size: CGFloat = 7.0
        let margin: CGFloat = 0.5
        let cx = rect.maxX - size / 2 - margin
        let cy = rect.minY + size / 2 + margin

        // Red circle
        NSColor.systemRed.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size),
        ).fill()

        // White "!" on top
        NSColor.white.setFill()

        // Stem
        let stemW: CGFloat = 1.3
        let stemH: CGFloat = 2.8
        let stemY = cy + size / 2 - 1.8 - stemH
        NSBezierPath(
            roundedRect: NSRect(x: cx - stemW / 2, y: stemY, width: stemW, height: stemH),
            xRadius: stemW / 2, yRadius: stemW / 2,
        ).fill()

        // Dot
        let dotSize: CGFloat = 1.3
        let dotY = cy - size / 2 + 1.0
        NSBezierPath(ovalIn: NSRect(x: cx - dotSize / 2, y: dotY, width: dotSize, height: dotSize)).fill()
    }

    // MARK: - Record-Only Badge (solid red dot in bottom-right)

    nonisolated private static func drawRecordOnlyBadge(in rect: NSRect) {
        let size: CGFloat = 5.0
        let margin: CGFloat = 0.5
        let cx = rect.maxX - size / 2 - margin
        let cy = rect.minY + size / 2 + margin

        NSColor.systemRed.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size),
        ).fill()
    }

    // MARK: - Update Available (small upward arrow badge in bottom-right)

    nonisolated private static func drawUpdateArrow(in rect: NSRect) {
        let size: CGFloat = 6.0
        let margin: CGFloat = 0.5
        let cx = rect.maxX - size / 2 - margin
        let cy = rect.minY + size / 2 + margin

        // Arrow pointing up: triangle + stem
        let arrow = NSBezierPath()
        // Triangle head
        arrow.move(to: NSPoint(x: cx, y: cy + size / 2)) // top
        arrow.line(to: NSPoint(x: cx - size / 3, y: cy + 0.5)) // bottom-left
        arrow.line(to: NSPoint(x: cx + size / 3, y: cy + 0.5)) // bottom-right
        arrow.close()
        arrow.fill()

        // Stem
        let stemWidth: CGFloat = 1.4
        let stem = NSRect(x: cx - stemWidth / 2, y: cy - size / 3, width: stemWidth, height: size / 2)
        NSBezierPath(roundedRect: stem, xRadius: stemWidth / 2, yRadius: stemWidth / 2).fill()
    }
}

// MARK: - Badge State Logic (pure function, testable without UI)

extension BadgeKind {
    /// Computes the current badge from plain value inputs.
    ///
    /// This is a pure function with no object dependencies — tests can call it
    /// directly with any combination of inputs without driving WatchLoop into states.
    static func compute(
        watchLoopActive: Bool,
        watchLoopState: WatchLoop.State,
        transcriberState: TranscriberState,
        activeJobState: JobState?,
        updateAvailable: Bool,
        permissionProblem: Bool = false,
        consentPending: Bool = false,
    ) -> BadgeKind {
        if watchLoopActive {
            if watchLoopState == .recording { return .recording }
            // An open browser-consent prompt has a deadline and is the one
            // question that can go unseen as a notification (issue #814), so
            // it outranks everything but a running recording and an error.
            if consentPending, transcriberState != .error { return .userAction }
            if transcriberState == .error { return .error }
        }
        switch activeJobState {
        case .transcribing: return .transcribing
        case .diarizing: return .diarizing
        case .some: return .processing
        case .none: break
        }
        if permissionProblem { return .error }
        if updateAvailable { return .updateAvailable }
        return .inactive
    }
}
