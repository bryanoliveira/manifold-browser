import AppKit
import SwiftUI

// Manifold: the spaces as a row of icons at the column's foot, as in Arc and
// Zen. One click goes to a space, whichever profile it is in; a right-click
// opens that space's menu. The row takes the place of the space's dot and
// the profile's badge: a space's profile is chosen in the space's own menu,
// as in Arc, and a click on a space of another profile goes there (see
// OneWindow.swift, which this turns on).
//
// On unless turned off in Settings › Spaces & Pins, and only with Spaces on
// and the column down a side with its titles. The column of icons alone
// keeps the dot. Fork/README.md says why the fork carries it.

@MainActor
enum SpaceStrip {
    nonisolated static let key = "manifold.spaceStrip"
    /// Set once the row has turned on Profiles in one window, so turning
    /// that off again is respected.
    private static let mergedKey = "manifold.spaceStrip.merged"

    static var on: Bool {
        get { Store.settings.object(forKey: key) as? Bool ?? true }
        set {
            Store.settings.set(newValue, forKey: key)
            if newValue { merge() }
        }
    }

    /// Whether the foot of this window's column shows the row.
    static func shows(_ browser: Browser) -> Bool {
        on && browser.prefs.usesSpaces && !browser.isPopup
    }

    /// Every profile's spaces in one window, once: what makes a click on a
    /// space of another profile go there.
    static func merge() {
        guard !Store.settings.bool(forKey: mergedKey) else { return }
        Store.settings.set(true, forKey: mergedKey)
        if !Shared.prefs.profilesInOneWindow { Shared.prefs.profilesInOneWindow = true }
    }

    static let cell: CGFloat = 26
    static let gap: CGFloat = 2

    /// The width the row asks for at the foot, less the dot and the badge
    /// it stands in for: what the pinned extensions there give up.
    static func taken(_ browser: Browser) -> CGFloat {
        guard shows(browser) else { return 0 }
        let replaced = (Profiles.shared.several ? 1 : 0) + 1
        return CGFloat(browser.everySpace.count - replaced) * (cell + gap)
    }

    /// The bench's `space` actions of the fork's own, on a test run:
    /// "profile" moves the space on screen to the profile named `name`;
    /// "strip" turns the row on or off (`on`).
    static func bench(_ request: [String: Any], _ browser: Browser) {
        guard Store.testing else { return }
        switch request["action"] as? String {
        case "profile":
            guard let name = request["name"] as? String,
                  let profile = Profiles.shared.list.first(where: { $0.name == name }) else { return }
            browser.moveSpace(browser.spaceID, toProfile: profile.id)
        case "strip":
            on = request["on"] as? Bool ?? true
            browser.prefs.objectWillChange.send()
        default: break
        }
    }

    // MARK: - a space's profile

    /// The Profile item in a space's menu: the profiles, the space's own
    /// checked, choosing another moves the space there. Stands in for the
    /// menu's own Profile item, which changes the window's profile.
    static func addProfileItems(to menu: NSMenu, for browser: Browser) {
        let here = browser.space
        let profiles = NSMenu()
        let fixed = here.isFirst || here.id == browser.homeSpaceID
        for profile in Profiles.shared.list {
            let choice = MenuAction.item(profile.name, checked: profile.id == here.profileID) {
                browser.moveSpace(here.id, toProfile: profile.id)
            }
            choice.isEnabled = !fixed || profile.id == here.profileID
            profiles.addItem(choice)
        }
        profiles.addItem(.separator())
        let fresh = MenuAction.item("New Profile…") {
            Ask.name("New Profile", detail: "“\(here.name)” moves into it, with sign-ins of its own.",
                     placeholder: "Work", confirm: "Create") { name in
                let made = Profiles.shared.add(named: name)
                browser.moveSpace(here.id, toProfile: made.id)
            }
        }
        fresh.isEnabled = !fixed
        profiles.addItem(fresh)
        profiles.autoenablesItems = false
        menu.addItem(.separator())
        let holder = NSMenuItem(title: "Profile: \(Profiles.shared.profile(here.profileID).name)", action: nil, keyEquivalent: "")
        holder.submenu = profiles
        if fixed { holder.toolTip = "The first space of a profile stays in it" }
        menu.addItem(holder)
    }
}

