import AppKit

// Manifold: Handoff from Safari on an iPhone or iPad. A page open there shows
// at the Dock's end on the Mac, under the Mac's default browser, for any
// browser that says it takes web pages (NSUserActivityTypes in the plist,
// build.sh). Clicking it opens the page here, the way a link from another app
// opens (Links.take). Both devices need the same Apple Account, Bluetooth and
// Wi-Fi on, and Handoff allowed in System Settings › General › AirDrop &
// Handoff (on the iPhone, General › AirPlay & Continuity).

enum Handoff {
    /// The web page a handed-off activity carries: http and https only, with
    /// any password in its address left behind.
    static func page(of activity: NSUserActivity) -> URL? {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        parts.user = nil
        parts.password = nil
        return parts.url
    }
}

extension Links {
    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        userActivityType == NSUserActivityTypeBrowsingWeb
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        // A test run takes nothing from outside it (see Links.handle).
        guard !Store.testing, let url = Handoff.page(of: userActivity) else { return false }
        // Where an address from another app goes.
        self.application(application, open: [url])
        return true
    }
}
