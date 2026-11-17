import Foundation

// Manifold's updates: upstream's feed is still read, at launch and every
// hour (Updater.swift), but a newer Search is only told about. Nothing is
// downloaded or installed. Upstream's build would replace this fork with
// plain Search, and the fork is updated by pulling upstream's code and
// building it again (Fork/README.md).
//
// Newer is decided by version, where upstream compares build numbers. A
// build number is the time a build was made, so any build made here after
// upstream's release would hide that release.

enum ManifoldUpdates {
    /// Upstream's own test runs point the updater at a feed of their own
    /// (SEARCH_FEED) to test its installing, and get upstream's behaviour.
    /// Every other run only tells.
    static var onlyTells: Bool {
        !(Store.testing && ProcessInfo.processInfo.environment["SEARCH_FEED"] != nil)
    }

    /// The release the feed names, when it is a newer version than this
    /// build and runs on this Mac, said at the foot of the window.
    @MainActor
    static func tell(_ found: Updater.Release?, say: ((String) -> Void)?) -> Updater.Release? {
        guard let found, found.runsHere, isNewer(found.version, than: Updater.version) else { return nil }
        say?("Upstream released Search \(found.version). Pull it into your copy to update")
        return found
    }

    /// "1.0.15" after "1.0.14", and "1.0.10" after "1.0.9".
    static func isNewer(_ version: String, than current: String) -> Bool {
        version.compare(current, options: .numeric) == .orderedDescending
    }
}
