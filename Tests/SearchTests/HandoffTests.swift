import XCTest
@testable import Search

/// A page handed off from Safari on an iPhone (Handoff.swift).
final class HandoffTests: XCTestCase {
    private func activity(_ url: String, type: String = NSUserActivityTypeBrowsingWeb) -> NSUserActivity {
        let activity = NSUserActivity(activityType: type)
        activity.webpageURL = URL(string: url)
        return activity
    }

    func testAWebPageComesThrough() {
        XCTAssertEqual(Handoff.page(of: activity("https://example.com/a?b=c#d"))?.absoluteString, "https://example.com/a?b=c#d")
        XCTAssertEqual(Handoff.page(of: activity("http://example.com/"))?.absoluteString, "http://example.com/")
    }

    func testAPasswordInTheAddressIsLeftBehind() {
        XCTAssertEqual(Handoff.page(of: activity("https://me:secret@example.com/"))?.absoluteString, "https://example.com/")
    }

    func testAnythingElseIsNot() {
        // Another app's own activity. (NSUserActivity itself refuses a page
        // address other than http or https, so none can arrive.)
        XCTAssertNil(Handoff.page(of: activity("https://example.com/", type: "com.example.notes.editing")))
    }
}
