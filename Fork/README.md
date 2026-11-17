# Manifold: this fork of Search

Manifold is [Search](https://github.com/driceroland/Search), a WebKit browser for the Mac, with a few additions.
Everything outside this folder is upstream's code. This page covers what the fork changes, how to release it,
and how to bring in upstream's updates.

## What the fork adds

Nothing yet beyond the name. Planned, in this order:

- importing Zen's spaces and profiles, so switching from Zen keeps everything;
- one page shown in several windows at once, held in memory once;
- sync with Safari on iPhone and iPad.

## Keeping up with upstream

The fork adds new files rather than editing upstream's, and keeps its own hooks into upstream files to a few lines.
To bring in upstream's changes:

```
git fetch upstream
git merge upstream/main
swift build
```

## Releasing

`Fork/release.sh` builds with upstream's `build.sh` and renames the app to Manifold. It signs the app ad hoc,
packs a disk image and a ZIP, tags the commit and publishes a GitHub release. The tag is upstream's version plus
a counter, such as `v1.0.14-manifold.1`. `Fork/release.sh --dry-run` builds and packs into `build/manifold/`
without publishing anything.

The release keeps Search's bundle id and data folders, so it uses the settings, tabs and sign-ins of any Search
already on the Mac. Because it has no Team ID, upstream's updater never replaces it with upstream's Search.
