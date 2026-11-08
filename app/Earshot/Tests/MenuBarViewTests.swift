@testable import Earshot

// swiftlint:disable file_length
import ViewInspector
import XCTest

@MainActor
// swiftlint:disable:next attributes type_body_length
final class MenuBarViewTests: XCTestCase {
    // MARK: - Helpers

    private actor RetryNotionExporter: NotionExporting {
        private(set) var receivedPageIDs: [String?] = []

        func exportMeeting( // swiftlint:disable:this function_parameter_count
            title _: String, date _: Date?, tags _: [String], markdown _: String,
            existingPageID: String?,
            onPageCreated _: @Sendable (NotionPageResult) async -> Void,
        ) -> NotionPageResult {
            receivedPageIDs.append(existingPageID)
            return NotionPageResult(pageID: "page-1", url: "https://www.notion.so/page-1")
        }
    }

    private func makeStatus(
        state: TranscriberState = .idle,
        meeting: MeetingInfo? = nil,
        error: String? = nil,
    ) -> TranscriberStatus {
        TranscriberStatus(state: state, meeting: meeting, error: error)
    }

    private func makeView(
        status: TranscriberStatus? = nil,
        isWatching: Bool = false,
        pipelineQueue: PipelineQueue? = nil,
        updateChecker: UpdateChecker? = nil,
        onNameSpeakers: @escaping (UUID?) -> Void = { _ in },
        onStopRecording: (() -> Void)? = nil,
        onStartRecording: @escaping () -> Void = {},
        onOpenProtocol: @escaping (URL) -> Void = { _ in },
        onQuit: @escaping () -> Void = {},
        manualRecordingPendingOrActive: Bool = false,
        notionExportEnabled: Bool = false,
    ) throws -> MenuBarView {
        try MenuBarView(
            status: status,
            isWatching: isWatching,
            pipelineQueue: pipelineQueue ?? makeIsolatedQueue(),
            updateChecker: updateChecker,
            onStartStop: {},
            onStartRecording: onStartRecording,
            onRecordApp: {},
            manualRecordingPendingOrActive: manualRecordingPendingOrActive,
            onStopRecording: onStopRecording,
            onOpenProtocol: { onOpenProtocol($0.url) },
            onOpenSettings: {},
            onNameSpeakers: onNameSpeakers,
            onProcessFiles: {},
            onQuit: onQuit,
            notionExportEnabled: notionExportEnabled,
        )
    }

    // MARK: - Start/Stop button

    func testIdleShowsWatchToggleOff() throws {
        let sut = try makeView(status: makeStatus(state: .idle), isWatching: false)
        let body = try sut.inspect()
        XCTAssertFalse(try body.find(ViewType.Toggle.self).isOn())
    }

    func testWatchingShowsWatchToggleOn() throws {
        let sut = try makeView(status: makeStatus(state: .watching), isWatching: true)
        let body = try sut.inspect()
        XCTAssertTrue(try body.find(ViewType.Toggle.self).isOn())
    }

    // MARK: - Meeting info

