@testable import Earshot
import XCTest

final class ParakeetVocabularyConfigurationTests: XCTestCase {
    func testConfigurationKeyChangesWhenVocabularyContentsChange() {
        let first = ParakeetVocabularyConfiguration(
            path: "/tmp/terms.txt",
            bookmark: nil,
            revision: .init(fileID: 42, modificationTime: .distantPast, fileSize: 12),
        )
        let edited = ParakeetVocabularyConfiguration(
            path: "/tmp/terms.txt",
            bookmark: nil,
            revision: .init(fileID: 42, modificationTime: .distantFuture, fileSize: 16),
        )

        XCTAssertNotEqual(first, edited)
    }
}
