"""The pins at the top of the column are each profile's, one page wherever they
show (Sources/Search/SharedPins.swift).

Build first (`./build.sh`), then `python3 Tests/shared_pins.py`. A hidden probe
in a world of its own, driven through ./bench. First, with Settings › Pins at
the top, the same in every space off, one page is pinned as a square in two
spaces, as an import from Arc or Zen leaves it, and a row in one. Then, on,
after a relaunch:
- the two squares are one pin every space shows, and the row stays its
  space's own;
- that pin is one tab in both spaces' rows, not two;
- a space with sign-ins of its own has a tab of its own for it;
- a page pinned as a square from then on is shared at once;
- Only in This Space on a square makes it a row of that space.
"""
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("shared-pins")


def pins():
    return sv.cmd({"do": "space", "action": "pins"})


def wait(check, within=6):
    for _ in range(int(within / 0.2)):
        if check(): return True
        time.sleep(0.2)
    return check()


def real(url):
    """A page in a new tab of the space on screen, not a bench tab."""
    sv.cmd({"do": "bookmark", "url": url, "new": True})
    time.sleep(0.5)
    return next(x for x in sv.cmd({"do": "tabs"})["tabs"] if x.get("active"))["id"]


def main():
    t = sv.T()
    long, tall, iana = f"{sv.BASE}/long", f"{sv.BASE}/tall", f"{sv.BASE}/asker"
    try:
        sv.setup(**{"spaces": True, "manifold.profilePins": False, "pins.list": True})
        sv.launch()
        sv.cmd({"do": "pin", "id": real(long)})
        sv.cmd({"do": "space", "action": "new", "name": "Work"})
        sv.cmd({"do": "pin", "id": real(long)})
        sv.cmd({"do": "pin", "id": real(tall), "listed": True})
        own = pins()["own"]
        t.ok("off: each space has its own square", own.get("Personal") == [long] and long in own.get("Work", []), own)

        sv.quit()
        time.sleep(1)
        os.system(f"defaults write {sv.SUITE} manifold.profilePins -bool true")
        sv.launch()
        out = pins()
        t.ok("on: the squares are one pin every space shows", out["shared"] == [long], out)
        t.ok("the row stays Work's own", out["own"].get("Work") == ["row " + tall] and out["own"].get("Personal") == [], out["own"])

        sv.cmd({"do": "space", "action": "go", "index": 2})
        def same():
            rows = pins()["rows"]
            return len(rows.get("Personal", [])) >= 1 and len(rows.get("Work", [])) >= 1 and rows["Personal"][0] == rows["Work"][0]
        t.ok("one tab for it in both spaces' rows", wait(same), pins()["rows"])

        sv.cmd({"do": "space", "action": "new", "name": "Apart", "fresh": True})
        rows = pins()["rows"]
        t.ok("a space with its own sign-ins has its own tab",
             wait(lambda: len(pins()["rows"].get("Apart", [])) == 1 and pins()["rows"]["Apart"][0] != pins()["rows"]["Personal"][0]),
             pins()["rows"])

        sv.cmd({"do": "space", "action": "go", "index": 1})
        fresh = real(iana)
        sv.cmd({"do": "pin", "id": fresh})
        t.ok("a square pinned now is shared at once", wait(lambda: iana in pins()["shared"]), pins())
        t.ok("and is in no space's own list", wait(lambda: all(iana not in v for v in pins()["own"].values())), pins()["own"])

        sv.cmd({"do": "pin", "id": fresh, "everywhere": False})
        t.ok("Only in This Space makes it a row of this space",
             wait(lambda: iana not in pins()["shared"] and "row " + iana in pins()["own"].get("Personal", [])), pins())
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
