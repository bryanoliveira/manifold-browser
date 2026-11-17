import Compression
import Foundation

// Zen's spaces, read: its workspaces and what is pinned and open in each, its
// Essentials, and the containers its spaces sign in with. Zen's bookmarks,
// history and passwords already come through the Firefox reader (Mozilla in
// Import.swift); this is the part only Zen has.
//
// Zen keeps all of it in one file per Firefox profile, zen-sessions.jsonlz4:
// JSON, LZ4-compressed behind Mozilla's 8-byte "mozLz40\0" header and the
// size it unpacks to. Older Zen kept the same lists in each window of
// Firefox's own session file, which is read when the newer one isn't there.
//
// What it is read into is Arc's shape (ArcSidebar), so the same takeArc
// brings it in, folders and pinned rows and profiles included. A Zen
// container, a cookie jar of its own, is what Search calls a profile: the
// container most spaces open in is the profile already here ("Default" to
// takeArc), and each other one a profile of its name.
//
// Read as damaged files are: a folder is taken no deeper than 64, only http
// and https addresses come, a password in one is dropped, and a file larger
// than any real session isn't read at all.

enum Zen {
    /// Where a profile's session is, newest kind first.
    static let sessionFiles = [
        "zen-sessions.jsonlz4",
        "sessionstore-backups/recovery.jsonlz4",
        "sessionstore.jsonlz4",
        "sessionstore-backups/previous.jsonlz4",
    ]

    /// Zen's spaces for one Firefox profile, by its folder's name, or for
    /// every one when nil. Nil when no profile has a session that reads.
    static func sidebar(in source: Mozilla.Source, profile: String?) -> ArcSidebar? {
        let folders = source.files(only: profile).map { $0.deletingLastPathComponent() }
        // The profile Zen opens first is the one whose spaces sign in as
        // this window does; any other is a profile of its own.
        let usual = ImportSource.mozilla(source).usual
        let ordered = folders.filter { $0.lastPathComponent == usual } + folders.filter { $0.lastPathComponent != usual }
        let labels = source.ini.names
        var merged: ArcSidebar?
        for folder in ordered {
            guard let state = session(in: folder) else { continue }
            let first = merged == nil
            let name = folder.lastPathComponent
            let read = parse(state, containers: containers(in: folder), separateEssentials: separateEssentials(in: folder),
                             prefix: first ? nil : name, label: labels[name] ?? name)
            guard var all = merged else { merged = read; continue }
            all.spaces += read.spaces
            all.favorites += read.favorites
            all.favoritesByProfile.merge(read.favoritesByProfile) { a, _ in a }
            all.profileNames = (all.profileNames ?? [:]).merging(read.profileNames ?? [:]) { a, _ in a }
            merged = all
        }
        return merged
    }

    static func counts(in source: Mozilla.Source, profile: String?) -> (spaces: Int, pinned: Int)? {
        sidebar(in: source, profile: profile).map { ($0.spaces.count, $0.pinnedCount + $0.favorites.count) }
    }

    // MARK: - the files

    /// The first of a profile's session files that unpacks to Zen's lists.
    static func session(in folder: URL) -> [String: Any]? {
        for name in sessionFiles {
            guard let packed = read(folder.appendingPathComponent(name), limit: 256 << 20),
                  let json = unpack(packed),
                  let top = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  top["tabs"] != nil || top["windows"] != nil
            else { continue }
            return top
        }
        return nil
    }

    /// Mozilla's LZ4 file: "mozLz40\0", the unpacked size as four bytes
    /// little-endian, then one raw LZ4 block.
    static func unpack(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 12, Array(bytes[0..<8]) == Array("mozLz40\0".utf8) else { return nil }
        let size = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        guard size > 0, size <= 1 << 30 else { return nil }
        var out = [UInt8](repeating: 0, count: size)
        let written = out.withUnsafeMutableBufferPointer { target -> Int in
            bytes.withUnsafeBufferPointer { source -> Int in
                guard let into = target.baseAddress, let from = source.baseAddress else { return 0 }
                return compression_decode_buffer(into, size, from + 12, bytes.count - 12, nil, COMPRESSION_LZ4_RAW)
            }
        }
        return written == size ? Data(out) : nil
    }

