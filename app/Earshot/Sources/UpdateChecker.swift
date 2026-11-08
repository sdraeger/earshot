import Foundation
import Observation

// MARK: - Models

struct ReleaseInfo: Equatable {
    let tagName: String
    let name: String
    let prerelease: Bool
    let htmlURL: URL
    let dmgURL: URL?

    var version: ReleaseVersion? {
        UpdateChecker.parseVersion(tagName)
    }
}

/// `major.minor.patch` with an optional pre-release tag, ordered as semver
/// orders them: a pre-release comes before its release, and pre-releases of
/// one version compare by their tag with numbers read as numbers (rc2 < rc10).
struct ReleaseVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    static func < (lhs: Self, rhs: Self) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
        case (.some, nil): return true
        default: return false
        }
    }
}

// MARK: - Protocol

protocol UpdateProviding: Sendable {
    func latestRelease() async throws -> ReleaseInfo
    func allReleases() async throws -> [ReleaseInfo]
}

// MARK: - GitHub Release Provider

struct GitHubReleaseProvider: UpdateProviding {
    /// Not `private` — `AboutSettingsView`'s GitHub link is built from the same
    /// two constants, so the repo identity has a single home.
    static let owner = "sdraeger"
    static let repo = "earshot"

    private struct GitHubRelease: Codable {
        let tagName: String
        let name: String?
        let prerelease: Bool
        let htmlURL: String
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case prerelease
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct GitHubAsset: Codable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    func latestRelease() async throws -> ReleaseInfo {
        let release: GitHubRelease = try await fetchJSON(path: "releases/latest")
        return mapRelease(release)
    }

    func allReleases() async throws -> [ReleaseInfo] {
        let releases: [GitHubRelease] = try await fetchJSON(path: "releases")
        return releases.map { mapRelease($0) }
    }

    private func fetchJSON<T: Decodable>(path: String) async throws -> T {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/\(path)")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateCheckerError.networkError(
                "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)",
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func mapRelease(_ release: GitHubRelease) -> ReleaseInfo {
        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
        return ReleaseInfo(
            tagName: release.tagName,
            name: release.name ?? release.tagName,
            prerelease: release.prerelease,
            // swiftlint:disable:next force_unwrapping
            htmlURL: URL(string: release.htmlURL)!,
            dmgURL: dmgAsset.flatMap { URL(string: $0.browserDownloadURL) },
        )
    }
}

// MARK: - Errors

enum UpdateCheckerError: LocalizedError {
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case let .networkError(detail): "Network error: \(detail)"
        }
    }
}

// MARK: - UpdateChecker

@MainActor
@Observable
final class UpdateChecker {
    var availableUpdate: ReleaseInfo?
    var isChecking = false
    var lastCheckDate: Date?
    var lastError: String?

    /// The Homebrew cask this app was installed from, `nil` for a DMG install.
    let installedCask: String?

    private let provider: any UpdateProviding
    private let currentVersion: ReleaseVersion
    private var checkTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    /// `installedCask` defaults to `nil` rather than probing the Caskroom, so a
    /// test never depends on whether the machine running it has the cask
    /// installed. The app passes `UpdateInstallRoute.installedCask()`.
    init(provider: any UpdateProviding = GitHubReleaseProvider(), installedCask: String? = nil) {
        self.provider = provider
        self.installedCask = installedCask
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        self.currentVersion = Self.parseVersion(version) ?? ReleaseVersion(major: 0, minor: 0, patch: 0, prerelease: nil)
    }

    /// How `update` should be installed on this machine.
    func installRoute(for update: ReleaseInfo) -> UpdateInstallRoute {
        UpdateInstallRoute.resolve(update: update, installedCask: installedCask)
    }

    func checkNow(includePreReleases: Bool = false) {
        // Deduplicate concurrent calls
        guard checkTask == nil else { return }

        isChecking = true
        lastError = nil

        checkTask = Task {
            defer {
                isChecking = false
                checkTask = nil
            }

            do {
                let release: ReleaseInfo?
                if includePreReleases {
                    let all = try await provider.allReleases()
                    release = all.first { r in
                        guard let remote = r.version else { return false }
                        return remote > currentVersion
                    }
                } else {
                    let latest = try await provider.latestRelease()
                    if let remote = latest.version, remote > currentVersion {
                        release = latest
                    } else {
                        release = nil
                    }
                }
                availableUpdate = release
                lastCheckDate = Date()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func startPeriodicChecks(settings: AppSettings) {
        periodicTask?.cancel()

        periodicTask = Task {
            // Initial delay
            try? await Task.sleep(for: .seconds(30))

            while !Task.isCancelled {
                if settings.checkForUpdates {
                    checkNow(includePreReleases: settings.includePreReleases)
                }
                try? await Task.sleep(for: .seconds(86400)) // 24 hours
            }
        }
    }

    // MARK: - Version Utilities

    /// `1.2.3`, `v1.2.3` or `v1.2.3-rc1`; nil for anything else.
    nonisolated static func parseVersion(_ string: String) -> ReleaseVersion? {
        var s = string
        if s.hasPrefix("v") { s = String(s.dropFirst()) }
        var prerelease: String?
        if let dash = s.firstIndex(of: "-") {
            prerelease = String(s[s.index(after: dash)...])
            s = String(s[s.startIndex ..< dash])
        }
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return ReleaseVersion(major: parts[0], minor: parts[1], patch: parts[2], prerelease: prerelease)
    }
}
