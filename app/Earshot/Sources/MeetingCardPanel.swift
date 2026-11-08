import AppKit
import SwiftUI

/// The card that asks whether to record a detected meeting: top right on the
/// menu-bar screen, over every app and Space, and absent from screen shares
/// and screenshots (`sharingType = .none`), so the people in the meeting never
/// see it. It answers the watch loop's parked consent question.
@MainActor
final class MeetingCardPanel {
    static let width: CGFloat = 320
    /// Room around the card for its shadow.
    static let shadowMargin: CGFloat = 12

    private var panel: NSPanel?
    private let settings: AppSettings
    private let onAnswer: @MainActor (Bool) -> Void

    init(settings: AppSettings, onAnswer: @escaping @MainActor (Bool) -> Void) {
        self.settings = settings
        self.onAnswer = onAnswer
    }

    func show(heading: String, title: String) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: MeetingCardView(
            heading: heading,
            title: title,
            templates: ProtocolTemplates.names(),
            settings: settings,
            onStart: { [weak self] in self?.answer(true) },
            onDismiss: { [weak self] in self?.answer(false) },
        ))
        panel.contentView = host
        let size = host.fittingSize
        let visible = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrame(
            NSRect(
                x: visible.maxX - size.width - 4,
                y: visible.maxY - size.height - 4,
                width: size.width,
                height: size.height,
            ),
            display: true,
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func answer(_ granted: Bool) {
        hide()
        onAnswer(granted)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
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
        panel.identifier = NSUserInterfaceItemIdentifier("meeting-card")
        return panel
    }
}

struct MeetingCardView: View {
    let heading: String
    let title: String
    var templates: [String] = [ProtocolTemplates.defaultName]
    @Bindable var settings: AppSettings
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Live transcript with speakers")
                Spacer()
                Toggle("Live transcript with speakers", isOn: $settings.liveTranscriptionEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            HStack {
                Text("Notes template")
                Spacer()
                Picker("Notes template", selection: $settings.protocolTemplate) {
                    ForEach(templates, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            Button(action: onStart) {
                Label("Start recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .accessibilityIdentifier(A11yID.meetingCardStart)
        }
        .padding(16)
        .frame(width: MeetingCardPanel.width)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(MeetingCardPanel.shadowMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.meetingCard)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "ear")
                .foregroundStyle(Theme.accent)
            Text(heading)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Not now")
            .accessibilityLabel("Not now")
        }
    }
}