    func testMeetingInfoShownWhenRecording() throws {
        let meeting = MeetingInfo(app: "Teams", title: "Standup")
        let sut = try makeView(status: makeStatus(state: .recording, meeting: meeting))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(textContaining: "Standup"))
    }

    func testMeetingInfoHiddenWhenIdle() throws {
        let sut = try makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(textContaining: "Standup"))
    }

    // MARK: - Error display

    func testErrorShownWhenErrorState() throws {
        let sut = try makeView(status: makeStatus(state: .error, error: "Python crashed"))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Python crashed"))
    }

    func testErrorHiddenWhenNotErrorState() throws {
        let sut = try makeView(status: makeStatus(state: .recording, error: "stale error"))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "stale error"))
    }

    // MARK: - Name Speakers button

    /// A queue holding one job that waits for speaker names.
    private func makeQueueAwaitingNaming() throws -> PipelineQueue {
        let queue = try makeIsolatedQueue()
        var job = PipelineJob(
            meetingTitle: "Standup", appName: "Teams",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"), appPath: nil, micPath: nil, micDelay: 0,
        )
        job.state = .speakerNamingPending
        queue.enqueue(job)
        return queue
    }

    func testNameSpeakersButtonShownWhenWaiting() throws {
        let sut = try makeView(status: makeStatus(state: .watching), pipelineQueue: makeQueueAwaitingNaming())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Name Speakers…"))
    }

    func testNameSpeakersButtonHiddenWhenIdle() throws {
        let sut = try makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Name Speakers…"))
    }

    // MARK: - Pending browser consent (issue #814)

    func testPendingConsentItemAnswersThePrompt() throws {
        var answers: [Bool] = []
        var sut = try makeView(status: makeStatus(state: .watching), isWatching: true)
        sut.pendingConsentApp = "Google Chrome"
        sut.onAnswerPendingConsent = { answers.append($0) }
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Record the meeting in Google Chrome?"))
        try body.find(viewWithAccessibilityIdentifier: A11yID.menuRecordPendingConsent).button().tap()
        try body.find(viewWithAccessibilityIdentifier: A11yID.menuDeclinePendingConsent).button().tap()
        XCTAssertEqual(answers, [true, false])
    }

    func testPendingConsentItemHiddenWithoutAPrompt() throws {
        let sut = try makeView(status: makeStatus(state: .watching), isWatching: true)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(viewWithAccessibilityIdentifier: A11yID.menuRecordPendingConsent))
    }

    // MARK: - Protocol link

    // MARK: - Static buttons always present

    func testSettingsButtonExists() throws {
        let sut = try makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Settings…"))
    }

    func testQuitButtonExists() throws {
        let sut = try makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Quit Earshot"))
    }

    // MARK: - Start Recording

    func testStartRecordingButtonShownWhenIdle() throws {
        let sut = try makeView(status: makeStatus(state: .idle))
        XCTAssertNoThrow(try sut.inspect().find(button: "Start Recording"))
    }

    func testStartRecordingButtonCallsCallback() throws {
        var called = false
        // swiftlint:disable:next trailing_closure
        let sut = try makeView(status: makeStatus(state: .idle), onStartRecording: { called = true })

        try sut.inspect().find(button: "Start Recording").tap()

        XCTAssertTrue(called)
    }

    func testStartRecordingButtonDisabledWhileAManualStartIsStillInFlight() throws {
        // The window between registering a start and the loop existing. The
        // narrow `state == .recording` predicate misses it, leaving the item
        // enabled and the click silently dropped by the ownership guard.
        let sut = try makeView(status: makeStatus(state: .idle), manualRecordingPendingOrActive: true)
        XCTAssertTrue(try sut.inspect().find(button: "Start Recording").isDisabled())
    }

    func testStartRecordingButtonEnabledWhenNothingRecords() throws {
        // Control for the assertion above.
        let sut = try makeView(status: makeStatus(state: .idle))
        XCTAssertFalse(try sut.inspect().find(button: "Start Recording").isDisabled())
    }

    // MARK: - Button tap callbacks

    func testStartStopButtonCallsCallback() throws {
        var called = false
        let sut = try MenuBarView(
            status: makeStatus(state: .idle),
            isWatching: false,
            pipelineQueue: makeIsolatedQueue(),
            updateChecker: nil,
            onStartStop: { called = true },
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(ViewType.Toggle.self).tap()
        XCTAssertTrue(called)
    }

    func testQuitButtonCallsCallback() throws {
        var called = false
        let sut = try MenuBarView(
            status: makeStatus(state: .idle),
            isWatching: false,
            pipelineQueue: makeIsolatedQueue(),
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: { called = true },
        )
        let body = try sut.inspect()
        try body.find(button: "Quit Earshot").tap()
        XCTAssertTrue(called)
    }

    func testSettingsButtonCallsCallback() throws {
        var called = false
        let sut = try MenuBarView(
            status: makeStatus(state: .idle),
            isWatching: false,
            pipelineQueue: makeIsolatedQueue(),
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: { called = true },
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Settings…").tap()
        XCTAssertTrue(called)
    }

    func testNameSpeakersButtonCallsCallback() throws {
        var called = false
        let sut = try MenuBarView(
            status: makeStatus(state: .watching),
            isWatching: false,
            pipelineQueue: makeQueueAwaitingNaming(),
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in called = true },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Name Speakers…").tap()
        XCTAssertTrue(called)
    }

    // MARK: - State label

    func testMeetingAppShown() throws {
        let meeting = MeetingInfo(app: "Zoom", title: "Retro")
        let sut = try makeView(status: makeStatus(state: .recording, meeting: meeting))
        let body = try sut.inspect()
        let texts = body.findAll(ViewType.Text.self)
        let found = texts.contains { (try? $0.string())?.contains("Zoom") == true }
        XCTAssertTrue(found, "App name 'Zoom' should appear in meeting info")
    }

    // MARK: - Processing section

    func testProcessingSectionHiddenWhenNoJobs() throws {
        let sut = try makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Processing"))
    }

    func testProcessingSectionShownWithActiveJob() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Standup",
            appName: "Teams",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil,
            micPath: nil,
            micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .transcribing)

        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: queue,
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Processing"))
        XCTAssertNoThrow(try body.find(textContaining: "Standup"))
        XCTAssertNoThrow(try body.find(textContaining: "Transcribing… 0s"))
    }

    func testDismissButtonShownForCompletedJob() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Retro",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil,
            micPath: nil,
            micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .done)

        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: queue,
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Dismiss"))
    }

    func testProcessFilesButtonCallsCallback() throws {
        var called = false
        let sut = try MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: makeIsolatedQueue(),
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: { called = true },
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Transcribe Files…").tap()
        XCTAssertTrue(called)
    }

    func testDismissButtonRemovesTheJob() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Standup",
            appName: "Teams",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil,
            micPath: nil,
            micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .done)

        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: queue,
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Dismiss").tap()
        XCTAssertFalse(queue.jobs.contains { $0.id == job.id })
    }

    func testDismissButtonShownForErrorJob() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Webex",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil,
            micPath: nil,
            micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .error, error: "Failed")

        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: queue,
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Dismiss"))
        XCTAssertNoThrow(try body.find(textContaining: "Failed"))
    }

    /// Retry is the only way to run a failed job again without importing its
    /// audio by hand. The queue has its own logDir: the default one is the
    /// app's real data folder.
    ///
    /// Each row carries its own identifier, so the second row's button retries
    /// the second job and leaves the first alone.
    func testRetryButtonRequeuesTheJobOfItsOwnRow() throws {
        let dir = try makeTempDirectory(prefix: "menubar_retry_test")
        let queue = PipelineQueue(logDir: dir)
        let first = try queue.insertJobForTesting(mixPath: emptyFile("first_mix.wav", in: dir), state: .error, error: "Failed")
        let second = try queue.insertJobForTesting(mixPath: emptyFile("second_mix.wav", in: dir), state: .error, error: "Failed")

        let sut = try makeView(status: makeStatus(), pipelineQueue: queue)
        try sut.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.jobRetryButton(1))
            .button()
            .tap()

        XCTAssertEqual(queue.jobs.first { $0.id == second }?.state, .waiting, "Retry did not requeue its own row's job")
        XCTAssertEqual(queue.jobs.first { $0.id == first }?.state, .error, "Retry requeued another row's job")
    }

    /// The button follows the queue's own check rather than the job's state,
    /// so it is absent for a failed job the queue would refuse to retry. The
    /// full set of refusals is covered on the queue; this is the one case a
    /// button keyed on the state alone would get wrong.
    func testRetryButtonIsAbsentForAFailedJobTheQueueWouldRefuse() throws {
        let dir = try makeTempDirectory(prefix: "menubar_retry_absent_test")
        let queue = PipelineQueue(logDir: dir)
        let mixPath = try emptyFile("shared_mix.wav", in: dir)
        queue.insertJobForTesting(mixPath: mixPath, state: .transcribing)
        queue.insertJobForTesting(mixPath: mixPath, state: .error, error: "This recording is already being processed")

        let body = try makeView(status: makeStatus(), pipelineQueue: queue).inspect()

        XCTAssertThrowsError(
            try body.find(viewWithAccessibilityIdentifier: A11yID.jobRetryButton(1)),
            "Retry offered while another job is still transcribing the same recording",
        )
    }

    /// The Retry row is shown from the job's recorded state and the queue's
    /// bookkeeping alone. The audio path here does not exist, so a view that
    /// asked the file system would hide the row, and a view body must not do
    /// that: the recording can sit on a network volume. The retry re-checks
    /// the file itself when it runs.
    func testFailedJobRetryRowIsOfferedWithoutAskingTheFileSystem() throws {
        let queue = try makeIsolatedQueue()
        queue.insertJobForTesting(
            mixPath: URL(fileURLWithPath: "/nonexistent-volume/recordings/gone_mix.wav"),
            state: .error, error: "Failed",
        )

        let body = try makeView(status: makeStatus(), pipelineQueue: queue).inspect()

        XCTAssertNoThrow(
            try body.find(viewWithAccessibilityIdentifier: A11yID.jobRetryButton(0)),
            "the Retry row was decided by a file system check in the view body",
        )
    }

    private func emptyFile(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    func testWarningJobShowsWarningText() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Standup",
            appName: "Teams",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil,
            micPath: nil,
            micDelay: 0,
        )
        var warningJob = job
        warningJob.warnings.append("Diarization failed — speakers not identified")
        warningJob.state = .done
        queue.enqueue(warningJob)

        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: queue,
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(textContaining: "Diarization failed — speakers not identified"))
    }

    // MARK: - Stop Recording button

    func testStopRecordingButtonVisibleWhileRecording() throws {
        // swiftlint:disable:next trailing_closure
        let sut = try makeView(status: makeStatus(state: .recording), onStopRecording: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Stop Recording"))
    }

    func testStopRecordingButtonHiddenWhenNothingRecords() throws {
        let sut = try makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Stop Recording"))
    }

    func testStopRecordingButtonCallsCallback() throws {
        var called = false
        let sut = try MenuBarView(
            status: makeStatus(state: .recording),
            isWatching: false,
            pipelineQueue: makeIsolatedQueue(),
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: { called = true },
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Stop Recording").tap()
        XCTAssertTrue(called)
    }

    // MARK: - Update indicator

    private func checkerWithUpdate(installedCask: String? = nil) throws -> UpdateChecker {
        let checker = UpdateChecker(provider: MockUpdateProvider(), installedCask: installedCask)
        checker.availableUpdate = try ReleaseInfo(
            tagName: "v1.0.0",
            name: "Release v1.0.0",
            prerelease: false,
            htmlURL: XCTUnwrap(URL(string: "https://github.com/pasrom/meeting-transcriber/releases/tag/v1.0.0")),
            dmgURL: URL(string: "https://example.com/app.dmg"),
        )
        return checker
    }

    func testUpdateIndicatorShownWhenUpdateAvailable() throws {
        let sut = try makeView(status: makeStatus(), updateChecker: checkerWithUpdate())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Update to v1.0.0"))
    }

    func testUpdateIndicatorSaysItCopiesBrewCommandForHomebrewInstall() throws {
        let sut = try makeView(
            status: makeStatus(),
            updateChecker: checkerWithUpdate(installedCask: "earshot"),
        )
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(textContaining: "copies the brew command"))
    }

    func testUpdateIndicatorHiddenWhenNoUpdate() throws {
        let checker = UpdateChecker(provider: MockUpdateProvider())

        let sut = try makeView(status: makeStatus(), updateChecker: checker)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Update to v1.0.0"))
    }

    func testUpdateIndicatorHiddenWhenNoChecker() throws {
        let sut = try makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Update to v1.0.0"))
    }

    // MARK: - Process Files button

    func testProcessFilesButtonAlwaysExists() throws {
        let sut = try makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Transcribe Files…"))
    }

    // MARK: - Error job display

    func testErrorJobShowsErrorMessage() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Broken",
            appName: "Teams",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .error, error: "Transcription failed")

        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: queue,
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(textContaining: "Transcription failed"))
    }

    // MARK: - Record/Stop button mutual exclusion

    func testStopRecordingReplacesStartRecording() throws {
        // swiftlint:disable:next trailing_closure
        let sut = try makeView(status: makeStatus(state: .recording), onStopRecording: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Stop Recording"))
        XCTAssertThrowsError(try body.find(text: "Start Recording"))
        XCTAssertThrowsError(try body.find(text: "Record an App…"))
    }

    // MARK: - Job state labels

    func testWaitingJobShowsWaitingLabel() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Standup",
            appName: "Teams",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)

        let sut = try makeView(status: makeStatus(), pipelineQueue: queue)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(textContaining: "Waiting…"))
    }

    func testCancelButtonShownForWaitingJob() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)

        let sut = try makeView(status: makeStatus(), pipelineQueue: queue)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(button: "Cancel"))
    }

    func testCompletedQueueShowsCompletedHeader() throws {
        let dir = try makeTempDirectory(prefix: "menubar_completed_test")
        let queue = PipelineQueue(logDir: dir)
        var job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        job.state = .done
        queue.insertJobForTesting(job)

        let sut = try makeView(status: makeStatus(), pipelineQueue: queue)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(textContaining: "Completed"))
    }

    func testJobLabelsAndCancelArePresent() throws {
        let dir = try makeTempDirectory(prefix: "menubar_job_label_test")
        let queue = PipelineQueue(logDir: dir)
        let job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)

        let body = try makeView(status: makeStatus(), pipelineQueue: queue).inspect()
        XCTAssertNoThrow(try body.find(textContaining: "Sprint"))
        XCTAssertNoThrow(try body.find(textContaining: "Waiting…"))
        XCTAssertFalse(try body.find(button: "Cancel").isDisabled())
    }

    func testCancelButtonCancelsOnlyItsOwnJob() throws {
        let dir = try makeTempDirectory(prefix: "menubar_cancel_test")
        let queue = PipelineQueue(logDir: dir)
        let first = try PipelineJob(
            meetingTitle: "First", appName: "Teams",
            mixPath: emptyFile("first_mix.wav", in: dir),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        let second = try PipelineJob(
            meetingTitle: "Second", appName: "Zoom",
            mixPath: emptyFile("second_mix.wav", in: dir),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(first)
        queue.enqueue(second)

        let body = try makeView(status: makeStatus(), pipelineQueue: queue).inspect()
        let cancelButtons = body.findAll(ViewType.Button.self).filter { button in
            (try? button.find(text: "Cancel")) != nil
        }
        XCTAssertEqual(cancelButtons.count, 2)
        guard cancelButtons.count == 2 else { return }
        try cancelButtons[1].tap()

        XCTAssertTrue(queue.jobs.contains { $0.id == first.id })
        XCTAssertFalse(queue.jobs.contains { $0.id == second.id })
    }

    func testActiveJobProgressLabelRendersTiming() throws {
        let dir = try makeTempDirectory(prefix: "menu_active_progress_test")
        let queue = PipelineQueue(logDir: dir)
        let job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .transcribing)

        let sut = try makeView(status: makeStatus(), pipelineQueue: queue)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(button: "Cancel"))
        XCTAssertNoThrow(try body.find(textContaining: "Sprint"))
        // The stage, not the exact seconds: a loaded runner can take a second
        // between `updateJobState` and `inspect()`.
        XCTAssertNoThrow(try body.find(textContaining: "Sprint — Transcribing… "))
    }

    func testCancelButtonHiddenForDoneJob() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .done)

        let sut = try makeView(status: makeStatus(), pipelineQueue: queue)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(button: "Cancel"))
    }

    func testDoneJobWithoutPathsHidesOpenButton() throws {
        let queue = try makeIsolatedQueue()
        let job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .done)

        let sut = try makeView(status: makeStatus(), pipelineQueue: queue)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(button: "Open"))
    }

    func testDoneJobWithNotionPageShowsOpenInNotion() throws {
        let queue = try makeIsolatedQueue()
        var job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        job.recordNotionPage(
            NotionPageResult(pageID: "page-1", url: "https://www.notion.so/page-1"),
            databaseID: "database-1",
        )
        job.finishNotionExport(succeeded: true)
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .done)

        var openedURL: URL?
        var quitCalled = false
        let sut = try makeView(
            status: makeStatus(),
            pipelineQueue: queue,
            onOpenProtocol: { openedURL = $0 },
            onQuit: { quitCalled = true },
            notionExportEnabled: true,
        )
        let body = try sut.inspect()

        XCTAssertNoThrow(try body.find(button: "Open in Notion"))
        XCTAssertThrowsError(try body.find(button: "Open"))
        try body.find(button: "Open in Notion").tap()
        XCTAssertEqual(openedURL, URL(string: "https://www.notion.so/page-1"))
        XCTAssertFalse(quitCalled)
    }

    func testFailedNotionJobRetryButtonRunsSavedExport() async throws {
        let dir = try makeTempDirectory(prefix: "menu_notion_retry_test")
        let markdown = dir.appendingPathComponent("protocol.md")
        try "# Meeting Protocol - Sprint".write(to: markdown, atomically: true, encoding: .utf8)
        let exporter = RetryNotionExporter()
        let configuration = NotionExportConfiguration(exporter: exporter, databaseID: "database-1")
        let configurationProvider: () -> NotionExportResolution = { .ready(configuration) }
        let queue = PipelineQueue(
            engine: MockEngine(), diarizerFactory: { _ in MockDiarization() },
            protocolGeneratorFactory: { MockProtocolGen() },
            outputDir: dir, logDir: dir,
            notionExportConfigurationProvider: configurationProvider,
        )
        var job = PipelineJob(
            meetingTitle: "Sprint", appName: "Zoom", mixPath: nil,
            appPath: nil, micPath: nil, micDelay: 0,
        )
        job.state = .done
        job.protocolPath = markdown
        job.beginNotionExport(speakerNames: [])
        job.recordNotionPage(
            NotionPageResult(pageID: "page-1", url: "https://www.notion.so/page-1"),
            databaseID: "database-1",
        )
        job.finishNotionExport(succeeded: false)
        queue.insertJobForTesting(job)

        let view = try makeView(status: makeStatus(), pipelineQueue: queue, notionExportEnabled: true)
        let button = try view.inspect().find(viewWithAccessibilityIdentifier: A11yID.jobNotionRetryButton(0)).button()
        XCTAssertFalse(button.isDisabled())
        try button.tap()

        for _ in 0 ..< 50 where queue.jobs.first?.notionExportStatus != .completed {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(queue.jobs.first?.notionExportStatus, .completed)
        let receivedPageIDs = await exporter.receivedPageIDs
        XCTAssertEqual(receivedPageIDs, ["page-1"])
    }

    /// The row is enabled from the job's recorded state alone. The backup path
    /// here does not exist, so a view that asked the file system would disable
    /// the row, and a view body must not do that: the output folder can be a
    /// network volume. The retry re-checks the file itself when it runs.
    func testFailedNotionJobRetryRowIsEnabledWithoutAskingTheFileSystem() throws {
        let queue = try makeIsolatedQueue()
        var job = PipelineJob(
            meetingTitle: "Sprint", appName: "Zoom", mixPath: nil,
            appPath: nil, micPath: nil, micDelay: 0,
        )
        job.state = .done
        job.protocolPath = URL(fileURLWithPath: "/nonexistent-volume/protocols/sprint.md")
        job.beginNotionExport(speakerNames: [])
        job.finishNotionExport(succeeded: false)
        queue.insertJobForTesting(job)

        let view = try makeView(pipelineQueue: queue, notionExportEnabled: true)
        let button = try view.inspect().find(viewWithAccessibilityIdentifier: A11yID.jobNotionRetryButton(0)).button()
        XCTAssertFalse(button.isDisabled())
    }

    func testFailedNotionJobWithoutBackupRetryRowIsDisabled() throws {
        let queue = try makeIsolatedQueue()
        var job = PipelineJob(
            meetingTitle: "Sprint", appName: "Zoom", mixPath: nil,
            appPath: nil, micPath: nil, micDelay: 0,
        )
        job.state = .done
        job.beginNotionExport(speakerNames: [])
        job.finishNotionExport(succeeded: false)
        queue.insertJobForTesting(job)

        let view = try makeView(pipelineQueue: queue, notionExportEnabled: true)
        let button = try view.inspect().find(viewWithAccessibilityIdentifier: A11yID.jobNotionRetryButton(0)).button()
        XCTAssertTrue(button.isDisabled())
    }

    func testDismissIsDisabledWhileNotionExportIsInProgress() throws {
        let queue = try makeIsolatedQueue()
        var job = PipelineJob(
            meetingTitle: "Exporting", appName: "Zoom", mixPath: nil,
            appPath: nil, micPath: nil, micDelay: 0,
        )
        job.state = .done
        job.beginNotionExport(speakerNames: [])
        queue.insertJobForTesting(job)

        let view = try makeView(pipelineQueue: queue, notionExportEnabled: true)
        XCTAssertTrue(try view.inspect().find(button: "Dismiss").isDisabled())
    }

    func testDoneJobWithNotionPageFallsBackToLocalFileWhenDisabled() throws {
        let queue = try makeIsolatedQueue()
        var job = PipelineJob(
            meetingTitle: "Sprint",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        job.protocolPath = URL(fileURLWithPath: "/tmp/protocol.md")
        job.recordNotionPage(
            NotionPageResult(pageID: "page-1", url: "https://www.notion.so/page-1"),
            databaseID: "database-1",
        )
        queue.enqueue(job)
        queue.updateJobState(id: job.id, to: .done)

        let sut = try makeView(
            status: makeStatus(),
            pipelineQueue: queue,
            notionExportEnabled: false,
        )
        let body = try sut.inspect()

        XCTAssertNoThrow(try body.find(button: "Open"))
        XCTAssertThrowsError(try body.find(button: "Open in Notion"))
    }

    // MARK: - Status lines

    func testIdleAndWatchingShowNoStatusLine() throws {
        for state in [TranscriberState.idle, .watching] {
            let body = try makeView(status: makeStatus(state: state)).inspect()
            XCTAssertThrowsError(try body.find(text: state.label), "\(state)")
        }
    }

    // MARK: - Multiple jobs

    func testMultipleJobsRendered() throws {
        let queue = try makeIsolatedQueue()
        let job1 = PipelineJob(
            meetingTitle: "Meeting 1",
            appName: "Teams",
            mixPath: URL(fileURLWithPath: "/tmp/mix1.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        let job2 = PipelineJob(
            meetingTitle: "Meeting 2",
            appName: "Zoom",
            mixPath: URL(fileURLWithPath: "/tmp/mix2.wav"),
            appPath: nil, micPath: nil, micDelay: 0,
        )
        queue.enqueue(job1)
        queue.enqueue(job2)

        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            pipelineQueue: queue,
            updateChecker: nil,
            onStartStop: {},
            onStartRecording: {},
            onRecordApp: {},
            manualRecordingPendingOrActive: false,
            onStopRecording: nil,
            onOpenProtocol: { _ in },
            onOpenSettings: {},
            onNameSpeakers: { _ in },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(textContaining: "Meeting 1"))
        XCTAssertNoThrow(try body.find(textContaining: "Meeting 2"))
    }
}

private extension InspectableView {
    /// A text that contains `fragment`: menu items join a job's title and state.
    func find(textContaining fragment: String) throws -> InspectableView<ViewType.Text> {
        try find(ViewType.Text.self) { try $0.string().contains(fragment) }
    }
}
