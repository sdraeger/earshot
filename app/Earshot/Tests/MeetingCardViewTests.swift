@testable import Earshot
import ViewInspector
import XCTest

@MainActor
final class MeetingCardViewTests: XCTestCase {
    private func makeSettings() throws -> AppSettings {
        let name = "meeting-card-\(getpid())-\(UUID().uuidString)"
        addTeardownBlock { DefaultsSuite.remove(name) }
        return try AppSettings(defaults: XCTUnwrap(DefaultsSuite.open(name)))
    }

    func testStartAndDismissAnswerTheQuestion() throws {
        var answers: [Bool] = []
        let view = try MeetingCardView(
            heading: "Meeting detected in zoom.us", title: "Weekly sync", settings: makeSettings(),
            onStart: { answers.append(true) }, onDismiss: { answers.append(false) },
        )

        try view.inspect().find(viewWithAccessibilityIdentifier: A11yID.meetingCardStart).button().tap()
        try view.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Not now" }.tap()

        XCTAssertEqual(answers, [true, false])
    }

    func testTheSwitchTurnsOnTheLiveTranscript() throws {
        let settings = try makeSettings()
        settings.liveTranscriptionEnabled = false
        let view = MeetingCardView(heading: "Meeting detected in zoom.us", title: "Weekly sync", settings: settings, onStart: {}, onDismiss: {})

        try view.inspect().find(ViewType.Toggle.self).tap()

        XCTAssertTrue(settings.liveTranscriptionEnabled)
    }

    func testThePickerChoosesTheTemplate() throws {
        let settings = try makeSettings()
        let view = MeetingCardView(
            heading: "Meeting detected in zoom.us", title: "Weekly sync", templates: ["Default", "Standup"],
            settings: settings, onStart: {}, onDismiss: {},
        )

        try view.inspect().find(ViewType.Picker.self).select(value: "Standup")

        XCTAssertEqual(settings.protocolTemplate, "Standup")
    }
}
