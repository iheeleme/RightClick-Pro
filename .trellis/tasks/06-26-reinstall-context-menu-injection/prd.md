# Fix Reinstall Context Menu Auto Injection

## Goal

Ensure RightTool self-heals after a reinstall so the Finder right-click menu is available in the default monitored directories without requiring users to wipe configuration by hand.

## What I Already Know

* The preview app calls `ConfigurationBootstrapper.bootstrap()` on launch.
* The Finder Sync extension currently only loads existing config in `FinderSyncController.init()` before setting `FIFinderSyncController.default().directoryURLs`.
* Existing local changes already started repairing default bookmark paths that can be written under the app sandbox container instead of the real user home.
* The packaging script started enabling the Finder extension with PlugInKit, but it only enables an already-discovered extension identifier.

## Requirements

* Finder extension startup must create or repair RightTool config/bookmarks before setting monitored directories.
* Default injected Desktop/Downloads/Documents/Code bookmarks must point at the real user home, not a sandbox container home.
* Existing installs with sandbox-container bookmark paths must be sanitized during bootstrap.
* Existing installs missing an available default directory bookmark must append that default directory to bookmarks, monitored/common IDs, and directory actions without rewriting unrelated user configuration.
* Local preview packaging should explicitly register the newly packaged Finder Sync `.appex` before enabling it when PlugInKit is available.
* The fix must preserve existing user configuration and avoid overwriting unrelated menu customization.

## Acceptance Criteria

* [x] Bootstrap creates default config/bookmarks as before.
* [x] Bootstrap maps sandbox-container bookmark paths back to the real user home.
* [x] Bootstrap repairs missing default directory injection for existing configs.
* [x] Finder extension bootstrap runs before `directoryURLs` are loaded.
* [x] Packaging script registers the packaged `.appex` path before `pluginkit -e use`.
* [x] SwiftPM tests pass.

## Definition of Done

* Tests added/updated for bootstrap self-healing behavior.
* Lint/type-check or project test command run.
* Existing dirty user changes are preserved.

## Technical Approach

Use the existing `ConfigurationBootstrapper` as the single source of config self-healing. The Finder extension will invoke it on init, then reload monitored directories from the repaired files. The packaging script will keep best-effort PlugInKit behavior, but make it path-aware by registering the just-built extension first.

## Out of Scope

* Building a full installer or notarized distribution flow.
* Forcing macOS System Settings permissions beyond PlugInKit development-time enablement.
* Reworking the settings UI beyond any compile fixes required by touched code.

## Technical Notes

* Relevant files: `Sources/RightToolCore/ConfigurationBootstrapper.swift`, `Sources/RightToolFinderExtension/FinderSyncController.swift`, `scripts/package-macos.sh`, `Tests/RightToolCoreTests/ConfigurationBootstrapperTests.swift`.
* Local `codegraph` index is not initialized, so repository inspection used `rg` and direct source reads.
