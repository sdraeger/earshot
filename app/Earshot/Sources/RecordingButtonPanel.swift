import AppKit
import SwiftUI

/// The floating button shown while a recording runs: a pill on an edge of
/// the menu-bar screen with voice-activity bars beside the app glyph. Drag it
/// anywhere; on release it snaps to the nearest edge (upright on the left and
/// right, lying down on the top and bottom) and keeps that place. Click it
/// for a menu that stops the recording. `sharingType = .none` keeps it out of
/// screen shares and screenshots of other apps.
@MainActor
final class RecordingButtonPanel {
    enum Edge: String {
        case left, right, top, bottom

        var isVertical: Bool {
            self == .left || self == .right
        }
    }

    /// The pill's length and thickness.
    static let pillLength: CGFloat = 80
    static let pillThickness: CGFloat = 36
    /// Room around the pill for its shadow.
    static let shadowMargin: CGFloat = 8
    static let edgeInset: CGFloat = 4
    /// How far along its edge the pill sits, 0 at the bottom or left end.
    /// The key predates the other edges, when it held the height on the right.
    static let fractionDefaultsKey = "recordingButtonYFraction"
    static let edgeDefaultsKey = "recordingButtonEdge"
    static let defaultFraction = 0.62

    private var panel: NSPanel?
    private var host: NSHostingView<RecordingButtonView>?
    private let level: @MainActor () -> Double
    private let stopTitle: @MainActor () -> String
    private let onStop: @MainActor () -> Void
    private let onHide: @MainActor () -> Void
    private let onOpenTranscript: @MainActor () -> Void
    private let defaults: UserDefaults
    private var grabOffset: NSPoint?

    init(
        level: @escaping @MainActor () -> Double,
        stopTitle: @escaping @MainActor () -> String,
        onStop: @escaping @MainActor () -> Void,
        onHide: @escaping @MainActor () -> Void,
        onOpenTranscript: @escaping @MainActor () -> Void,
        defaults: UserDefaults = .standard,
    ) {
        self.level = level
        self.stopTitle = stopTitle
        self.onStop = onStop
        self.onHide = onHide
        self.onOpenTranscript = onOpenTranscript
        self.defaults = defaults
    }

    func show() {
        let panel = ensurePanel()
        let edge = defaults.string(forKey: Self.edgeDefaultsKey).flatMap(Edge.init(rawValue:)) ?? .right
        let fraction = defaults.object(forKey: Self.fractionDefaultsKey) as? Double ?? Self.defaultFraction
        place(panel, edge: edge, fraction: fraction)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// The panel's size on `edge`: the pill plus its shadow margin, long side
    /// along the edge.
    static func panelSize(on edge: Edge) -> NSSize {
        let long = pillLength + 2 * shadowMargin
        let short = pillThickness + 2 * shadowMargin
        return edge.isVertical ? NSSize(width: short, height: long) : NSSize(width: long, height: short)
    }

    /// The panel's frame on `edge`, `fraction` of the way along it (clamped).
    static func frame(edge: Edge, fraction: Double, in visible: NSRect) -> NSRect {
        let size = panelSize(on: edge)
        let along = CGFloat(min(max(fraction, 0), 1))
        let origin = switch edge {
        case .left: NSPoint(x: visible.minX + edgeInset, y: visible.minY + along * (visible.height - size.height))
        case .right: NSPoint(x: visible.maxX - size.width - edgeInset, y: visible.minY + along * (visible.height - size.height))
        case .bottom: NSPoint(x: visible.minX + along * (visible.width - size.width), y: visible.minY + edgeInset)
        case .top: NSPoint(x: visible.minX + along * (visible.width - size.width), y: visible.maxY - size.height - edgeInset)
        }
        return NSRect(origin: origin, size: size)
    }

    /// The edge nearest `center` and how far along it `center` lies.
    static func snap(center: NSPoint, in visible: NSRect) -> (edge: Edge, fraction: Double) {
        let distances: [(Edge, CGFloat)] = [
            (.left, center.x - visible.minX), (.right, visible.maxX - center.x),
            (.bottom, center.y - visible.minY), (.top, visible.maxY - center.y),
        ]
        let edge = distances.min { $0.1 < $1.1 }?.0 ?? .right
        let size = panelSize(on: edge)
        let fraction = edge.isVertical
            ? (center.y - size.height / 2 - visible.minY) / (visible.height - size.height)
            : (center.x - size.width / 2 - visible.minX) / (visible.width - size.width)
        return (edge, Double(min(max(fraction, 0), 1)))
    }

    private var visibleFrame: NSRect {
        (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    private func place(_ panel: NSPanel, edge: Edge, fraction: Double, animate: Bool = false) {
        host?.rootView = makeView(horizontal: !edge.isVertical)
        let frame = Self.frame(edge: edge, fraction: fraction, in: visibleFrame)
        if animate {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func makeView(horizontal: Bool) -> RecordingButtonView {
        RecordingButtonView(
            level: level,
            horizontal: horizontal,
            onTap: { [weak self] in self?.showMenu() },
            onDrag: { [weak self] in self?.drag() },
            onDragEnd: { [weak self] in self?.endDrag() },
        )
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize(on: .right)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.sharingType = .none
        panel.identifier = NSUserInterfaceItemIdentifier("recording-button")
        let host = NSHostingView(rootView: makeView(horizontal: false))
        panel.contentView = host
        self.host = host
        self.panel = panel
        return panel
    }

    /// Follows the pointer, keeping the point it was grabbed at, within the screen.
    private func drag() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let offset = grabOffset ?? NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        grabOffset = offset
        let visible = visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: min(max(mouse.x - offset.x, visible.minX), visible.maxX - size.width),
            y: min(max(mouse.y - offset.y, visible.minY), visible.maxY - size.height),
        ))
    }

    /// Snaps to the nearest edge and remembers it.
    private func endDrag() {
        grabOffset = nil
        guard let panel else { return }
        let frame = panel.frame
        let (edge, fraction) = Self.snap(center: NSPoint(x: frame.midX, y: frame.midY), in: visibleFrame)
        defaults.set(edge.rawValue, forKey: Self.edgeDefaultsKey)
        defaults.set(fraction, forKey: Self.fractionDefaultsKey)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            place(panel, edge: edge, fraction: fraction, animate: true)
        }
    }

    private func showMenu() {
        guard let view = panel?.contentView else { return }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open Transcript", action: onOpenTranscript))
        menu.addItem(ClosureMenuItem(stopTitle(), action: onStop))
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Don't Show This Button", action: onHide))
        menu.popUp(positioning: nil, at: NSPoint(x: 8, y: view.bounds.height - 8), in: view)
    }
}

/// A menu item that runs a closure.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, action handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc
    private func run() {
        handler()
    }
}

