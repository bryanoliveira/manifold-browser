#!/usr/bin/env python3
"""Search's name, made Manifold's: the one rename the fork keeps, as rules.

Upstream's code says "Search" wherever it names the browser, and
com.officecommun.search wherever it names the app to macOS. The fork's tree is
upstream's with this rename applied, so every merge from upstream brings new
lines to rename and, where upstream changed a renamed line, a conflict that is
only the rename. This script does both, the same way every time.

    python3 Fork/rebrand.py apply           rename everything in scope, in place
    python3 Fork/rebrand.py check           what `apply` would change, changing nothing
    python3 Fork/rebrand.py resolve         settle every merge conflict that is only the
                                            rename; the others are left as they are
    python3 Fork/rebrand.py test            the rules' own checks

What it renames, in the files listed under FILES:
- the word Search, as the browser's name, inside the strings of Swift code
  (comments keep their words), and on every line of the shell and Python
  scripts and the AppleScript dictionary that isn't a comment;
- com.officecommun.search, the bundle id, to io.szero.manifold, and every
  identifier made from it.
What it leaves, under KEEP: Search as a verb or a feature ("Search Tabs…",
"Search with Google", "Brave Search"), the files named Search (Search.sdef, the
entitlements, the Swift package's own target), the identifiers that check
upstream's signed files (its update feed and AI engine), and the places that mean
upstream on purpose ("a fork of Search", "Upstream released Search").
Upstream's documents (README, CHANGELOG, ROADMAP, NOTES) describe upstream, and
are not in scope.

A merge: `git merge upstream/main`, then `python3 Fork/rebrand.py resolve`,
then `python3 Fork/rebrand.py apply` for the lines upstream added; Fork/README.md
has the whole routine.
"""
import glob
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FILES = [
    "Sources/Search/*.swift",
    "Tests/SearchTests/*.swift",
    "Tests/*.py",
    "build.sh",
    "fresh.sh",
    "bench",
    "bench-mcp",
    "Search.sdef",
]

OLD_ID, NEW_ID = "com.officecommun.search", "io.szero.manifold"
# Identifiers of upstream's own signed files, checked against upstream's
# signature: renaming them would refuse upstream's feed and AI engine.
KEPT_IDS = r"\.appcast|\.ai-engine"

# Search where it isn't the browser's name: each pattern matches the word
# Search alone, with what around it tells.
KEEP = [
    r"(?<=Brave )Search",
    r"Search(?= (?:Tabs|a site|bookmarks|commands|everywhere|in a new tab|in this tab|notifications|options|or enter|sites|the tabs|unavailable|with)\b)",
    r"Search(?=\.(?:zip|sdef|entitlements|passkeys|provisionprofile)\b)",
    r"(?<=Sources/)Search\b",
    r"(?<=show-bin-path\)/)Search\b",
    r"(?<=/\* )Search(?=:)",
    r"(?<=Not a )Search(?= message)",
    r"(?<=fork of )Search\b",
    r"(?<=Upstream released )Search\b",
    r"(?<=© Office Commun · )Search\b",
    r"Search(?= from searchbrowser)",
]
# Whole strings of Swift that are Search the verb, or names nothing sees.
KEEP_LINES = [
    r'prompt = "Search"',
    r'"Search \\\(site\.',
    r'WKContentWorld\.world\(name: "Search"\)',
]

WORD = re.compile(r"\bSearch\b")


def rename(text):
    """The rename on a piece of text that is all to be renamed: a string's
    contents, or a script's line."""
    kept = set()
    for pattern in KEEP:
        for m in re.finditer(pattern, text):
            kept.add(m.start())
    text = WORD.sub(lambda m: m.group(0) if m.start() in kept else "Manifold", text)
    return re.sub(re.escape(OLD_ID) + r"(?!(?:" + KEPT_IDS + r")\b)", NEW_ID, text)


# MARK: - Swift: only what is inside a string

