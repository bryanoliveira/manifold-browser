import AppKit

// Manifold: the bench's `space` actions of the fork's own, on a test run only
// (Bench.swift hands them here). Nil goes on to the space's usual answer.
//   "profile"  moves the space on screen to the profile named `name`
//   "strip"    turns the row of spaces on or off (`on`)
//   "shared"   every window's row and which of its pages it holds live, for
//              One page in every window (SharedPages.swift)

@MainActor
enum ForkBench {
    static func space(_ request: [String: Any], _ browser: Browser) -> [String: Any]? {
        guard Store.testing else { return nil }
        switch request["action"] as? String {
        case "profile":
            guard let name = request["name"] as? String,
                  let profile = Profiles.shared.list.first(where: { $0.name == name }) else { return nil }
            browser.moveSpace(browser.spaceID, toProfile: profile.id)
            return nil
        case "strip":
            SpaceStrip.on = request["on"] as? Bool ?? true
            browser.prefs.objectWillChange.send()
            return nil
        case "shared":
            return ["on": SharedPages.on, "windows": Browsers.all.enumerated().map { n, other -> [String: Any] in
                let pictures = other.window.map { pictureCount(in: $0.contentView) } ?? 0
                return [
                    "n": n + 1,
                    "space": other.space.name,
                    "tabs": other.tabs.map(Bench.short),
                    "active": other.active.map(Bench.short) ?? "",
                    "live": other.tabs.filter { $0.built?.window != nil && $0.built?.window === other.window }.map(Bench.short),
                    "pictures": pictures,
                    "key": other.window?.isKeyWindow == true,
                ]
            }]
        case "pins":
            // Every row this window holds, by space, with its pins' tabs.
            var rows: [String: [String]] = [browser.space.name: browser.tabs.filter { $0.pin != nil }.map(Bench.short)]
            for (id, row) in browser.parked {
                rows[browser.spaces.first { $0.id == id }?.name ?? id.uuidString] = row.tabs.filter { $0.pin != nil }.map(Bench.short)
            }
            return ["rows": rows, "shared": Pins.shared(browser.profileID).map(\.home),
                    "own": Dictionary(uniqueKeysWithValues: browser.spaces.map { space in
                        (space.name, Pins.defs(space.id).map { $0.listed == true ? "row " + $0.home : $0.home })
                    })]
        default:
            return nil
        }
    }

    private static func pictureCount(in view: NSView?) -> Int {
        guard let view else { return 0 }
        return (view is PagePicture ? 1 : 0) + view.subviews.reduce(0) { $0 + pictureCount(in: $1) }
    }
}
