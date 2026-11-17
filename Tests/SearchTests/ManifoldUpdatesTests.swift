import XCTest
@testable import Search

/// Manifold tells about a newer upstream Search by its version (ManifoldUpdates.swift).
final class ManifoldUpdatesTests: XCTestCase {
    func testANewerVersionIsNewer() {
        XCTAssertTrue(ManifoldUpdates.isNewer("1.0.15", than: "1.0.14"))
        XCTAssertTrue(ManifoldUpdates.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(ManifoldUpdates.isNewer("1.1", than: "1.0.14"))
    }

    func testTheSameOrAnOlderVersionIsNot() {
        XCTAssertFalse(ManifoldUpdates.isNewer("1.0.14", than: "1.0.14"))
        XCTAssertFalse(ManifoldUpdates.isNewer("1.0.9", than: "1.0.10"))
        // A run with no bundle around it calls itself "dev".
        XCTAssertFalse(ManifoldUpdates.isNewer("1.0.15", than: "dev"))
    }

    @MainActor
    func testItSaysSoAndHandsTheReleaseBack() throws {
        let release = Updater.Release(version: "999.0", build: 1, archive: URL(string: "https://example.com/a.zip")!,
                                      dmg: URL(string: "https://example.com/a.dmg")!, sha256: nil, notes: nil,
                                      minimumSystemVersion: nil)
        var said: [String] = []
        XCTAssertEqual(ManifoldUpdates.tell(release, say: { said.append($0) }), release)
        XCTAssertEqual(said, ["Upstream released Search 999.0. Pull it into your copy to update"])
        XCTAssertNil(ManifoldUpdates.tell(nil, say: { said.append($0) }))
        XCTAssertEqual(said.count, 1)
    }
}
