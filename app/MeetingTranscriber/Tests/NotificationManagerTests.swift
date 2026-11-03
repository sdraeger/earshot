@testable import MeetingTranscriber
import UserNotifications
import XCTest

final class NotificationManagerTests: XCTestCase {
    // MARK: - isSetUp starts false

    func testIsSetUpFalseByDefault() {
        let manager = NotificationManager()
        XCTAssertFalse(manager.isSetUp)
    }

    // MARK: - notify without setUp is no-op

    func testNotifyWithoutSetUpDoesNotCrash() {
        let manager = NotificationManager()
        // isSetUp is false — notify should silently return
        manager.notify(title: "Test", body: "Should be ignored")
        XCTAssertFalse(manager.isSetUp)
    }

    // MARK: - Why a notification is dropped (the reason the log names)

    func testTheDropReasonNamesTheMissingBundleBeforeTheMissingSetUp() {
        // `setUp()` refuses without a bundle, so both are false together, and
        // the cause is the bundle.
        XCTAssertEqual(NotificationManager.undeliverableReason(hasBundle: false), "no_app_bundle")
        XCTAssertEqual(NotificationManager.undeliverableReason(hasBundle: true), "not_set_up")
    }

    /// The raw values are what `notification_posted` logs, so a renamed case
    /// must fail here rather than change the log text unnoticed.
    func testTheUrgencyNamesTheLogUsesArePinned() {
        XCTAssertEqual(NotificationUrgency.standard.rawValue, "standard")
        XCTAssertEqual(NotificationUrgency.timeSensitive.rawValue, "timeSensitive")
    }

    /// The settings line logged with each posted notification. Each field is
    /// named, so "alertStyle=none" cannot be mistaken for the alert switch, and
    /// the names are the `/state` ones.
    func testTheSettingsLineNamesEverySettingThatCanHideANotification() {
        let visibility = NotificationVisibility(
            authorization: .authorized, alert: .enabled, alertStyle: .none,
            timeSensitive: .disabled, scheduledDelivery: .enabled,
        )

        XCTAssertEqual(
            visibility.logDescription,
            "authorization=authorized alert=enabled alertStyle=none timeSensitive=disabled scheduledDelivery=enabled",
        )
    }

    // MARK: - shared singleton

    func testSharedIsSingleton() {
        let a = NotificationManager.shared
        let b = NotificationManager.shared
        XCTAssertIdentical(a, b)
    }

    #if !APPSTORE

        // MARK: - notify records into the ring buffer (RPC observability chokepoint)

        /// The buffer records ahead of the delivery guard, so a notify() call is
        /// captured even when `setUp()` never ran (no app bundle in the test host)
        /// BUT is marked undelivered — the entry means "the app decided to
        /// notify", not "the user saw it". This is the single chokepoint the
        /// debug RPC `/state.notifications` snapshot reads, so every caller is
        /// observable without touching call sites.
        func testNotifyRecordsUnpostedEntryWhenSetUpNeverRan() {
            let manager = NotificationManager()
            XCTAssertFalse(manager.isSetUp)

            manager.notify(title: "Silent Recording", body: "Both channels silent")
            manager.notify(title: "Recording started", body: "Recording: Standup (Teams)")

            let entries = manager.recentNotificationsLog.entries
            XCTAssertEqual(entries.map(\.title), ["Silent Recording", "Recording started"])
            XCTAssertEqual(entries.map(\.body), ["Both channels silent", "Recording: Standup (Teams)"])
            XCTAssertEqual(entries.map(\.posted), [false, false], "delivery guard failed, so entries must be marked unposted")
        }

        /// The `AppNotifying.recentNotifications` conformance exposes the same
        /// entries the buffer holds — this is what `AppState.rpcStateSnapshot()`
        /// reads through the injected notifier.
        func testRecentNotificationsConformanceMirrorsBuffer() {
            let manager = NotificationManager()
            manager.notify(title: "Silent Recording", body: "Both channels silent")

            XCTAssertEqual(manager.recentNotifications, manager.recentNotificationsLog.entries)
        }
    #endif

    // MARK: - Browser consent prompt (issue #503)

    func testConsentGrantedOnlyForRecordAction() {
        XCTAssertEqual(NotificationManager.consentAnswer(for: NotificationManager.recordActionID), .granted)
    }

    func testNeverActionIsItsOwnAnswerNotADecline() {
        // The distinction the deny list rests on: a decline is about this call
        // and expires with the cooldown, Never is about the app and does not.
        // Mapping Never onto .declined would re-prompt ten minutes later.
        XCTAssertEqual(NotificationManager.consentAnswer(for: NotificationManager.neverActionID), .never)
        XCTAssertFalse(ConsentAnswer.never.isGranted)
    }

    func testConsentDeclinedForIgnoreAndUnknownActions() {
        XCTAssertEqual(NotificationManager.consentAnswer(for: NotificationManager.ignoreActionID), .declined)
        XCTAssertEqual(NotificationManager.consentAnswer(for: "something-else"), .declined)
    }

    /// A click on the notification body is not an answer, and neither is a
    /// dismiss: the prompt stays parked (why: `consentAnswer(for:)`).
    func testBodyClickAndDismissAreNotAnAnswer() {
        XCTAssertNil(NotificationManager.consentAnswer(for: UNNotificationDefaultActionIdentifier))
        XCTAssertNil(NotificationManager.consentAnswer(for: UNNotificationDismissActionIdentifier))
    }

    func testConsentCategoryHasRecordIgnoreAndNeverActions() {
        let category = NotificationManager.makeConsentCategory()
        XCTAssertEqual(category.identifier, NotificationManager.consentCategoryID)
        XCTAssertEqual(
            category.actions.map(\.identifier),
            [
                NotificationManager.recordActionID,
                NotificationManager.ignoreActionID,
                NotificationManager.neverActionID,
            ],
        )
        XCTAssertEqual(category.actions.map(\.title), ["Record", "Ignore", "Never for this app"])
        // `consentAnswer(for:)` maps a dismiss to "no answer" on the premise
        // that it never arrives. Registering `.customDismissAction` would make
        // a swipe-away park the prompt with nothing on screen; that needs a
        // decision, not a silent combination.
        XCTAssertFalse(category.options.contains(.customDismissAction))
    }

    /// Neither action may carry `.foreground`. The delegate callback fires
    /// either way, so the flag buys nothing and costs the user their meeting
    /// window: tapping Record activates the app, pulling focus away from the
    /// call they just consented to keep having. On a machine with several
    /// bundles registered for the same identifier it is worse than useless,
    /// because LaunchServices activates whichever copy it considers canonical
    /// rather than the running one.
    func testConsentActionsDoNotActivateTheApp() {
        let category = NotificationManager.makeConsentCategory()
        for action in category.actions {
            XCTAssertFalse(
                action.options.contains(.foreground),
                "\(action.identifier) must not steal focus from the meeting",
            )
        }
    }

    func testAskToRecordDeclinesWhenNotSetUp() async {
        // No app bundle / setUp never ran → we can't show a prompt, so default
        // to "don't record" rather than recording without asking.
        let manager = NotificationManager()
        let answer = await manager.askToRecord(title: "Browser meeting", body: "Record?")
        XCTAssertEqual(answer, .declined)
    }

    func testDefaultNotifierDeniesConsent() async {
        // The AppNotifying default (a notifier with no real prompt, e.g.
        // SilentNotifier) denies consent, so a browser meeting never records
        // without a visible prompt.
        let answer = await SilentNotifier().askToRecord(title: "Browser meeting", body: "Record?")
        XCTAssertEqual(answer, .declined)
    }
}
