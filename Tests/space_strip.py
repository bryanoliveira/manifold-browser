"""The spaces at the foot of the column, and a space moved to another profile
(Sources/Search/SpaceStrip.swift).

Build first (`./build.sh`), then `python3 Tests/space_strip.py`. A hidden probe
in a world of its own gets three spaces and a second profile, and is checked
for:
- Profiles in one window turned on by the row once there are two profiles;
- the space's menu offering the space's own profile, in place of the window's;
- a space with a page in it moved to the other profile: gone from this
  profile's list, last in the other's, its page with it, on screen there;
- a profile's first space staying where it is;
- pictures of the column with the row on and off, in the scratch folder
  given with --pictures (nothing is kept without it).
"""
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("space-strip")


def space(action="list", **f):
    return sv.cmd({"do": "space", "action": action, **f})


def spaces_file():
    return json.load(open(f"{sv.SUPPORT}/spaces.json"))


def profiles_file():
    return json.load(open(f"{sv.SUPPORT}/profiles.json"))


def wait(check, within=5):
    for _ in range(int(within / 0.1)):
        if check(): return True
        time.sleep(0.1)
    return check()


def picture(name, folder):
    if not folder: return
    out = sv.cmd({"do": "picture", "path": f"{folder}/{name}.png", "page": False})
    print(f"  picture: {folder}/{name}.png", "" if "error" not in out else out)


def main():
    folder = sys.argv[sys.argv.index("--pictures") + 1] if "--pictures" in sys.argv else None
    t = sv.T()
    try:
        sv.setup(spaces=True, sidebar=True)
        sv.launch()
        space("new", name="Work")
        space("new", name="Play")
        made = sv.cmd({"do": "profile", "action": "new", "name": "Hug"})
        t.ok("a second profile", "id" in made, made)
        merged = wait(lambda: os.popen(f"defaults read {sv.SUITE} profiles.oneWindow 2>/dev/null").read().strip() == "1")
        t.ok("the row turned Profiles in one window on", merged)

        # Work, with a page in it.
        space("go", index=2)
        tab = next(x for x in sv.cmd({"do": "tabs"})["tabs"] if not x.get("bench"))
        sv.cmd({"do": "go", "id": tab["id"], "url": f"{sv.BASE}/long"})
        wait(lambda: any("/long" in (x.get("url") or "") for x in sv.cmd({"do": "tabs"})["tabs"]))
        out = space()
        t.ok("on Work", out.get("current") == "Work", out.get("current"))
        titles = [m["title"] for m in out["menu"]]
        t.ok("the menu offers the space's profile", "Profile: Personal" in titles, titles)
        t.ok("every profile's spaces are listed", out.get("every") == ["Personal", "Work", "Play", "Hug"], out.get("every"))
        picture("row-on", folder)

        hug = next(p["id"] for p in profiles_file() if p["name"] == "Hug")
        space("profile", name="Hug")
        moved = wait(lambda: next((s for s in spaces_file() if s["name"] == "Work"), {}).get("profile") == hug)
        t.ok("Work is in Hug now", moved, spaces_file())
        names = [s["name"] for s in spaces_file()]
        t.ok("last among Hug's spaces", names.index("Work") > names.index("Hug"), names)
        # Hug's window takes this one's place; the bench is asked of it by number.
        shown = [w for w in sv.cmd({"do": "windows"})["windows"] if not w.get("tucked")]
        t.ok("Hug's window is the one on screen", [w["profile"] for w in shown] == ["Hug"], shown)
        n = shown[0]["n"] if shown else 1
        out = space(window=n)
        t.ok("and Work is on screen in it", out.get("current") == "Work", out.get("current"))
        t.ok("the list follows", out.get("every") == ["Personal", "Play", "Hug", "Work"], out.get("every"))
        urls = [x.get("url") or "" for x in sv.cmd({"do": "tabs", "window": n})["tabs"]]
        t.ok("its page came with it", any("/long" in u for u in urls), urls)
        titles = [m["title"] for m in out["menu"]]
        t.ok("its menu says Hug", "Profile: Hug" in titles, titles)

        # A profile's first space stays.
        space("go", index=1)
        space("profile", name="Hug")
        time.sleep(0.5)
        personal = next(s for s in spaces_file() if s["name"] == "Personal")
        t.ok("Personal's first space stays in Personal", personal.get("profile") is None, personal)

        space("strip", on=False)
        time.sleep(0.5)
        picture("row-off", folder)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