def string_spans(src):
    """The spans of a Swift file that are inside strings, interpolations left
    out: "...", \"\"\"...\"\"\", raw strings #"..."#, and the strings inside an
    interpolation. Comments and regex literals (#/.../#) are code."""
    spans, i, n = [], 0, len(src)
    stack = [["code", None]]
    start = 0
    while i < n:
        top = stack[-1]
        if top[0] == "code":
            if src.startswith("//", i):
                j = src.find("\n", i)
                i = n if j < 0 else j
                continue
            if src.startswith("/*", i):
                depth, i = 1, i + 2
                while i < n and depth:
                    if src.startswith("/*", i): depth, i = depth + 1, i + 2
                    elif src.startswith("*/", i): depth, i = depth - 1, i + 2
                    else: i += 1
                continue
            c = src[i]
            if c == "#":
                k = 0
                while i + k < n and src[i + k] == "#": k += 1
                if i + k < n and src[i + k] == "/":
                    end = src.find("/" + "#" * k, i + k + 1)
                    i = n if end < 0 else end + 1 + k
                    continue
                if i + k < n and src[i + k] == '"':
                    multi = src.startswith('"""', i + k)
                    i += k + (3 if multi else 1)
                    stack.append(["str", multi, k])
                    start = i
                    continue
                i += k
                continue
            if c == '"':
                multi = src.startswith('"""', i)
                i += 3 if multi else 1
                stack.append(["str", multi, 0])
                start = i
                continue
            if top[1] is not None:
                if c == "(":
                    top[1] += 1
                elif c == ")":
                    if top[1] == 0:
                        stack.pop()
                        i += 1
                        start = i
                        continue
                    top[1] -= 1
            i += 1
            continue
        _, multi, k = top
        close = ('"""' if multi else '"') + "#" * k
        escape = "\\" + "#" * k
        if src.startswith(escape, i):
            j = i + len(escape)
            if j < n and src[j] == "(":
                spans.append((start, i))
                stack.append(["code", 0])
                i = j + 1
                continue
            i = j + 1
            continue
        if src.startswith(close, i):
            spans.append((start, i))
            stack.pop()
            i += len(close)
            continue
        if not multi and src[i] == "\n":
            spans.append((start, i))
            stack.pop()
        i += 1
    return spans


def rename_swift(src):
    out, last = [], 0
    for a, b in string_spans(src):
        line_start = src.rfind("\n", 0, a) + 1
        line_end = src.find("\n", b)
        line = src[line_start:len(src) if line_end < 0 else line_end]
        out.append(src[last:a])
        piece = src[a:b]
        out.append(piece if any(re.search(p, line) for p in KEEP_LINES) else rename(piece))
        last = b
    out.append(src[last:])
    # The bundle id in code that isn't a string (a constant's name has none).
    return "".join(out)


def rename_script(src):
    """A shell or Python script, or the dictionary: every line but comments."""
    lines = src.split("\n")
    return "\n".join(line if line.lstrip().startswith("#") and not line.startswith("#!") else rename(line) for line in lines)


def renamed(path, src):
    return rename_swift(src) if path.endswith(".swift") else rename_script(src)


def files():
    out = []
    for pattern in FILES:
        out += sorted(glob.glob(os.path.join(ROOT, pattern)))
    return [p for p in out if os.path.isfile(p)]


def apply(write):
    changed = 0
    for path in files():
        src = open(path, encoding="utf-8").read()
        if "<<<<<<<" in src:
            print(f"skipped, still in conflict: {os.path.relpath(path, ROOT)}")
            continue
        new = renamed(path, src)
        if new == src:
            continue
        changed += 1
        rel = os.path.relpath(path, ROOT)
        if write:
            open(path, "w", encoding="utf-8").write(new)
            print(f"renamed: {rel}")
        else:
            for old_line, new_line in zip(src.split("\n"), new.split("\n")):
                if old_line != new_line:
                    print(f"{rel}:\n  - {old_line.strip()[:160]}\n  + {new_line.strip()[:160]}")
    print(f"{changed} file(s) {'renamed' if write else 'to rename'}")


# MARK: - merge conflicts that are only the rename

CONFLICT = re.compile(
    r"^<<<<<<< [^\n]*\n(?P<ours>.*?)^\|\|\|\|\|\|\| [^\n]*\n(?P<base>.*?)^=======\n(?P<theirs>.*?)^>>>>>>> [^\n]*\n",
    re.S | re.M)


def settle(path, text):
    """Each conflict where our side is upstream's old lines renamed becomes
    upstream's new lines renamed. Returns the text and how many are left."""
    left = 0

    def one(m):
        nonlocal left
        ours, base, theirs = m.group("ours"), m.group("base"), m.group("theirs")
        if renamed(path, base) == ours:
            return renamed(path, theirs)
        if renamed(path, theirs) == ours or renamed(path, theirs) == renamed(path, ours):
            return ours
        left += 1
        return m.group(0)

    return CONFLICT.sub(one, text), left


def resolve():
    names = subprocess.run(["git", "diff", "--name-only", "--diff-filter=U"], cwd=ROOT,
                           capture_output=True, text=True).stdout.split()
    if not names:
        print("no conflicts")
        return
    for name in names:
        path = os.path.join(ROOT, name)
        # Upstream's old lines too (diff3), which is how a rename-only
        # conflict is told from a real one.
        subprocess.run(["git", "checkout", "--conflict=diff3", "--", name], cwd=ROOT, check=True)
        text, left = settle(path, open(path, encoding="utf-8").read())
        open(path, "w", encoding="utf-8").write(text)
        if left:
            print(f"left for you: {name} ({left} conflict(s) that are more than the rename)")
        else:
            subprocess.run(["git", "add", "--", name], cwd=ROOT, check=True)
            print(f"settled: {name}")