/// Bar heights for the voice-activity indicator, as fractions of its height.
enum VoiceBars {
    static let weights: [Double] = [0.55, 1.0, 0.8, 0.45]
    static let floor = 0.18

    /// `loudness = clamp((dBFS + 55) / 40, 0, 1)`, so -55 dBFS and below is
    /// still and -15 dBFS fills the bars; each bar wobbles by up to 25 % with
    /// its own phase so speech reads as movement.
    static func heights(levelDBFS: Double, phase: Double) -> [Double] {
        let loudness = min(max((levelDBFS + 55) / 40, 0), 1)
        return weights.enumerated().map { index, weight in
            floor + (1 - floor) * loudness * weight * (0.75 + 0.25 * sin(phase + Double(index) * 1.3))
        }
    }
}

struct RecordingButtonView: View {
    let level: @MainActor () -> Double
    /// Lying down, on the top or bottom edge.
    var horizontal = false
    let onTap: () -> Void
    let onDrag: () -> Void
    let onDragEnd: () -> Void

    private var pillSize: CGSize {
        let length = RecordingButtonPanel.pillLength
        let thickness = RecordingButtonPanel.pillThickness
        return horizontal ? CGSize(width: length, height: thickness) : CGSize(width: thickness, height: length)
    }

    var body: some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 7)) : AnyLayout(VStackLayout(spacing: 7))
        let panel = RecordingButtonPanel.panelSize(on: horizontal ? .top : .right)
        layout {
            grip

            TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                bars(VoiceBars.heights(
                    levelDBFS: level(),
                    phase: context.date.timeIntervalSinceReferenceDate * 9,
                ))
            }
            .frame(width: 16, height: 18)

            Image(systemName: "ear")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Theme.accent, in: Circle())
        }
        .frame(width: pillSize.width, height: pillSize.height)
        .background(Theme.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .frame(width: panel.width, height: panel.height)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .gesture(DragGesture(minimumDistance: 3).onChanged { _ in onDrag() }.onEnded { _ in onDragEnd() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(A11yID.recordingButton)
    }

    /// Two short bars across the pill to grab it by; an open hand over them.
    private var grip: some View {
        let layout = horizontal ? AnyLayout(HStackLayout(spacing: 2.5)) : AnyLayout(VStackLayout(spacing: 2.5))
        return layout {
            ForEach(0 ..< 2, id: \.self) { _ in
                Capsule()
                    .fill(.secondary.opacity(0.55))
                    .frame(width: horizontal ? 2 : 12, height: horizontal ? 12 : 2)
            }
        }
        .frame(width: horizontal ? 7 : 16, height: horizontal ? 16 : 7)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
    }

    private func bars(_ heights: [Double]) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2.5, height: 18 * heights[index])
            }
        }
        .animation(.easeOut(duration: 0.12), value: heights)
    }
}
