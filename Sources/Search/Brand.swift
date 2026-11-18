import Foundation

// Manifold's name and mark inside the app, where upstream's say Search: the
// window's title, Quit, Settings › About, the default-browser lines and the
// welcome. The rest of the app's text still says Search, which keeps
// upstream's edits to those lines merging cleanly (Fork/README.md).
//
// The mark is Fork/mark.svg, which build.sh copies into the app's Resources;
// a run without it (swift run, the tests) draws upstream's.

enum Brand {
    nonisolated static let name = "Manifold"

    /// Search › Send Feedback: a new issue on the fork's own repository, with
    /// the version already in it, rather than an email to Office Commun.
    nonisolated static var feedback: URL? {
        var page = URLComponents(string: "https://github.com/bryanoliveira/manifold-browser/issues/new")
        page?.queryItems = [URLQueryItem(name: "body", value: "\n\n—\n\(name) \(Updater.version), build \(Updater.build), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")]
        return page?.url
    }

    /// The mark's canvas and its one path, from mark.svg in the app's
    /// Resources. Nil when it isn't there.
    nonisolated static let mark: (canvas: CGSize, data: String)? = {
        guard let url = Bundle.main.url(forResource: "mark", withExtension: "svg"),
              let svg = try? String(contentsOf: url, encoding: .utf8),
              let box = svg.firstMatch(of: #/viewBox="0 0 ([0-9.]+) ([0-9.]+)"/#),
              let width = Double(box.1), let height = Double(box.2),
              let path = svg.firstMatch(of: #/ d="([^"]+)"/#)
        else { return nil }
        return (CGSize(width: width, height: height), String(path.1))
    }()
}
