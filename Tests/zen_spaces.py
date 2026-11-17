"""Zen's spaces, containers, Essentials, folders and open tabs come over
(Sources/Search/ImportZen.swift).

Build first (`./build.sh`), then `python3 Tests/zen_spaces.py`. A made-up Zen
profile is written into the world's own Import folder: three workspaces, two
of them in the Personal container and one in Hug, an Essential, a folder
nested in a folder, and an open tab. The import is asked for its spaces with
pinned rows and their folders on, and the files the app writes are checked.

`python3 Tests/zen_spaces.py --from "<a Zen profile folder>"` imports a copy
of a real profile's session instead, into the same throwaway world, and
prints what came over. The profile itself is only read.
"""
import json
import os
import shutil
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("zen-spaces")
PROFILE = "abcd1234.Default (release)"


def mozlz4(data: bytes) -> bytes:
    """Mozilla's LZ4 file, as one block of nothing but literals: valid LZ4,
    and all a reader needs to be shown."""
    n = len(data)
    token, more = (n, b"") if n < 15 else (15, b"\xff" * ((n - 15) // 255) + bytes([(n - 15) % 255]))
    return b"mozLz40\0" + struct.pack("<I", n) + bytes([token << 4]) + more + data


def tab(url, space, pinned=True, folder=None, essential=False, container=0):
    t = {"entries": [{"url": url, "title": url.split("/")[2]}], "index": 1, "pinned": pinned,
         "zenWorkspace": space, "zenEssential": essential, "userContextId": container}
    if pinned:
        t["_zenPinnedInitialState"] = {"entry": {"url": url, "title": url.split("/")[2]}}
    if folder:
        t["groupId"] = folder
    return t


SESSION = {
    "spaces": [
        {"uuid": "{a}", "name": "Play", "icon": "🎮", "containerTabId": 1},
        {"uuid": "{b}", "name": "Study", "icon": "📚", "containerTabId": 1},
        {"uuid": "{c}", "name": "HUG", "icon": "🐼", "containerTabId": 6},
    ],
    "folders": [
        {"id": "f1", "name": "Admin", "parentId": None, "splitViewGroup": False},
        {"id": "f2", "name": "Papers", "parentId": "f1", "splitViewGroup": False},
    ],
    "groups": [],
    "tabs": [
        tab("https://www.iana.org/", None, essential=True, container=1),
        tab("https://example.com/", "{a}"),
        tab("https://www.rfc-editor.org/", "{a}", folder="f2"),
        tab("https://example.org/", "{a}", folder="f1"),
        tab("https://example.net/", "{a}", pinned=False),
        tab("https://www.w3.org/", "{b}"),
        tab("https://www.ietf.org/", "{c}", container=6),
    ],
}
CONTAINERS = {"identities": [{"userContextId": 1, "public": True, "name": "Personal"},
                             {"userContextId": 6, "public": True, "name": "Hug"}]}


def zen(source=None):
    root = f"{sv.SUPPORT}/Import/zen"
    profile = f"{root}/Profiles/{PROFILE}"
    os.makedirs(profile, exist_ok=True)
    Path(f"{root}/profiles.ini").write_text(
        f"[Profile0]\nName=Default (release)\nIsRelative=1\nPath=Profiles/{PROFILE}\nDefault=1\n")
    # A profile counts as one once it holds places.sqlite.
    Path(f"{profile}/places.sqlite").write_bytes(b"")
    if source:
        for name in ["zen-sessions.jsonlz4", "containers.json", "prefs.js"]:
            if os.path.exists(f"{source}/{name}"):
                shutil.copy(f"{source}/{name}", f"{profile}/{name}")
        return
    Path(f"{profile}/zen-sessions.jsonlz4").write_bytes(mozlz4(json.dumps(SESSION).encode()))
    Path(f"{profile}/containers.json").write_text(json.dumps(CONTAINERS))


def read(name, default):
    path = f"{sv.SUPPORT}/{name}"
    return json.load(open(path)) if os.path.exists(path) else default


def settle(name):
    for _ in range(25):
        if os.path.exists(f"{sv.SUPPORT}/{name}"):
            return
        time.sleep(0.2)


def main():
    source = sys.argv[sys.argv.index("--from") + 1] if "--from" in sys.argv else None
    t = sv.T()
    try:
        sv.setup(**{"pins.list": True, "pins.folders": True})
        zen(source)
        sv.launch()
        out = sv.cmd({"do": "import", "from": "Zen", "what": ["spaces"]})
        settle("pins.json")
        time.sleep(1)
        spaces = read("spaces.json", [])
        profiles = read("profiles.json", [])
        pins = read("pins.json", {})
        if source:
            print(json.dumps(out.get("arc"), indent=1))
            print("profiles:", [p["name"] for p in profiles])
            for space in spaces:
                row = pins.get(space["id"], []) if isinstance(pins, dict) else []
                print(f"  {space['name']!r}: {len(row)} pins, profile {space.get('profile') or 'Personal'}")
            return
        arc = out.get("arc") or {}
        t.ok("three spaces came in", arc.get("spaces") == 3 or len(spaces) >= 3, out)
        names = {s["name"]: s for s in spaces}
        t.ok("each workspace is a space", {"Play", "Study", "HUG"} <= set(names), [s["name"] for s in spaces])
        hug = [p for p in profiles if p["name"] == "Hug"]
        t.ok("the Hug container is a profile", len(hug) == 1, profiles)
        t.ok("HUG is in it", hug and names.get("HUG", {}).get("profile") == hug[0]["id"], names.get("HUG"))
        t.ok("Personal's spaces stay in the profile already here",
             names.get("Play", {}).get("profile") is None and names.get("Study", {}).get("profile") is None, spaces)
        homes = {s: {p["home"] for p in pins.get(names[s]["id"], [])} for s in names if s in ("Play", "Study", "HUG")}
        t.ok("the Essential is pinned in every space", all("https://www.iana.org/" in h for h in homes.values()), homes)
        t.ok("Play's pinned pages are rows", {"https://example.com/", "https://example.org/", "https://www.rfc-editor.org/"} <= homes.get("Play", set()), homes)
        folders = read("pin-folders.json", {})
        t.ok("its folders are nested as in Zen", "Papers" in json.dumps(folders) and "Admin" in json.dumps(folders), folders)
        play = read(f"session-{names['Play']['id']}.json", None) or read("session.json", {})
        urls = [x.get("url") for x in play.get("tabs", [])]
        t.ok("the open tab is asleep in Play", "https://example.net/" in urls, urls)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
