import AppKit
@testable import Earshot
import XCTest

@MainActor
final class UpdateInstallRouteTests: XCTestCase {
    private func release(prerelease: Bool = false, dmg: Bool = true) throws -> ReleaseInfo {
        try ReleaseInfo(
            tagName: prerelease ? "v1.0.0-rc1" : "v1.0.0",
            name: "Release",
            prerelease: prerelease,
            htmlURL: XCTUnwrap(URL(string: "https://github.com/pasrom/meeting-transcriber/releases/tag/v1.0.0")),
            dmgURL: dmg ? URL(string: "https://example.com/app.dmg") : nil,
        )
    }

    private let caskApp = UpdateInstallRoute.caskAppPath

    // MARK: - installedCask

    func testInstalledCaskFindsStableUnderAppleSiliconPrefix() {
        let cask = UpdateInstallRoute.installedCask(bundlePath: caskApp) { path in
            path == "/opt/homebrew/Caskroom/earshot"
        }
        XCTAssertEqual(cask, "earshot")
    }

    func testInstalledCaskFindsBetaUnderIntelPrefix() {
        let cask = UpdateInstallRoute.installedCask(bundlePath: caskApp) { path in
            path == "/usr/local/Caskroom/earshot@beta"
        }
        XCTAssertEqual(cask, "earshot@beta")
    }

    func testInstalledCaskIsNilWithoutCaskroomEntry() {
        XCTAssertNil(UpdateInstallRoute.installedCask(bundlePath: caskApp) { _ in false })
    }

    /// The Caskroom is machine-wide: a dev build or a second copy on a Mac
    /// that has the cask must not be told to upgrade a different app.
    func testInstalledCaskIsNilWhenRunningBundleIsNotTheCaskApp() {
        XCTAssertNil(UpdateInstallRoute.installedCask(bundlePath: "/Users/dev/.build/Earshot-Dev.app") { _ in
            true
        })
    }

    // MARK: - resolve

    func testStableCaskGetsBrewCommandForStableRelease() throws {
        let route = try UpdateInstallRoute.resolve(update: release(), installedCask: "earshot")
        XCTAssertEqual(
            route,
            .homebrew(command: "brew update && brew upgrade --cask pasrom/meeting-transcriber/earshot"),
        )
    }

    /// The stable cask never carries a pre-release, so brew would report it as
    /// up to date; the DMG is the only way to the release.
    func testStableCaskFallsBackToDownloadForPrerelease() throws {
        let route = try UpdateInstallRoute.resolve(
            update: release(prerelease: true), installedCask: "earshot",
        )
        try XCTAssertEqual(route, .download(XCTUnwrap(URL(string: "https://example.com/app.dmg"))))
    }

    /// The beta cask is carried forward on stable releases too.
    func testBetaCaskGetsBrewCommandForStableAndPrerelease() throws {
        for prerelease in [false, true] {
            let route = try UpdateInstallRoute.resolve(
                update: release(prerelease: prerelease), installedCask: "earshot@beta",
            )
            XCTAssertEqual(route, .homebrew(command: "brew update && brew upgrade --cask pasrom/meeting-transcriber/earshot@beta"))
        }
    }

    func testDMGInstallGetsDownload() throws {
        let route = try UpdateInstallRoute.resolve(update: release(), installedCask: nil)
        try XCTAssertEqual(route, .download(XCTUnwrap(URL(string: "https://example.com/app.dmg"))))
    }

    func testDownloadFallsBackToReleasePageWithoutDMG() throws {
        let update = try release(dmg: false)
        let route = UpdateInstallRoute.resolve(update: update, installedCask: nil)
        XCTAssertEqual(route, .download(update.htmlURL))
    }

    // MARK: - perform

    func testHomebrewRouteCopiesCommand() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("UpdateInstallRouteTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        UpdateInstallRoute.homebrew(command: "brew upgrade --cask earshot")
            .perform(pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "brew upgrade --cask earshot")
    }

    // MARK: - UpdateChecker wiring

    func testCheckerRouteFollowsInstalledCask() throws {
        let checker = UpdateChecker(provider: MockUpdateProvider(), installedCask: "earshot")

        XCTAssertEqual(
            try checker.installRoute(for: release()),
            .homebrew(command: "brew update && brew upgrade --cask pasrom/meeting-transcriber/earshot"),
        )
    }
}
