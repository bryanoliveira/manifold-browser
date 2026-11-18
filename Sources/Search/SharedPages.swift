import AppKit
import WebKit

// Manifold: one page in every window. A space's row belongs to the space, not
// to a window: two windows of one profile showing a space hold the same tabs,
// so each page is in memory once. A page can be drawn in only one window at a
// time; the window in front holds it live, and any other window showing it
// draws a picture of it, a few times a second, until it comes to the front and
// takes the page, with no reload.
//
// Off unless turned on (Settings › Tabs › One page in every window), and only
// from the next launch: windows that hold the same tabs can't go back to
// holding their own while they are open. Fork/README.md says what changes:
// closing a window no longer closes its tabs, which stay with their space.
//
// Upstream's code keeps its shape: each window's `tabs` and `parked` still
// hold its rows, and the hooks here keep the copies of one space's row the
// same objects in every window that has it.

@MainActor
enum SharedPages {
    nonisolated static let key = "manifold.sharedPages"

    /// As it was when this run started (see above).
    static let on: Bool = Store.settings.bool(forKey: key)

    /// The switch itself, for the next launch.
    static var wanted: Bool {
        get { Store.settings.bool(forKey: key) }
        set { Store.settings.set(newValue, forKey: key) }
    }

    // MARK: - one row per space

    /// Set while one window's change is copied into the others, so their own
    /// didSets don't copy it back.
    private static var syncing = false

    /// The windows other than `browser` that hold `space`'s row, on screen
    /// or parked: one profile's, not pop-ups, not closing.
    static func holders(of space: UUID, profile: UUID, except browser: Browser?) -> [Browser] {
        Browsers.all.filter { other in
            other !== browser && other.profileID == profile && !other.isPopup && !other.retired
                && (other.spaceID == space || other.parked[space] != nil)
        }
    }

    /// `space`'s row as another window has it: on screen there first, as the
    /// freshest, then parked. Nil with the switch off or nobody holding it.
    static func live(_ space: UUID, for browser: Browser) -> Parked? {
        guard on, !browser.isPopup else { return nil }
        let others = holders(of: space, profile: browser.profileID, except: browser)
        if let shown = others.first(where: { $0.spaceID == space && !$0.tabs.isEmpty }) {
            return Parked(tabs: shown.tabs, active: shown.activeID, splits: shown.splits, groups: shown.tabGroups)
        }
        return others.lazy.compactMap { $0.parked[space] }.first { !$0.tabs.isEmpty }
    }

    /// A parked row about to come on screen (Browser.enter): the live one,
    /// keeping this window's own tab in front if the row still has it.
    static func fresh(_ space: UUID, for browser: Browser) -> Parked? {
        guard var row = live(space, for: browser) else { return nil }
        if let mine = browser.parked[space]?.active, row.tabs.contains(where: { $0.id == mine }) { row.active = mine }
        return row
    }

    /// One window's row changed (its `tabs`, `splits` or `tabGroups`): every
    /// other window holding the same space gets the same, keeping its own tab
    /// in front, or the one now at its place when that one went.
    static func rowChanged(_ browser: Browser) {
        guard on, !syncing, !browser.isPopup, !browser.retired, !browser.tabs.isEmpty else { return }
        let space = browser.spaceID
        let row = browser.tabs
        let ids = row.map(\.id)
        // On its way to another space (Browser.enter): the row on screen is
        // still the one it has just parked, under the space it left, while
        // spaceID already names the next. Not this space's row at all.
        if browser.parked.contains(where: { $0.key != space && $0.value.tabs.map(\.id) == ids }) { return }
        syncing = true
        defer { syncing = false }
        for other in holders(of: space, profile: browser.profileID, except: browser) {
            if other.spaceID == space {
                // A window on its way into the space takes the row as it
                // restores it (join), not half-way.
                guard !other.tabs.isEmpty else { continue }
                guard other.tabs.map(\.id) != ids || other.splits != browser.splits || other.tabGroups != browser.tabGroups
                else { continue }
                let keep = kept(other.activeID, from: other.tabs, in: row)
                other.tabGroups = browser.tabGroups
                other.showRow(row, active: keep, splits: browser.splits)
            } else if var parked = other.parked[space] {
                let keep = kept(parked.active, from: parked.tabs, in: row)
                parked.tabs = row
                parked.splits = browser.splits
                parked.groups = browser.tabGroups
                parked.active = keep
                other.parked[space] = parked
            }
        }
    }

