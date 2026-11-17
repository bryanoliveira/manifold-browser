#!/bin/bash
# Builds Manifold for this Mac and publishes it as a GitHub release of the
# fork. Upstream's own build.sh does the building, unchanged; this script only
# renames what people see, packs it, and uploads it.
#
#   Fork/release.sh            build, pack, tag and publish the next release
#   Fork/release.sh --dry-run  build and pack into build/manifold/, publish nothing
#
# The tag is upstream's version plus a counter for this fork: v1.0.14-manifold.1,
# then v1.0.14-manifold.2, until upstream's VERSION moves on.
#
# What changes from upstream's Search.app, and nothing else:
#   - the name in the menu bar, the Dock, ⌘Tab and Finder is "Manifold"
#     (a localised display name, the way build.sh names dev builds);
#   - it is signed ad hoc, so it runs on the Mac that installs it and
#     upstream's updater never swaps it for upstream's Search (Updater.swift
#     refuses any swap under an app with no Team ID).
# The bundle id and the data folders stay Search's, so an existing Search
# setup on this Mac carries over.
set -euo pipefail

cd "$(dirname "$0")/.."
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

NAME="Manifold"
ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || { echo "only Apple Silicon builds for now" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < VERSION)"

if [ "$DRY" = 0 ]; then
  [ -z "$(git status --porcelain)" ] || { echo "commit or stash your changes first: a release is built from a commit" >&2; exit 1; }
  git fetch -q origin
  [ "$(git rev-parse HEAD)" = "$(git rev-parse '@{upstream}' 2>/dev/null || true)" ] \
    || { echo "push this branch first: the release points at a commit on GitHub" >&2; exit 1; }
  git fetch -q --tags origin
fi

# The next free counter for this upstream version.
N=1
while git rev-parse -q --verify "refs/tags/v$VERSION-manifold.$N" >/dev/null; do N=$((N + 1)); done
TAG="v$VERSION-manifold.$N"

./build.sh release
APP="build/Search.app"

# The name people see. The folder stays Search.app: macOS reads a bundle
# whose folder differs from its CFBundleName as renamed by hand, and then
# shows the folder's name instead of the localised one.
mkdir -p "$APP/Contents/Resources/en.lproj"
printf '"CFBundleDisplayName" = "%s";\n"CFBundleName" = "%s";\n' "$NAME" "$NAME" \
  > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
/usr/libexec/PlistBuddy -c "Delete :LSHasLocalizedDisplayName" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSHasLocalizedDisplayName bool true" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :NSHumanReadableCopyright $NAME, a fork of Search by Office Commun" "$APP/Contents/Info.plist"
# The plist changed, so the signature has to be made again, as build.sh
# signs when there is no Developer ID.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

OUT="build/manifold"
rm -rf "$OUT"
mkdir -p "$OUT/dmg"
ZIP="$OUT/$NAME-$TAG-$ARCH.zip"
DMG="$OUT/$NAME-$TAG-$ARCH.dmg"
ditto -c -k --keepParent "$APP" "$ZIP"
cp -R "$APP" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "$NAME" -srcfolder "$OUT/dmg" -ov -format UDZO -quiet "$DMG"
rm -rf "$OUT/dmg"
echo "packed: $DMG, $ZIP"

UPSTREAM_SHA="$(git merge-base HEAD upstream/main 2>/dev/null || true)"
NOTES="$OUT/notes.md"
{
  echo "$NAME $TAG for Apple Silicon Macs, built from Search $VERSION."
  echo
  echo "This build is signed ad hoc. It has no Developer ID, so macOS refuses it on first launch."
  echo "Open it once from System Settings › Privacy & Security › Open Anyway."
  echo "Or remove the download mark in Terminal: \`xattr -dr com.apple.quarantine /Applications/Search.app\`."
  echo
  echo "## What this fork adds to Search"
  echo
  if [ -n "$UPSTREAM_SHA" ] && [ -n "$(git log --oneline "$UPSTREAM_SHA..HEAD" -- . ':!Fork')" ]; then
    git log --format='- %s' "$UPSTREAM_SHA..HEAD" -- . ':!Fork'
  else
    echo "- Nothing yet beyond the name: this is upstream Search as of ${UPSTREAM_SHA:0:7}."
  fi
  echo
  echo "SHA-256:"
  echo
  echo '```'
  (cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")")
  echo '```'
} > "$NOTES"

if [ "$DRY" = 1 ]; then
  echo "dry run: $TAG not published. Notes in $NOTES"
  exit 0
fi

git tag -a "$TAG" -m "$NAME $TAG"
git push -q origin "$TAG"
gh release create "$TAG" "$DMG" "$ZIP" --title "$NAME $TAG" --notes-file "$NOTES" --verify-tag
echo "released: $TAG"
