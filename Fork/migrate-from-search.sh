#!/bin/bash
# A Search's data, copied to Manifold's places, once: Manifold's bundle id is
# io.szero.manifold, and macOS keeps an app's settings, cookies and site data
# by its bundle id, and Manifold its own files in Application Support/Manifold.
#
#   Fork/migrate-from-search.sh          copy what Manifold doesn't have yet
#
# Copied, never moved: Search's data stays where it is, as it was, until you
# remove it (the last lines this prints say where). Once Manifold has data of
# its own, running this again changes nothing. Neither browser may be open
# while it runs: their files would be copied half written.
#
# What goes where:
#   ~/Library/Application Support/Search    → …/Manifold         tabs, spaces, pins, history, bookmarks
#   settings com.officecommun.search         → io.szero.manifold  every setting
#   ~/Library/WebKit/com.officecommun.search → …/io.szero.manifold sign-ins, site data, extensions' data
#   ~/Library/HTTPStorages/com.officecommun.search(.binarycookies) → …/io.szero.manifold  cookies
# Not copied: the caches, which fill again, and the keychain, where Search's
# items are found by their label, which Manifold no longer uses.
set -euo pipefail

OLD="com.officecommun.search"
NEW="io.szero.manifold"
LIB="$HOME/Library"

for app in Search Manifold; do
  if pgrep -x "$app" >/dev/null; then
    echo "$app is open: quit it first, so nothing is copied half written" >&2
    exit 1
  fi
done

# Manifold has run for real once its own folder is there: then everything
# was copied before, or Manifold has data of its own, and nothing is touched.
# Before that, what is at Manifold's places came from test runs, which use
# the bundle id but folders of their own ("Manifold (name)"): it is moved
# aside, never deleted, and Search's copied in its place.
if [ -e "$LIB/Application Support/Manifold" ]; then
  echo "Manifold already has its own data ($LIB/Application Support/Manifold): nothing copied"
  exit 0
fi
STAMP="$(date +%Y%m%d-%H%M%S)"

copy() {
  local from="$1" to="$2" what="$3"
  if [ ! -e "$from" ]; then
    echo "nothing to copy: $what ($from)"
    return
  fi
  if [ -e "$to" ]; then
    mv "$to" "$to.test-runs-$STAMP"
    echo "moved aside, from test runs: $to.test-runs-$STAMP"
  fi
  ditto "$from" "$to"
  echo "copied: $what, $(du -sh "$to" | cut -f1)"
}

copy "$LIB/Application Support/Search" "$LIB/Application Support/Manifold" "tabs, spaces, pins, history and bookmarks"
copy "$LIB/WebKit/$OLD" "$LIB/WebKit/$NEW" "sign-ins, site data and extensions' data"
copy "$LIB/HTTPStorages/$OLD" "$LIB/HTTPStorages/$NEW" "cookies"
copy "$LIB/HTTPStorages/$OLD.binarycookies" "$LIB/HTTPStorages/$NEW.binarycookies" "cookies (file)"

# Settings go through macOS's own preferences, so nothing it holds in memory
# is missed. Importing replaces the whole domain: what test runs wrote there
# (their windows' frames) goes.
if defaults export "$OLD" - >/dev/null 2>&1; then
  defaults export "$OLD" - | defaults import "$NEW" -
  echo "copied: settings, $(defaults read "$NEW" | grep -c ' = ') entries"
else
  echo "nothing to copy: settings ($OLD)"
fi

cat <<EOF

Search's own data is still in place. Once Manifold has everything, it can go:
  rm -rf "$LIB/Application Support/Search" "$LIB/WebKit/$OLD" "$LIB/HTTPStorages/$OLD" "$LIB/HTTPStorages/$OLD.binarycookies" "$LIB/Caches/$OLD"
  defaults delete $OLD
EOF
