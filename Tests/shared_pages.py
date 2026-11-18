"""One page in every window (Sources/Search/SharedPages.swift).

Build first (`./build.sh`), then `python3 Tests/shared_pages.py`. A hidden probe
in a world of its own, driven through ./bench, is checked for, with Settings ›
One page in every window on:
- a second window on the same space holding the same tabs, not copies;
- the page live in the window in front only, a picture of it in the other;
- the live page moving to whichever window comes to the front, never
  reloaded (a mark set in the page by script is still there);
- a tab opened in one window there in the other, and closed in one, gone
  from both;
- a window that went to another space finding, back, the tab opened
  meanwhile in the one it left;
- closing a window leaving the tabs with their space;
- both windows sharing their row again after a relaunch;
and with the switch off, each window holding its own tabs, as upstream does.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("shared-pages")
ON = {"manifold.sharedPages": True, "spaces": True}


def shared():
    return sv.cmd({"do": "space", "action": "shared"})["windows"]


def wait(check, within=6):
    for _ in range(int(within / 0.2)):
        if check(): return True
        time.sleep(0.2)
    return check()


def mark(tab, window=None):
    req = {"do": "eval", "id": tab, "js": "window.__mark = window.__mark || 'kept'; window.__mark"}
    if window: req["window"] = window
    return sv.cmd(req).get("value")


def read_mark(tab):
    return sv.cmd({"do": "eval", "id": tab, "js": "window.__mark || 'reloaded'"}).get("value")


def main():
    t = sv.T()
    try:
        sv.setup(**ON)
        sv.launch()
        tab = next(x for x in sv.cmd({"do": "tabs"})["tabs"] if not x.get("bench"))["id"]
        sv.cmd({"do": "go", "id": tab, "url": f"{sv.BASE}/long"})
        wait(lambda: not sv.cmd({"do": "tabs"})["tabs"][0].get("loading") and "/long" in sv.cmd({"do": "tabs"})["tabs"][0].get("url", ""))
        t.ok("the page is marked", mark(tab) == "kept")

        sv.cmd({"do": "windows", "action": "new"})
        wait(lambda: len(shared()) == 2)
        w = shared()
        t.ok("two windows", len(w) == 2, w)
        t.ok("the second holds the same tab, not a copy", w[1]["tabs"] == w[0]["tabs"] == [tab], w)
        t.ok("the page is live in one window only",
             sorted([len(x["live"]) for x in w]) == [0, 1], w)
        t.ok("and a picture in the other", sum(x["pictures"] for x in w) == 1, w)

        for n in (1, 2, 1):
            sv.cmd({"do": "windows", "action": "front", "n": n})
            moved = wait(lambda: shared()[n - 1]["live"] == [tab])
            t.ok(f"window {n} in front holds it live", moved, shared())
        t.ok("never reloaded on the way", read_mark(tab) == "kept")

        opened = sv.cmd({"do": "open", "url": f"{sv.BASE}/tall"}).get("id")
        t.ok("a tab opened in one window is in the other",
             wait(lambda: all(opened in x["tabs"] for x in shared())), shared())
        sv.cmd({"do": "close", "id": opened})
        t.ok("and closed there, gone from both",
             wait(lambda: all(opened not in x["tabs"] for x in shared())), shared())

        # Window 2 goes to another space; a tab opened meanwhile in the space it
        # left is there when it comes back, the same tab.
        sv.cmd({"do": "space", "action": "new", "name": "Work", "window": 2})
        wait(lambda: shared()[1]["space"] == "Work")
        work = shared()[1]["tabs"][0]
        t.ok("window 2 on Work, window 1 still on Personal",
             [x["space"] for x in shared()] == ["Personal", "Work"], shared())
        sv.cmd({"do": "windows", "action": "front", "n": 1})
        later = sv.cmd({"do": "open", "url": f"{sv.BASE}/tall", "window": 1}).get("id")
        wait(lambda: later in shared()[0]["tabs"])
        sv.cmd({"do": "space", "action": "go", "index": 1, "window": 2})
        back = wait(lambda: shared()[1]["space"] == "Personal" and later in shared()[1]["tabs"])
        t.ok("back on Personal, window 2 has the tab opened while it was away", back, shared())
        t.ok("the same row as window 1's", shared()[0]["tabs"] == shared()[1]["tabs"], shared())
        sv.cmd({"do": "space", "action": "go", "index": 2, "window": 2})
        wait(lambda: shared()[1]["space"] == "Work")
        t.ok("and Work kept its own tab", shared()[1]["tabs"] == [work], shared())
        sv.cmd({"do": "space", "action": "go", "index": 1, "window": 2})
        wait(lambda: shared()[1]["space"] == "Personal")
        sv.cmd({"do": "close", "id": later})

        # A relaunch brings both windows back on the same row.
        sv.quit()
        time.sleep(1)
        sv.launch()
        wait(lambda: len(shared()) == 2)
        w = shared()
        t.ok("after a relaunch, two windows again", len(w) == 2, w)
        t.ok("sharing one row", len(w) == 2 and w[0]["tabs"] == w[1]["tabs"] and len(w[0]["tabs"]) >= 1, w)

        sv.cmd({"do": "windows", "action": "close", "n": 2})
        wait(lambda: len(shared()) == 1)
        w = shared()
        t.ok("closing a window keeps the tabs with their space", len(w) == 1 and len(w[0]["tabs"]) >= 1, w)

        # Off: each window its own tabs, as upstream has it.
        sv.setup()
        sv.launch()
        sv.cmd({"do": "windows", "action": "new"})
        wait(lambda: len(shared()) == 2)
        w = shared()
        t.ok("switched off, the second window's tabs are its own",
             len(w) == 2 and not set(w[0]["tabs"]) & set(w[1]["tabs"]) and sum(x["pictures"] for x in w) == 0, w)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