    /// A window's tab in front, if the new row still has it; otherwise the
    /// tab now at its place.
    private static func kept(_ active: Tab.ID?, from old: [Tab], in row: [Tab]) -> Tab.ID? {
        guard let active, !row.isEmpty else { return row.first?.id }
        if row.contains(where: { $0.id == active }) { return active }
        let at = old.firstIndex { $0.id == active } ?? 0
        return row[min(at, row.count - 1)].id
    }

    /// The first step of Browser.restoreSession: the row another window
    /// already has for this space, with any page this window's own record
    /// held that the row lacks (a second window from before the switch was
    /// on). True when it took one.
    static func join(_ browser: Browser) -> Bool {
        guard let live = live(browser.spaceID, for: browser) else { return false }
        let extras = browser.extras(for: browser.spaceID, beside: live.tabs)
        browser.tabGroups = live.groups ?? []
        browser.showRow(live.tabs + extras, active: live.active, splits: live.splits)
        for tab in browser.tabs where browser.visibleTabIDs.contains(tab.id) { _ = tab.wake() }
        return true
    }

    /// Browser.readRow, for a window that isn't its profile's oldest: the
    /// space's file, which every window shares with the switch on, and any
    /// page of this window's own record the file lacks.
    static func readRow(_ browser: Browser, _ space: UUID) -> Session.Shape? {
        guard on, !browser.isPopup, !browser.usesFiles else { return nil }
        var shape = Session.read(space: space)
        let have = Set(shape.tabs.map(\.url))
        let mine = browser.record.rows[space.uuidString]?.tabs ?? []
        shape.tabs += mine.filter { $0.pin == nil && !have.contains($0.url) }
        return shape
    }

    /// Browser.writeRow: every window writes its rows into the space's file
    /// too, so whichever window opens a space finds the same row.
    static func writesFiles(_ browser: Browser) -> Bool {
        on && !browser.isPopup && !browser.usesFiles
    }

    /// Whether a window other than `browser` still has this tab, so closing
    /// the window, or putting a space away, leaves it be.
    static func heldElsewhere(_ tab: Tab, by browser: Browser) -> Bool {
        guard on else { return false }
        return Browsers.all.contains { other in
            other !== browser && !other.retired && (other.tabs.contains { $0 === tab } || other.parkedTabs.contains { $0 === tab })
        }
    }

    /// Whether another window shows this tab now, so it stays awake and open
    /// (Sleep.swift, Closing.swift).
    static func shownElsewhere(_ tab: Tab, by browser: Browser) -> Bool {
        guard on else { return false }
        return Browsers.all.contains { other in
            other !== browser && !other.retired && !other.shut && other.visibleTabIDs.contains(tab.id)
        }
    }

    /// The window extensions see a tab in: the first whose row on screen
    /// has it, as Extensions.browser(of:) answers. A tab in two windows' rows
    /// is told of once, in that window (Extensions.follow).
    static func isHome(_ browser: Browser, of tab: Tab) -> Bool {
        guard on else { return true }
        return Browsers.all.first { !$0.retired && !$0.isPopup && $0.tabs.contains { $0 === tab } } === browser
    }

    // MARK: - the live page and its pictures

    /// Every stage that has asked, so a page moving between windows has the
    /// stage it left draw a picture in its place.
    private static let stages = NSHashTable<StageView>.weakObjects()

