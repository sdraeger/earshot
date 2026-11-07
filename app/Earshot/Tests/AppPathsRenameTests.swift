@testable import Earshot
import XCTest

final class AppPathsRenameTests: XCTestCase {
    func testMovesTheOldFolderAndLeavesALink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("MeetingTranscriber")
        let new = root.appendingPathComponent("Earshot")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: old.appendingPathComponent("speakers.json"))

        AppPaths.moveLegacyFolder(old, to: new)

        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("speakers.json").path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: old.path), new.path)
        // A second launch finds the link and leaves both alone.
        AppPaths.moveLegacyFolder(old, to: new)
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("speakers.json").path))
    }

    func testKeepsAnExistingNewFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("MeetingTranscriber")
        let new = root.appendingPathComponent("Earshot")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)

        AppPaths.moveLegacyFolder(old, to: new)

        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: old.path))
    }
}
