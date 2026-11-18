import Foundation

// Manifold: the pins at the top of the column are a profile's, as Arc's
// favourites are. Every space of a profile shows the same ones, and each is one
// page wherever it shows, in every space that shares the profile's sign-ins.
// The pinned rows below them stay each space's own.
//
// Three parts, all on unless turned off in Settings › Spaces & Pins:
//   - a pin pinned as a square is shared with every space of its profile, the
//     Keep in Every Space upstream has (Pins.shared); Only in This Space on a
//     square makes it a row of that space instead;
//   - the squares the spaces already have are made one shared set, once, the
//     copies of a page merged (an import from Arc or Zen gives every space its
//     own copy of the favourites);
//   - a shared pin is one tab across the spaces whose pages use the same
//     store (Browser.reconcilePins asks `one`), instead of a tab per space.
//     A space with sign-ins of its own keeps its own.

@MainActor
enum SharedPins {
    nonisolated static let key = "manifold.profilePins"
    private static let mergedKey = "manifold.profilePins.merged"

    /// On unless turned off; off by default in a test run, so upstream's
    /// own tests see upstream's pins, and the fork's turn it on.
    static var on: Bool {
        get { Store.settings.object(forKey: key) as? Bool ?? !Store.testing }
        set {
            Store.settings.set(newValue, forKey: key)
            if newValue { start() }
        }
    }

    // MARK: - one page

    /// The tab another of this window's rows already has for a shared pin,
    /// for the row of `space` to hold too — or another window's, with One
    /// page in every window on. Only one whose pages use this space's store.
    static func one(for id: UUID, shared: Bool, space: UUID, in browser: Browser) -> Tab? {
        guard on, shared else { return nil }
        let store = Spaces.store(for: space)
        let windows = [browser] + (SharedPages.on ? Browsers.all.filter { $0 !== browser && $0.profileID == browser.profileID && !$0.isPopup && !$0.retired } : [])
        for window in windows {
            for row in rows(of: window, besides: space) {
                if let tab = row.first(where: { $0.pinID == id && !$0.shy && $0.store === store }) { return tab }
            }
        }
        return nil
    }

    /// Whether a row other than `space`'s, in any window, still holds this
    /// tab: a shared pin's tab leaves one row without closing then.
    static func inOtherRow(_ tab: Tab, besides space: UUID) -> Bool {
        guard on, tab.pinID != nil else { return false }
        return Browsers.all.contains { window in
            !window.retired && rows(of: window, besides: space).contains { $0.contains { $0 === tab } }
        }
    }

    /// A window's rows other than `space`'s: the one on screen first.
    private static func rows(of window: Browser, besides space: UUID) -> [[Tab]] {
        var out: [[Tab]] = []
        if window.spaceID != space { out.append(window.tabs) }
        for (id, row) in window.parked where id != space && id != window.spaceID { out.append(row.tabs) }
        return out
    }

    // MARK: - squares are the profile's

    private static var watching: NSObjectProtocol?
    /// The shared pins as last seen, by profile: a square that leaves them
    /// for a space's own list was kept there on purpose (Only in This Space).
    private static var lastShared: [UUID: Set<UUID>] = [:]

    /// At launch (Links), and when turned on: the squares merged once, then
    /// every square pinned from here on shared.
    static func start() {
        guard on else { return }
        Shared.prefs.sharesPins = true
        // With Spaces off there is one space and nothing to share with: the
        // shared pins don't show then (Preferences.showsSharedPins), and a
        // square moved there would vanish. The merge waits for Spaces.
        if Shared.prefs.usesSpaces, !Store.settings.bool(forKey: mergedKey) {
            Store.settings.set(true, forKey: mergedKey)
            for profile in Profiles.shared.list { merge(profile.id) }
        }
        remember()
        guard watching == nil else { return }
        watching = NotificationCenter.default.addObserver(forName: Pins.changed, object: nil, queue: .main) { note in
            guard let space = note.userInfo?["space"] as? UUID else {
                MainActor.assumeIsolated { remember() }
                return
            }
            MainActor.assumeIsolated { shareSquares(of: space) }
        }
    }

    private static func remember() {
        for profile in Profiles.shared.list { lastShared[profile.id] = Set(Pins.shared(profile.id).map(\.id)) }
    }

    /// A space's own squares, shared with every space of its profile; one
    /// that was shared a moment ago and was kept here is made a row instead.
    private static func shareSquares(of space: UUID) {
        guard on, Shared.prefs.showsSharedPins, Spaces.known[space] != nil else { return }
        let profile = Spaces.profile(of: space)
        var own = Pins.defs(space)
        let squares = own.filter { $0.listed != true }
        guard !squares.isEmpty else { return remember() }
        let was = lastShared[profile] ?? []
        var shared = Pins.shared(profile)
        var changed = false
        for square in squares {
            guard let at = own.firstIndex(where: { $0.id == square.id }) else { continue }
            if was.contains(square.id) {
                own[at].listed = true
            } else if shared.contains(where: { $0.home == square.home }) {
                // Already one of the profile's: the copy goes.
                own.remove(at: at)
            } else {
                var pin = own.remove(at: at)
                pin.folder = nil
                shared.append(pin)
            }
            changed = true
        }
        guard changed else { return }
        lastShared[profile] = Set(shared.map(\.id))
        Pins.adopt([space: own], in: [space], shared: shared, profile: profile)
    }

    /// Every space's squares in one profile made its shared ones, in the
    /// order they are first met, a page pinned in several spaces once.
    static func merge(_ profile: UUID) {
        let spaces = Spaces.read(profile: profile).map(\.id)
        var shared = Pins.shared(profile)
        var homes = Set(shared.map(\.home))
        var own: [UUID: [PinDef]] = [:]
        for space in spaces {
            var keep: [PinDef] = []
            for pin in Pins.defs(space) {
                guard pin.listed != true else { keep.append(pin); continue }
                if homes.insert(pin.home).inserted {
                    var moved = pin
                    moved.folder = nil
                    shared.append(moved)
                }
            }
            own[space] = keep
        }
        guard shared != Pins.shared(profile) || spaces.contains(where: { (own[$0] ?? []) != Pins.defs($0) }) else { return }
        Pins.adopt(own, in: spaces, shared: shared, profile: profile)
    }
}