    /// A file's bytes, unless it is a link, not a plain file, or larger
    /// than `limit`.
    private static func read(_ url: URL, limit: Int) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= limit else { return nil }
        guard let data = try? handle.readToEnd(), data.count <= limit else { return nil }
        return data
    }

    /// The containers a profile has, by number: "Personal", "Work".
    /// Firefox's four built-in ones may carry no name, only the string it
    /// translates them by.
    static func containers(in folder: URL) -> [Int: String] {
        guard let data = read(folder.appendingPathComponent("containers.json"), limit: 4 << 20),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        let builtIn = ["user-context-personal": "Personal", "user-context-work": "Work",
                       "user-context-banking": "Banking", "user-context-shopping": "Shopping"]
        var names: [Int: String] = [:]
        for case let identity as [String: Any] in (top["identities"] as? [Any]) ?? [] {
            guard let id = identity["userContextId"] as? Int, identity["public"] as? Bool != false else { continue }
            let name = named(identity["name"] as? String) ?? (identity["l10nId"] as? String).flatMap { builtIn[$0] }
            if let name { names[id] = name }
        }
        return names
    }

    /// Whether Essentials belong to a container rather than to every space:
    /// zen.workspaces.separate-essentials, once
    /// zen.workspaces.container-specific-essentials-enabled. Off by default.
    static func separateEssentials(in folder: URL) -> Bool {
        guard let data = read(folder.appendingPathComponent("prefs.js"), limit: 16 << 20),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        for key in ["zen.workspaces.separate-essentials", "zen.workspaces.container-specific-essentials-enabled"]
        where text.contains("user_pref(\"\(key)\", true)") {
            return true
        }
        return false
    }

    // MARK: - the lists

    /// One Firefox profile's session as Arc's shape. `prefix` keeps its
    /// profiles apart from another Firefox profile's, read with it; nil for
    /// the first, whose most-used container is the profile already here.
    static func parse(_ top: [String: Any], containers: [Int: String] = [:], separateEssentials: Bool = false,
                      prefix: String? = nil, label: String? = nil) -> ArcSidebar {
        // Zen's own file holds the lists at the top; Firefox's session holds
        // them once per window.
        let windows = top["tabs"] != nil ? [top] : ((top["windows"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        var rawSpaces: [[String: Any]] = []
        var seenSpaces = Set<String>()
        var tabs: [[String: Any]] = []
        var folders: [String: Folder] = [:]
        var groupNames: [String: String] = [:]
        for window in windows {
            for case let space as [String: Any] in (window["spaces"] as? [Any]) ?? [] {
                if let id = space["uuid"] as? String, seenSpaces.insert(id).inserted { rawSpaces.append(space) }
            }
            tabs += ((window["tabs"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
            for case let folder as [String: Any] in (window["folders"] as? [Any]) ?? [] {
                guard let id = folder["id"] as? String else { continue }
                folders[id] = Folder(name: named(folder["name"] as? String) ?? "Folder",
                                     parent: folder["parentId"] as? String,
                                     split: folder["splitViewGroup"] as? Bool == true)
            }
            for case let group as [String: Any] in (window["groups"] as? [Any]) ?? [] {
                guard let id = group["id"] as? String, group["splitView"] as? Bool != true else { continue }
                if let name = named(group["name"] as? String) { groupNames[id] = name }
            }
        }

        // The container most spaces open in, the first such space's on a
        // tie: it, and no container at all, are the profile already here.
        let used = rawSpaces.map { ($0["containerTabId"] as? Int) ?? 0 }
        let tally = Dictionary(used.map { ($0, 1) }, uniquingKeysWith: +)
        let home = used.first { tally[$0] == tally.values.max() } ?? 0
        let homeKey = prefix ?? "Default"
        var profileNames: [String: String] = [:]
        if let prefix { profileNames[prefix] = label ?? prefix }
        func profile(_ container: Int) -> String {
            guard container != 0, container != home else { return homeKey }
            let key = (prefix.map { "\($0)/" } ?? "") + "container-\(container)"
            let name = containers[container] ?? "Container \(container)"
            profileNames[key] = prefix == nil ? name : "\(label ?? homeKey) · \(name)"
            return key
        }

        // Each space's tree of pinned pages and its open ones, filled in the
        // order Zen keeps its tabs, a folder made where its first page is.
        let spaceIDs = rawSpaces.compactMap { $0["uuid"] as? String }
        var pinned: [String: Box] = [:]
        var open: [String: Box] = [:]
        var boxes: [String: [String: Box]] = [:]
        var openGroups: [String: [String: Box]] = [:]
        for id in spaceIDs { pinned[id] = Box(title: ""); open[id] = Box(title: "") }
        var essentials: [(container: Int, item: ArcSidebar.Item)] = []
        var total = 0

        func folderBox(_ id: String?, space: String, depth: Int = 0) -> Box? {
            guard let root = pinned[space] else { return nil }
            guard let id, depth < 64, let folder = folders[id] else { return root }
            // A split view is two tabs side by side, not a folder: its tabs
            // go where it is.
            if folder.split { return folderBox(folder.parent, space: space, depth: depth + 1) }
            if let made = boxes[space]?[id] { return made }
            guard let parent = folderBox(folder.parent, space: space, depth: depth + 1) else { return nil }
            let made = Box(title: folder.name)
            parent.nodes.append(.box(made))
            boxes[space, default: [:]][id] = made
            return made
        }

        for tab in tabs where total < 5000 {
            // A glance is a peek that was never kept, an empty tab is Zen's
            // placeholder in an empty folder, and a live folder's pages are
            // fetched again from its feed.
            guard tab["zenIsGlance"] as? Bool != true, tab["zenIsEmpty"] as? Bool != true,
                  tab["zenLiveFolderItemId"] as? String == nil,
                  let item = item(of: tab)
            else { continue }
            total += 1
            if tab["zenEssential"] as? Bool == true {
                essentials.append(((tab["userContextId"] as? Int) ?? 0, item))
                continue
            }
            // A tab outside any known space is in the first one, as Zen
            // shows it.
            let space = (tab["zenWorkspace"] as? String).flatMap { pinned[$0] != nil ? $0 : nil } ?? spaceIDs.first
            guard let space else { continue }
            if tab["pinned"] as? Bool == true {
                folderBox(tab["groupId"] as? String, space: space)?.nodes.append(.item(item))
            } else if let root = open[space] {
                // An open tab in one of Zen's tab groups goes in the group of
                // that name here.
                if let group = tab["groupId"] as? String, let name = groupNames[group] ?? folders[group]?.name {
                    let box = openGroups[space]?[group] ?? {
                        let made = Box(title: name)
                        root.nodes.append(.box(made))
                        openGroups[space, default: [:]][group] = made
                        return made
                    }()
                    box.nodes.append(.item(item))
                } else {
                    root.nodes.append(.item(item))
                }
            }
        }

        var spaces: [ArcSidebar.Space] = []
        for raw in rawSpaces {
            guard let id = raw["uuid"] as? String else { continue }
            let name = named(raw["name"] as? String) ?? "Space"
            // An emoji, or one of Zen's own pictures by its address
            // (chrome://browser/skin/zen-icons/selectable/star.svg).
            let icon = named(raw["icon"] as? String)
            let isPicture = icon.map { $0.contains("/") || $0.contains(":") } ?? false
            let picture = isPicture ? icon.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } : nil
            let emoji = isPicture ? nil : icon
            var space = ArcSidebar.Space(name: name, emoji: emoji, symbol: Arc.symbol(emoji: emoji, arcIcon: picture, name: name),
                                         profile: profile((raw["containerTabId"] as? Int) ?? 0),
                                         pinned: pinned[id].map(nodes) ?? [])
            space.open = open[id].map(nodes) ?? []
            spaces.append(space)
        }

        // Every profile is given its own list, so that takeArc never falls
        // back to all of them: every Essential when Zen shows them in every
        // space, only its container's when it keeps them apart.
        var byProfile: [String: [ArcSidebar.Item]] = [:]
        for key in Set(spaces.map(\.profile)) { byProfile[key] = [] }
        for essential in essentials {
            if separateEssentials {
                byProfile[profile(essential.container), default: []].append(essential.item)
            } else {
                for key in byProfile.keys { byProfile[key, default: []].append(essential.item) }
            }
        }
        return ArcSidebar(favorites: essentials.map(\.item), favoritesByProfile: byProfile, spaces: spaces,
                          profileNames: profileNames)
    }

    /// A tab's page. A pinned tab's is the one it was pinned at, which is
    /// where Zen takes it back to; any other tab's is the one it is on.
    private static func item(of tab: [String: Any]) -> ArcSidebar.Item? {
        var entry: [String: Any]?
        if tab["pinned"] as? Bool == true {
            entry = (tab["_zenPinnedInitialState"] as? [String: Any])?["entry"] as? [String: Any]
        }
        if entry?["url"] == nil, let entries = tab["entries"] as? [Any], !entries.isEmpty {
            // "index" counts from one.
            let index = min(max(((tab["index"] as? Int) ?? entries.count) - 1, 0), entries.count - 1)
            entry = entries[index] as? [String: Any]
        }
        guard let url = page(entry?["url"] as? String) else { return nil }
        let title = named(tab["zenStaticLabel"] as? String) ?? named(entry?["title"] as? String) ?? url.host() ?? url.absoluteString
        return ArcSidebar.Item(title: title, url: url)
    }

    private struct Folder { var name: String; var parent: String?; var split: Bool }

    /// A folder while it is being filled.
    private final class Box {
        enum Entry { case item(ArcSidebar.Item), box(Box) }
        let title: String
        var nodes: [Entry] = []
        init(title: String) { self.title = title }
    }

    private static func nodes(_ box: Box) -> [ArcSidebar.Node] {
        box.nodes.compactMap { entry in
            switch entry {
            case .item(let item): return .item(item)
            case .box(let inner):
                let inside = nodes(inner)
                return inside.isEmpty ? nil : .folder(.init(title: inner.title, items: inside))
            }
        }
    }

    /// A web address, with any password in it left behind.
    private static func page(_ text: String?) -> URL? {
        guard let text, var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        parts.user = nil
        parts.password = nil
        return parts.url
    }

    private static func named(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }
}

extension ImportSource {
    /// Zen's spaces, pins and Essentials, nil for any other browser.
    func zenSidebar(profile: String?) -> ArcSidebar? {
        guard case .mozilla(let source) = self, source.name == "Zen" else { return nil }
        return Zen.sidebar(in: source, profile: profile)
    }

    func zenCounts(profile: String?) -> (spaces: Int, pinned: Int)? {
        guard case .mozilla(let source) = self, source.name == "Zen" else { return nil }
        return Zen.counts(in: source, profile: profile)
    }
}
