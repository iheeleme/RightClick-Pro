# Quality Guidelines

Settings UI quality is measured by compile safety, persistence correctness, Finder-menu consistency, and manual macOS interaction checks.

## Required Checks

- Run `swift build --target RightClickProAppPreview` for settings-only changes.
- Run `scripts/ci-swift-check.sh debug` before committing Swift changes.
- Run `scripts/package-macos.sh debug` after settings changes that may affect preview bundle compilation or assets.
- Run `git diff --check`.

## Manual Smoke Test

After meaningful settings UI changes, open the preview app and verify:

- Menu bar opens the settings window.
- Sidebar sections switch without stale detail content.
- Overview shows current config/storage status.
- Action toggles, placement controls, visibility controls, sorting, and filtering update table/previews.
- Template add/edit/delete sheets validate required fields and update matching actions.
- Developer entry add/edit/delete sheets validate bundle identifier and update matching actions.
- Recent operations refresh reads `operation-log.jsonl`.
- Save/delete/reset operations show visible status feedback.

## Visual Standards

- Keep the surface dense and tool-like. Avoid marketing hero sections.
- Use semantic SF Symbols/AppKit icons through existing icon helpers.
- Use table headers, row controls, badges, and previews for scanability.
- Keep row controls accessible with labels/help text.
- Do not add controls that look editable without backing state and a ViewModel command.
- Keep Finder menu previews visually consistent through `FinderMenuPreview`, `FinderMenuBox`, `FinderMenuRow`, and `PreviewSection`.

## Code Review Checklist

- Does the UI mutate through `SettingsViewModel`?
- Does the preview derive from real `RightClickProConfig`/`DirectoryBookmarkCatalog`/`MenuBuilder` output?
- Do add/edit/delete flows preserve action back references?
- Are empty states and failure statuses visible?
- Do controls stay within stable row/table dimensions?
- Are long paths/title strings truncated or selectable where needed?

## Anti-Patterns

- Static mock data in a settings page that claims to reflect current config.
- Page-specific menu cards that drift from real Finder presentation.
- Native `Menu` controls used where a clearer segmented/filter/table control already exists locally.
- Hidden or icon-only destructive actions without help/accessibility labels.
