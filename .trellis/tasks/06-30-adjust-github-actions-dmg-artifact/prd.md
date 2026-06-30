# Adjust GitHub Actions DMG Artifact

## Goal

GitHub Actions packaging should publish DMG-only artifacts. The workflow should stop uploading the generated preview app zip together with the DMG inside one Actions artifact.

## What I Already Know

* The user asked to adjust GitHub Actions so the artifact is only a DMG.
* `.github/workflows/package-macos.yml` currently uploads both `dist/*.zip` and `dist/*.dmg`.
* `scripts/package-macos.sh` creates a preview zip by default and creates a DMG when `RIGHTCLICKPRO_PACKAGE_DMG=1`.
* The current workflow exposes `package_dmg` as a manual input and defaults it to `false`.

## Requirements

* GitHub Actions packaging must always request DMG generation.
* GitHub Actions upload-artifact must include only DMG files.
* Documentation must match the new GitHub Actions artifact behavior.

## Acceptance Criteria

* [x] The workflow uploads `dist/*.dmg` and no `dist/*.zip`.
* [x] The workflow succeeds on tag/push/manual runs without requiring the old `package_dmg` input.
* [x] Packaging docs describe DMG-only uploaded artifacts.
* [x] YAML syntax check and whitespace check pass.

## Out of Scope

* Changing local script behavior for developers who still use `scripts/package-macos.sh` directly.
* Adding signing or notarization.

## Technical Notes

* Relevant files: `.github/workflows/package-macos.yml`, `docs/github-actions-packaging.md`.
* Relevant specs: `.trellis/spec/backend/quality-guidelines.md`, `.trellis/spec/backend/directory-structure.md`, `.trellis/spec/backend/logging-guidelines.md`.
