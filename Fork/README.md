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

- **One page in every window.** Turned on in Settings › Tabs › One page in every window, from the next launch. A
  space's tabs belong to the space, so two windows showing a space show the same tabs, and each page is in memory
  once. The window in front holds a page live. Another window showing the same page draws a picture of it, four
  times a second, and takes the page itself, with no reload, when it comes to the front. Split View's pages do the
  same. Opening, closing, moving and grouping tabs in one window happen in the other. Closing a window keeps its
  tabs with their space, as in Arc. A window that comes back to a space finds what was opened there meanwhile. Off,
  each window holds its own tabs, as in upstream.
- **Pins at the top, the same in every space.** The squares at the top of the column are each profile's, as Arc's
  favourites are: every space of a profile shows the same ones, and each is one page across the spaces that share
  the profile's sign-ins, so Gmail pinned there loads once. A space with sign-ins of its own keeps a page of its
  own for them. A page pinned as a square is shared at once; Only in This Space makes a square a row of that space,
  since the pinned rows stay each space's own. Turned on, the squares your spaces already had become one set, a
  page pinned in several spaces kept once: an import from Zen or Arc gives every space its own copy of the
  favourites, and this merges them. On by default, in Settings › Spaces & Pins › Pins at the top, the same in every
  space; it needs Spaces on.
- **Spaces at the foot of the column, as in Arc and Zen.** Every space is an icon in a row under the tabs, and
  one click goes to it, whichever profile it is in. A right-click opens the space's menu. The row stands in for
  the single space button and the profile badge. A space's profile is chosen in its own menu, under Profile, as in
  Arc: choosing another moves the space there with its tabs, pins and folders. A profile's first space stays in
  it. Listing every profile's spaces needs Settings › Profiles in one window, which the row turns on once. The row
  has its own switch in Settings › Spaces & Pins, on by default. With the column showing icons only, the single
  space button stays.

- **Manifold's name and icon.** `./build.sh` names the app Manifold (Manifold-<branch> for a dev build), in the
  Dock, the menu bar, ⌘Tab and Finder. The icon is a lowercase m drawn as one ribbon, `Fork/mark.svg`, on upstream's
  plate and in its colours, Dark and Tinted Dock styles included. The bundle id and the data folders stay
  Search's, so your settings, tabs and sign-ins carry over. Inside the app, the mark and the name are Manifold's
  where you see them daily: the window's title, Quit, Settings › About, the default-browser lines and the welcome.
  Send Feedback opens a new issue on this fork's GitHub instead of writing to Office Commun, and Settings no
  longer shows "Install updates on its own". The rest of the app's text still says Search. Renaming all of its
  about 160 strings would turn upstream's edits to those lines into merge conflicts.

- **Handoff from Safari on iPhone and iPad.** A page open in Safari on your iPhone shows at the end of the Mac's
  Dock under Manifold, when Manifold is the Mac's default browser, and a click opens it here as a link from another
  app would. Both devices need the same Apple Account, Bluetooth and Wi-Fi on, and Handoff allowed (Mac: System
  Settings › General › AirDrop & Handoff; iPhone: Settings › General › AirPlay & Continuity). Apple's iCloud sync
  of tabs and bookmarks is closed to other apps; Handoff is the part of it a browser can take.

## Roadmap

Everything planned so far is built. Possible next steps, none started:

- Handoff to the iPhone, which Apple allows only for apps signed with a developer team.

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
- `Updater.swift`: two lines in `check` that hand a found release to `ManifoldUpdates.swift`;
- `build.sh`: the name people see, Manifold, in four lines, and the mark copied into the app; `Icon/icon.swift`: the
  mark from `Fork/mark.svg` when it is there;
- for the name and mark inside the app (`Brand.swift`): two lines in `Design.swift` for the mark, and about ten
  strings in `App.swift`, `WindowTitle.swift`, `Settings.swift` and `Welcome.swift`; one line in `Links.swift` for
  feedback, and two in `SettingsIndex.swift` that hide the install switch;
- `build.sh`: one plist key, NSUserActivityTypes, for Handoff (`Handoff.swift`);
- for pins at the top (`SharedPins.swift`): three lines in `reconcilePins` in `Browser.swift` (a shared pin's tab
  taken from another space, and left open while another space holds it), the same check in the two lines of
  `Spaces.swift` that put a space's row away, one line in `Links.swift` that starts it at launch, and its switch in
  `SettingsIndex.swift` and `Settings.swift`;
- for one page in every window (`SharedPages.swift`): in `Browser.swift`, the row's three setters tell it of a
  change, `restoreSession` and `loadRow` take the row another window has, `readRow` and `writeRow` use the space's
  file, and closing a window leaves tabs another window holds; in `Spaces.swift`, coming back to a space takes the
  live row, and putting a space away leaves tabs held elsewhere; `Stage.swift` asks before taking a page from
  another window and keeps the picture; `Windows.swift` tells it which window came to the front; `Sleep.swift` and
  `Closing.swift` keep awake and open a tab another window shows; `Extensions.swift` tells extensions of a tab in
  one window; its switch is in `SettingsIndex.swift` and `Settings.swift`. Every hook does nothing with the switch
  off;
- for the row of spaces (`SpaceStrip.swift`): the foot of the column in `Side.swift` (the row in place of the
  space button and the badge, and the room it takes from pinned extensions), the space menu's Profile item in
  `Spaces.swift`, its switch in `SettingsIndex.swift` and `Settings.swift`, and one line in `Bench.swift` that
  hands the fork's own test actions to it.

To bring in upstream's changes, when Manifold says upstream released a new version:

```
git fetch upstream
git merge upstream/main
swift build && swift test --filter "ImportZen|ManifoldUpdates|Handoff" \
  && ./build.sh && python3 Tests/space_strip.py && python3 Tests/shared_pages.py && python3 Tests/shared_pins.py \
  && python3 Tests/zen_spaces.py
```

Then quit the browser and run `./build.sh`. It rebuilds `build/Search.app` in place, and the next launch is the new
version. Your tabs, settings and sign-ins live outside the app, so they stay. Upstream's test scripts also launch
`build/Search.app`, each in a hidden test world of its own, so they never touch your browser's data.

## Limitations

- With pins at the top shared, moving a square to another space, or dropping one into a space, leaves it where it
  was: it is in every space already. A test run starts with the switch off, so upstream's own tests check
  upstream's pins; the fork's tests turn it on.
- Upstream's `Tests/pin_tiers.py` has one check that fails on upstream's own code too, "Clear reuses your empty tab
  in a group".

- One page in every window takes effect at the next launch, both when turned on and off.
- A click on a page's picture brings its window to the front. The page takes the click after that.
- A picture is redrawn four times a second, so a video seen in it moves in steps.
- Handoff from the iPhone was built from Apple's documentation and checked as far as the app's own side goes. It
  has not been tried with a real iPhone yet.

## Releasing

`Fork/release.sh` builds with upstream's `build.sh` and renames the app to Manifold. It signs the app ad hoc,
packs a disk image and a ZIP, tags the commit and publishes a GitHub release. The tag is upstream's version plus
a counter, such as `v1.0.14-manifold.1`. `Fork/release.sh --dry-run` builds and packs into `build/manifold/`
without publishing anything.

The release keeps Search's bundle id and data folders, so it uses the settings, tabs and sign-ins of any Search
already on the Mac. Because it has no Team ID, upstream's updater never replaces it with upstream's Search.