    /// StageView.placeWanted, before it takes its page: whether it may. A
    /// page another window of ours shows stays there unless this window is
    /// the one in front; this stage draws a picture of it instead. A page
    /// filling the screen is upstream's business.
    static func mayTake(_ page: NSView, into stage: StageView) -> Bool {
        guard on else { return true }
        stages.add(stage)
        guard let window = stage.window, let web = page as? WKWebView, web.fullscreenState == .notInFullscreen,
              let current = page.window, current !== window, let from = Browsers.browser(for: current)
        else {
            dropPicture(in: stage)
            return true
        }
        // The window in front: the one last brought forward (Browsers.front),
        // which stays so while another app is in front.
        guard let to = Browsers.browser(for: window), to === Browsers.front else {
            picture(of: web, in: stage)
            return false
        }
        // This window takes it: its delegate is this window now, as when a
        // tab is moved here (Browser.receive), and the stage it left draws a
        // picture in its place.
        if let tab = to.tabs.first(where: { $0.built === web }) {
            if from.peekTab != nil, from.peekFrom == tab.id { from.closePeek() }
            to.prepare(tab)
        }
        dropPicture(in: stage)
        DispatchQueue.main.async {
            for other in stages.allObjects where other !== stage && other.window === current { other.needsLayout = true }
        }
        return true
    }

    /// A window came to the front: its stages look again, and take any page
    /// another window was holding for it.
    static func becameKey(_ browser: Browser) {
        guard on else { return }
        for stage in stages.allObjects where stage.window === browser.window { stage.needsLayout = true }
    }

    /// Whether a view in a stage is the picture standing in for the page it
    /// wants, which StageView.clearUnwanted leaves.
    static func keeps(_ view: NSView, for page: NSView?) -> Bool {
        guard on, let picture = view as? PagePicture else { return false }
        return page != nil && picture.page === page
    }

    private static func picture(of web: WKWebView, in stage: StageView) {
        if let shown = stage.subviews.compactMap({ $0 as? PagePicture }).first {
            if shown.page === web { shown.frame = stage.bounds; return }
            shown.removeFromSuperview()
        }
        let picture = PagePicture(page: web)
        picture.frame = stage.bounds
        picture.autoresizingMask = [.width, .height]
        stage.addSubview(picture)
        picture.start()
    }

    private static func dropPicture(in stage: StageView) {
        for picture in stage.subviews.compactMap({ $0 as? PagePicture }) {
            picture.stop()
            picture.removeFromSuperview()
        }
    }
}

/// A page drawn as a picture in a window that isn't holding it live, taken
/// again a few times a second while it can be seen. A click brings its
/// window to the front, which takes the page itself (SharedPages.becameKey).
final class PagePicture: NSView {
    weak var page: WKWebView?
    private var timer: Timer?
    private var taking = false

    init(page: WKWebView) {
        self.page = page
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) { nil }

    func start() {
        take()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.take() }
        }
        timer?.tolerance = 0.05
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    /// The page as it is now, at this view's width. Nothing while the window
    /// can't be seen, or while the last picture is still being made.
    private func take() {
        guard !taking, let page, let window, window.occlusionState.contains(.visible), bounds.width > 0 else { return }
        taking = true
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(bounds.width))
        page.takeSnapshot(with: config) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.taking = false
                if let image { self.layer?.contents = image }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Browser {
    /// Pages this window's own record keeps for `space` that `row` lacks, as
    /// tabs asleep: what a window brings to a row it joins (SharedPages.join).
    func extras(for space: UUID, beside row: [Tab]) -> [Tab] {
        guard !usesFiles else { return [] }
        let have = Set(row.compactMap { ($0.pending ?? $0.address)?.absoluteString })
        var seen = have
        return (record.rows[space.uuidString]?.tabs ?? []).compactMap { entry in
            guard entry.pin == nil, entry.url != "about:blank", seen.insert(entry.url).inserted,
                  let url = URL(string: entry.url) else { return nil }
            let tab = Tab(configuration: Web.configuration(space: space))
            prepare(tab)
            tab.restore(url: url, title: entry.title)
            return tab
        }
    }
}
