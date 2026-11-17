import XCTest
@testable import Search

/// Zen's spaces, read into the shape the Arc import brings in (ImportZen.swift).
final class ImportZenTests: XCTestCase {
    // MARK: - the file

    /// A mozlz4 file written by hand, with one back-reference in it, so the
    /// test holds Apple's LZ4 decoder to the block format Mozilla writes:
    /// nine literal bytes, nine bytes copied from three back, eight more
    /// literal bytes.
    func testUnpacksMozillasLZ4() throws {
        var file = Array("mozLz40\0".utf8) + [26, 0, 0, 0]
        file += [0x95] + Array("{\"t\":\"abc".utf8) + [0x03, 0x00]
        file += [0x80] + Array("\",\"u\":1}".utf8)
        let json = try XCTUnwrap(Zen.unpack(Data(file)))
        XCTAssertEqual(String(decoding: json, as: UTF8.self), "{\"t\":\"abcabcabcabc\",\"u\":1}")
    }

    func testRefusesWhatIsNotMozillasLZ4() {
        XCTAssertNil(Zen.unpack(Data("{\"tabs\":[]}".utf8)))
        // The header promises more than the block holds.
        var file = Array("mozLz40\0".utf8) + [99, 0, 0, 0]
        file += [0x80] + Array("\",\"u\":1}".utf8)
        XCTAssertNil(Zen.unpack(Data(file)))
    }

    // MARK: - the lists

    private func tab(_ url: String, space: String?, pinned: Bool = true, pinnedAt: String? = nil,
                     folder: String? = nil, essential: Bool = false, container: Int = 0,
                     extra: [String: Any] = [:]) -> [String: Any] {
        var tab: [String: Any] = ["entries": [["url": url, "title": "T \(url)"]], "index": 1,
                                  "pinned": pinned, "zenEssential": essential, "userContextId": container]
        if let space { tab["zenWorkspace"] = space }
        if let folder { tab["groupId"] = folder }
        if let pinnedAt { tab["_zenPinnedInitialState"] = ["entry": ["url": pinnedAt, "title": "Pinned"]] }
        return tab.merging(extra) { _, new in new }
    }

    private var session: [String: Any] {
        [
            "spaces": [
                ["uuid": "{a}", "name": "Play", "icon": "🎮️", "containerTabId": 1],
                ["uuid": "{b}", "name": "Work", "icon": "🤖", "containerTabId": 1],
                ["uuid": "{c}", "name": "HUG", "icon": "🐼", "containerTabId": 6],
            ],
            "folders": [
                ["id": "f1", "name": "Admin", "parentId": NSNull(), "splitViewGroup": false],
                ["id": "f2", "name": "Papers", "parentId": "f1", "splitViewGroup": false],
                ["id": "sv", "name": "", "parentId": "f1", "splitViewGroup": true],
            ],
            "groups": [["id": "g1", "name": "Reading", "splitView": false]],
            "tabs": [
                tab("https://mail.example.com/", space: nil, essential: true, container: 1),
                tab("https://now.example.com/", space: "{a}", pinnedAt: "https://home.example.com/"),
                tab("https://a.example.com/", space: "{a}", folder: "f2"),
                tab("https://b.example.com/", space: "{a}", folder: "f1"),
                tab("https://c.example.com/", space: "{a}", folder: "sv"),
                tab("about:blank", space: "{a}", folder: "f1", extra: ["zenIsEmpty": true]),
                tab("https://peek.example.com/", space: "{a}", pinned: false, extra: ["zenIsGlance": true]),
                tab("https://open.example.com/", space: "{a}", pinned: false),
                tab("https://grouped.example.com/", space: "{a}", pinned: false, folder: "g1"),
                tab("moz-extension://x/page.html", space: "{b}"),
                tab("https://hug.example.com/", space: "{c}", container: 6),
            ],
        ]
    }

    func testEachWorkspaceIsASpaceInTheProfileOfItsContainer() {
        let read = Zen.parse(session, containers: [1: "Personal", 6: "Hug"])
        XCTAssertEqual(read.spaces.map(\.name), ["Play", "Work", "HUG"])
        // Most spaces open in Personal: that is the profile already here.
        XCTAssertEqual(read.spaces.map(\.profile), ["Default", "Default", "container-6"])
        XCTAssertEqual(read.profileNames?["container-6"], "Hug")
        XCTAssertEqual(read.spaces[0].symbol, "gamecontroller")
    }

    func testPinnedTabsKeepTheirFoldersAndThePageTheyWerePinnedAt() {
        let play = Zen.parse(session).spaces[0]
        let home = ArcSidebar.Item(title: "Pinned", url: URL(string: "https://home.example.com/")!)
        let a = ArcSidebar.Item(title: "T https://a.example.com/", url: URL(string: "https://a.example.com/")!)
        let b = ArcSidebar.Item(title: "T https://b.example.com/", url: URL(string: "https://b.example.com/")!)
        let c = ArcSidebar.Item(title: "T https://c.example.com/", url: URL(string: "https://c.example.com/")!)
        // A split view's tab sits in the folder the split view is in; Zen's
        // placeholder for an empty folder is left out.
        XCTAssertEqual(play.pinned, [
            .item(home),
            .folder(.init(title: "Admin", items: [.folder(.init(title: "Papers", items: [.item(a)])), .item(b), .item(c)])),
        ])
    }

    func testOpenTabsComeAsTheyAreAndAGlanceDoesNot() {
        let play = Zen.parse(session).spaces[0]
        XCTAssertEqual(play.open.count, 2)
        guard case .item(let open) = play.open.first, case .folder(let group) = play.open.last else {
            return XCTFail("\(play.open)")
        }
        XCTAssertEqual(open.url.absoluteString, "https://open.example.com/")
        XCTAssertEqual(group.title, "Reading")
        // Only web pages: an extension's page doesn't come.
        XCTAssertEqual(Zen.parse(session).spaces[1].pinned, [])
    }

    func testEssentialsGoToEverySpaceUnlessZenKeepsThemApart() {
        let shared = Zen.parse(session)
        XCTAssertEqual(shared.favorites.map(\.url.host), ["mail.example.com"])
        XCTAssertEqual(shared.favoritesByProfile["Default"]?.count, 1)
        XCTAssertEqual(shared.favoritesByProfile["container-6"]?.count, 1)

        let apart = Zen.parse(session, separateEssentials: true)
        XCTAssertEqual(apart.favoritesByProfile["Default"]?.count, 1)
        // Its own list, empty, so it isn't given every profile's.
        XCTAssertEqual(apart.favoritesByProfile["container-6"], [])
    }

    func testOlderZenKeepsTheSameListsInEachWindow() {
        let read = Zen.parse(["windows": [session]], containers: [6: "Hug"])
        XCTAssertEqual(read.spaces.map(\.name), ["Play", "Work", "HUG"])
        XCTAssertEqual(read.pinnedCount, 5)
    }

    func testAnotherFirefoxProfilesSpacesAreProfilesOfTheirOwn() {
        let read = Zen.parse(session, containers: [6: "Hug"], prefix: "abc.Other", label: "Other")
        XCTAssertEqual(read.spaces.map(\.profile), ["abc.Other", "abc.Other", "abc.Other/container-6"])
        XCTAssertEqual(read.profileNames?["abc.Other"], "Other")
        XCTAssertEqual(read.profileNames?["abc.Other/container-6"], "Other · Hug")
    }
}