extension Browser {
    /// A space moved into another profile: every window of this profile lets
    /// go of it, as when it is deleted, and it joins the other profile's
    /// spaces, last. What it holds goes with it, being kept by the space's id:
    /// its tabs, pins and folders, and its own sign-ins if it has them. A
    /// space signed in with its profile's others is signed in with the new
    /// profile's from now on. A profile's first space stays where it is.
    func moveSpace(_ id: UUID, toProfile target: UUID) {
        guard target != profileID, id != Space.firstID, id != homeSpaceID,
              spaces.contains(where: { $0.id == id }), Profiles.shared.list.contains(where: { $0.id == target })
        else { return }
        for window in Browsers.all where window.profileID == profileID && !window.isPopup {
            if window.spaceID == id { window.enter(window.homeSpaceID) }
            window.writeSession(now: true)
            window.forget(space: id)
        }
        var all = Spaces.read()
        guard let at = all.firstIndex(where: { $0.id == id }) else { return }
        var space = all.remove(at: at)
        space.profile = target == Profile.personalID ? nil : target
        let lastOfTarget = all.lastIndex(where: { $0.profileID == target }).map { $0 + 1 } ?? all.endIndex
        all.insert(space, at: lastOfTarget)
        // Every window's list follows (see Browser.init).
        Spaces.write(all)
        // Where the space went, it stays on screen.
        if merges { Browsers.join(space: id, from: self) }
    }
}

/// Menu items that call back into Swift.
@MainActor
enum MenuAction {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }
    private static var kept: [Action] = []

    static func item(_ title: String, checked: Bool = false, _ run: @escaping () -> Void) -> NSMenuItem {
        if kept.count > 200 { kept.removeFirst(kept.count - 200) }
        let action = Action(run)
        kept.append(action)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        item.target = action
        item.state = checked ? .on : .off
        return item
    }
}

/// The row: one icon per space this window can go to, in the order of the
/// space's menu and ⌃1–⌃9. Scrolls sideways when there are more than fit.
struct SpaceStripView: View {
    @ObservedObject var browser: Browser
    /// Spaces of other profiles, read when the list changes anywhere.
    @State private var every: [Space] = []

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SpaceStrip.gap) {
                    ForEach(Array(every.enumerated()), id: \.element.id) { index, space in
                        SpaceStripIcon(browser: browser, space: space, index: index,
                                       here: !browser.makingSpace && space.id == browser.spaceID)
                            .id(space.id)
                    }
                }
            }
            .frame(maxWidth: CGFloat(every.count) * (SpaceStrip.cell + SpaceStrip.gap))
            .onChange(of: browser.spaceID) { _, id in
                withAnimation(Motion.quick) { scroller.scrollTo(id) }
            }
        }
        .onAppear {
            every = browser.everySpace
            if Profiles.shared.several { SpaceStrip.merge() }
        }
        .onChange(of: browser.spaces) { _, _ in every = browser.everySpace }
        .onReceive(NotificationCenter.default.publisher(for: Spaces.changed)) { _ in
            // A new profile is written with its first space: from then on
            // there are spaces of other profiles to list.
            DispatchQueue.main.async {
                if Profiles.shared.several { SpaceStrip.merge() }
                every = browser.everySpace
            }
        }
    }
}

private struct SpaceStripIcon: View {
    @ObservedObject var browser: Browser
    let space: Space
    let index: Int
    let here: Bool
    @State private var hovering = false

    var body: some View {
        Button { browser.switchSpace(to: space.id) } label: {
            Image(systemName: space.symbol)
                .font(.system(size: 12, weight: here ? .semibold : .medium))
                .foregroundStyle(space.tint ?? (here || hovering ? Palette.ink : Palette.muted))
                .opacity(here || hovering ? 1 : 0.75)
                .frame(width: SpaceStrip.cell, height: SpaceStrip.cell)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(here ? (space.tint.map { $0.opacity(0.18) } ?? Palette.hover)
                                   : (hovering ? Palette.hover : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(index < 9 ? "\(space.name)   ⌃\(index + 1)" : space.name)
        .accessibilityLabel(space.name)
        .accessibilityAddTraits(here ? .isSelected : [])
        .overlay(StripRightClick { menu() })
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: here)
    }

    /// The space's own menu: its name, icon, colour, profile and the rest.
    /// A space not on screen is gone to first, as the menu is about the one
    /// on screen.
    private func menu() {
        if !here { browser.switchSpace(to: space.id) }
        let id = space.id
        DispatchQueue.main.async {
            let showing = Browsers.all.first { $0.spaceID == id && !$0.tucked && !$0.isPopup } ?? browser
            SpaceMenu.show(for: showing)
        }
    }
}

/// A right-click over an icon, and only that: every other click and the
/// hover fall through to the button beneath (as Side.swift's RightClick).
private struct StripRightClick: NSViewRepresentable {
    let run: () -> Void

    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) { view.run = run }

    final class Catcher: NSView {
        var run: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) { run?() }
    }
}