# MARK: - the rules' own checks

def test():
    cases = [
        ('"Quit Search?"', '"Quit Manifold?"'),
        ('"Search can ask before it quits."', '"Manifold can ask before it quits."'),
        ('"Search Tabs…"', '"Search Tabs…"'),
        ('"Search the tabs Search closed"', '"Search the tabs Manifold closed"'),
        ('"Brave Search"', '"Brave Search"'),
        ('"Search with \\(name)"', '"Search with \\(name)"'),
        ('"New in Search \\(release.version)"', '"New in Manifold \\(release.version)"'),
        ('// Search keeps this comment\nlet a = "Search"', '// Search keeps this comment\nlet a = "Manifold"'),
        ('let b = #"raw Search"#', 'let b = #"raw Manifold"#'),
        ('let c = """\n  Search, in a block\n  """', 'let c = """\n  Manifold, in a block\n  """'),
        ('x("\\(f("Search")) and Search")', 'x("\\(f("Manifold")) and Manifold")'),
        ('let r = #/Search "x"/#', 'let r = #/Search "x"/#'),
        ('var prompt = "Search"', 'var prompt = "Search"'),
        ('"com.officecommun.search"', '"io.szero.manifold"'),
        ('"com.officecommun.search.test.\\(name)"', '"io.szero.manifold.test.\\(name)"'),
        ('"com.officecommun.search.appcast"', '"com.officecommun.search.appcast"'),
        ('"com.officecommun.search.ai-engine"', '"com.officecommun.search.ai-engine"'),
        ('"a fork of Search by Office Commun"', '"a fork of Search by Office Commun"'),
        ('"Upstream released Search \\(v)"', '"Upstream released Search \\(v)"'),
        ('Text("Search \\(site.name)")', 'Text("Search \\(site.name)")'),
        ('"Search \\(next.version) is ready"', '"Manifold \\(next.version) is ready"'),
        ('"get Search from searchbrowser.app"', '"get Search from searchbrowser.app"'),
    ]
    failed = 0
    for src, want in cases:
        got = rename_swift(src)
        if got != want:
            failed += 1
            print(f"FAIL swift: {src!r}\n  got  {got!r}\n  want {want!r}")
    scripts = [
        ('APP = str(ROOT / "build" / "Search.app")', 'APP = str(ROOT / "build" / "Manifold.app")'),
        ('# Search, in a comment', '# Search, in a comment'),
        ('cp Search.sdef "$APP/Contents/Resources/"', 'cp Search.sdef "$APP/Contents/Resources/"'),
        ('BINARY="$(swift build --show-bin-path)/Search"', 'BINARY="$(swift build --show-bin-path)/Search"'),
        ('SUITE=com.officecommun.search.test', 'SUITE=io.szero.manifold.test'),
        ('rm -rf "$HOME/Library/WebKit/com.officecommun.search/x"', 'rm -rf "$HOME/Library/WebKit/io.szero.manifold/x"'),
    ]
    for src, want in scripts:
        got = rename_script(src)
        if got != want:
            failed += 1
            print(f"FAIL script: {src!r}\n  got  {got!r}\n  want {want!r}")
    # A conflict that is only the rename is settled; a real one is left.
    conflict = ('a\n<<<<<<< HEAD\nlet t = "Manifold is here"\n||||||| base\nlet t = "Search is here"\n'
                '=======\nlet t = "Search is here, now"\n>>>>>>> upstream\nb\n')
    text, left = settle("x.swift", conflict)
    if text != 'a\nlet t = "Manifold is here, now"\nb\n' or left:
        failed += 1
        print(f"FAIL settle: {text!r} {left}")
    real = ('<<<<<<< HEAD\nlet t = "Manifold, ours"\n||||||| base\nlet t = "Search"\n'
            '=======\nlet t = "Search, theirs"\n>>>>>>> upstream\n')
    text, left = settle("x.swift", real)
    if left != 1 or text != real:
        failed += 1
        print(f"FAIL settle kept a real conflict: {text!r} {left}")
    print(f"{len(cases) + len(scripts) + 2 - failed} passed, {failed} failed")
    return failed


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "apply": apply(write=True)
    elif command == "check": apply(write=False)
    elif command == "resolve": resolve()
    elif command == "test": sys.exit(1 if test() else 0)
    else: sys.exit(__doc__)
