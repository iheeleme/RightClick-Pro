# Consolidate macOS Packaging Branches

## Goal

Make `develop` the single canonical branch for the completed macOS 15 packaging work and remove superseded local/remote fix branches without deleting release tags or product commits.

## Requirements

* Fast-forward remote `develop` from `d12f72a` to `acde16b`, preserving the archived task and journal commits.
* Confirm `v0.1.4` remains pointed at `d12f72a` and is not moved.
* Delete remote and local `codex/ship-macos15-packaging-fix` after its commits are reachable from `develop`.
* Delete local `codex/fix-macos15-packaging` after verifying its product fix is already represented by `develop` and release history.
* Leave `main`, `origin/main`, `develop`, tags, and unrelated active Trellis tasks untouched.

## Acceptance Criteria

* [x] `origin/develop` points to `acde16b` and contains all completed packaging work.
* [x] `v0.1.4` remains immutable and points to `d12f72a`.
* [x] No local or remote macOS packaging fix branches remain.
* [x] Working tree is clean and no product files are changed.

## Out Of Scope

* Deleting release tags or GitHub Releases.
* Archiving unrelated active Trellis tasks.
* Rewriting commit history.
