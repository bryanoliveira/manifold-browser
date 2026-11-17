# Manifold: this fork of Search

Manifold is [Search](https://github.com/driceroland/Search), a WebKit browser for the Mac, with a few additions.
Everything outside this folder is upstream's code. This page covers what the fork changes, how to release it,
and how to bring in upstream's updates.

## What the fork adds

- **Zen's spaces and profiles.** Settings › Import, then Zen, brings over Zen's workspaces as spaces. Each space
  keeps its pinned tabs, nested folders and open tabs. Essentials become pins, and containers become profiles.
  The next section says how each part maps.

- **News of upstream releases, without installing them.** Search checks officecommun.com at launch and every hour
  for a newer version, and installs it on its own. Manifold still checks. When upstream is ahead, a line at the foot
  of the window says "Upstream released Search 1.0.15. Pull it into your copy to update." Nothing is downloaded or
  installed, because upstream's build would replace this fork with plain Search. Versions are compared by number.
  Upstream compares build times, and any build made here after upstream's release would hide that release. The
  Settings switch "Install updates on its own" has no effect in Manifold.

## Roadmap

In order. Each item says what upstream already has or plans in the same area, so the fork doesn't build it twice.
Upstream's own list is [ROADMAP.md](../ROADMAP.md).

1. **One page in several windows at once, held in memory once.** Today a tab belongs to one window. Upstream plans
   "Tabs shared across windows" ([#417](https://github.com/driceroland/Search/issues/417), under Later): a space's
   tabs shown in any window, with a stand-in wherever the tab is open in another window, as Arc does. This item
   goes further, with the page live in each window. A web view can be drawn in only one window at a time. So the
   second window either shows a live picture of the first, or the page moves to whichever window you are using.
   That choice comes first.
2. **Sync with Safari on iPhone and iPad.** Upstream keeps sync between Macs only. Since 17 November 2026,
   `Sync.swift` writes spaces, pins, bookmarks and settings into a folder you choose, such as one in iCloud Drive.
   Upstream lists accounts and sync across devices under "Not on the list". Safari syncs your devices through
   Apple's own iCloud service, which other apps can't use. What a Mac app can reach is Safari's files on this Mac,
   with Full Disk Access. Those hold Safari's bookmarks and a copy of the tabs open on your other devices. Which way
   this can work, and whether Safari keeps what another app writes there, is the first thing to find out.
3. **Rename Search to Manifold, with an icon of its own.** Releases already show Manifold in the Dock, the menu bar
   and Finder, but a plain `./build.sh` still says Search, and so does the app inside. The bundle id and the data
   folder stay Search's, so your data carries over. Three parts, from cheapest to keep in step with upstream:
   - **The icon.** `Icon/icon.swift` draws upstream's mark. A fork icon drawn by a file in `Fork/` and swapped in
     after the build never conflicts with upstream.
   - **The name `./build.sh` gives the app, and the mark drawn inside it.** Your daily build should say Manifold too.
     The mark is `Logomark` in `Design.swift`, used by the welcome screens and Settings. Each is a small hook.
   - **"Search" in the app's own text.** About 160 strings in 47 files say Search, in menus, Settings and messages.
     Renaming them in place makes every upstream edit to one of those lines a merge conflict. How to avoid that is
     the design question for this part.
4. **A space switcher at the foot of the column, as in Zen and Arc.** Each space is an icon in a row under the
   tabs, and one click goes to it. Today the spaces are reached by swiping or scrolling through them, or through
   the space's menu, which takes two clicks. The row has no profile button: a space's profile is chosen in the
   space's own settings, as in Arc, and clicking a space of another profile goes there.

## How Zen maps onto Search

Zen keeps its spaces, tabs and folders in `zen-sessions.jsonlz4`, inside each Firefox profile folder. That file is
JSON compressed with LZ4 behind an 8-byte `mozLz40` header. Zen lists its containers in `containers.json`. A
container is a cookie jar of its own, so a site you sign in to in one container is signed out in another. Search
calls the same thing a profile.

| In Zen | In Search |
|---|---|
| A workspace | A space with the same name. Its emoji picks the nearest of Search's space icons. |
| The container most of your workspaces open in | The profile you already have. No new profile is made for it. |
| Any other container a workspace opens in | A new profile with the container's name, holding that workspace |
| Essentials | Pins in every space, or only in their container's spaces when Zen keeps Essentials apart by container |
| A pinned tab | A pin at the address it was pinned at, which is where Zen takes it back to |
| A folder, nested or not | A tab group, or a folder of pinned rows when Settings › Spaces & Pins › Folders in pinned rows is on. The import sheet offers to turn that on. |
| An open tab | An asleep tab at the end of its space's row |

Glance tabs, the empty placeholders Zen keeps in empty folders, live-folder items and non-web pages stay behind.
A page pinned twice in one space comes in once. Running the import again adds only what is missing.

Zen's bookmarks, history and saved passwords were already imported by upstream, through its Firefox reader.

`python3 Tests/zen_spaces.py --from "<a Zen profile folder>"` imports a copy of a real profile into a throwaway
test world and prints what came over. Your own browser data is never touched. On the Zen profile this was built
against, it brought 6 spaces, 2 new profiles, about 1,950 pins and 71 open tabs.

## Keeping up with upstream

The fork adds new files rather than editing upstream's. The Zen import lives in `Sources/Search/ImportZen.swift`. Its
tests are `Tests/SearchTests/ImportZenTests.swift` and `Tests/zen_spaces.py`. Upstream files carry only small hooks:

- `ImportArc.swift`: two optional fields on the sidebar model, and a fallback to Zen in the two functions that ask
  for Arc's sidebar;
- `Browser.swift`: in `takeArc`, profile names taken from the sidebar, and a space's open tabs added after its
  pinned ones;
- `ImportPanel.swift`: three strings that said "Arc" now say the browser's name;
- `Updater.swift`: two lines in `check` that hand a found release to `ManifoldUpdates.swift`.

To bring in upstream's changes, when Manifold says upstream released a new version:

```
git fetch upstream
git merge upstream/main
swift build && swift test --filter "ImportZen|ManifoldUpdates"
```

Then quit the browser and run `./build.sh`. It rebuilds `build/Search.app` in place, and the next launch is the new
version. Your tabs, settings and sign-ins live outside the app, so they stay. Upstream's test scripts also launch
`build/Search.app`, each in a hidden test world of its own, so they never touch your browser's data.

## Releasing

`Fork/release.sh` builds with upstream's `build.sh` and renames the app to Manifold. It signs the app ad hoc,
packs a disk image and a ZIP, tags the commit and publishes a GitHub release. The tag is upstream's version plus
a counter, such as `v1.0.14-manifold.1`. `Fork/release.sh --dry-run` builds and packs into `build/manifold/`
without publishing anything.

The release keeps Search's bundle id and data folders, so it uses the settings, tabs and sign-ins of any Search
already on the Mac. Because it has no Team ID, upstream's updater never replaces it with upstream's Search.
