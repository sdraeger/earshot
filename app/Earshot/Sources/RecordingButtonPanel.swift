import AppKit
import SwiftUI

/// The floating button shown while a recording runs: a pill at the right edge
/// of the menu-bar screen with voice-activity bars over the app glyph. Drag it
/// up or down (the height is kept); click it for a menu that stops the
/// recording. `sharingType = .none` keeps it out of screen shares and
/// screenshots of other apps.
@MainActor
final class RecordingButtonPanel {
    /// Panel size: the 44×92 pill plus room for its shadow.
    static let panelSize = NSSize(width: 60, height: 108)
    static let edgeInset: CGFloat = 4
    /// The pill's height on screen as a fraction of the visible height, from the bottom.
    static let positionDefaultsKey = "recordingButtonYFraction"
    static let defaultFraction = 0.62

    private var panel: NSPanel?
    private let level: @MainActor () -> Double
    private let stopTitle: @MainActor () -> String
    private let onStop: @MainActor () -> Void
    private let onHide: @MainActor () -> Void
    private let defaults: UserDefaults
    private var grabOffset: CGFloat?

    init(
        level: @escaping @MainActor () -> Double,
        stopTitle: @escaping @MainActor () -> String,
        onStop: @escaping @MainActor () -> Void,
        onHide: @escaping @MainActor () -> Void,
        defaults: UserDefaults = .standard,
    ) {
        self.level = level
        self.stopTitle = stopTitle
        self.onStop = onStop
        self.onHide = onHide
        self.defaults = defaults
    }

    func show() {
        let panel = ensurePanel()
        place(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Origin for a pill at `fraction` of the way up `visible`, flush right.
    static func origin(fraction: Double, in visible: NSRect) -> NSPoint {
        let clamped = min(max(fraction, 0), 1)
        return NSPoint(
            x: visible.maxX - panelSize.width - edgeInset,
            y: visible.minY + clamped * (visible.height - panelSize.height),
        )
    }

    private var visibleFrame: NSRect {
        (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    private func place(_ panel: NSPanel) {
        let fraction = defaults.object(forKey: Self.positionDefaultsKey) as? Double ?? Self.defaultFraction
        panel.setFrameOrigin(Self.origin(fraction: fraction, in: visibleFrame))
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        panel.contentView = NSHostingView(rootView: RecordingButtonView(
            level: level,
            onTap: { [weak self] in self?.showMenu() },
            onDrag: { [weak self] in self?.drag() },
            onDragEnd: { [weak self] in self?.endDrag() },
        ))
        self.panel = panel
        return panel
    }

    /// Follows the pointer vertically, keeping the point it was grabbed at.
    private func drag() {
        guard let panel else { return }
        let mouseY = NSEvent.mouseLocation.y
        let offset = grabOffset ?? (mouseY - panel.frame.minY)
        grabOffset = offset
        let visible = visibleFrame
        let y = min(max(mouseY - offset, visible.minY), visible.maxY - Self.panelSize.height)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: y))
    }

    private func endDrag() {
        grabOffset = nil
        guard let panel else { return }
        let visible = visibleFrame
        let span = visible.height - Self.panelSize.height
        guard span > 0 else { return }
        defaults.set(Double((panel.frame.minY - visible.minY) / span), forKey: Self.positionDefaultsKey)
    }

    private func showMenu() {
        guard let view = panel?.contentView else { return }
        let menu = NSMenu()
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
    let onTap: () -> Void
    let onDrag: () -> Void
    let onDragEnd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                bars(VoiceBars.heights(
                    levelDBFS: level(),
                    phase: context.date.timeIntervalSinceReferenceDate * 9,
                ))
            }
            .frame(width: 20, height: 22)

            Image(systemName: "ear")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
        }
        .frame(width: 44, height: 92)
        .background(Theme.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .frame(width: RecordingButtonPanel.panelSize.width, height: RecordingButtonPanel.panelSize.height)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .gesture(DragGesture(minimumDistance: 3).onChanged { _ in onDrag() }.onEnded { _ in onDragEnd() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(A11yID.recordingButton)
    }

    private func bars(_ heights: [Double]) -> some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 3, height: 22 * heights[index])
            }
        }
        .animation(.easeOut(duration: 0.12), value: heights)
    }
}
