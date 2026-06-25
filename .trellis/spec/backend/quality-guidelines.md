# Quality Guidelines

> Code quality standards for backend development.

---

## Overview

<!--
Document your project's quality standards here.

Questions to answer:
- What patterns are forbidden?
- What linting rules do you enforce?
- What are your testing requirements?
- What code review standards apply?
-->

(To be filled by the team)

---

## Forbidden Patterns

<!-- Patterns that should never be used and why -->

(To be filled by the team)

---

## Required Patterns

<!-- Patterns that must always be used -->

(To be filled by the team)

---

## Testing Requirements

<!-- What level of testing is expected -->

(To be filled by the team)

---

## Code Review Checklist

<!-- What reviewers should check -->

### Scenario: macOS GitHub Actions Packaging

#### 1. Scope / Trigger

- Trigger: any change to `.github/workflows/package-macos.yml`, `scripts/ci-swift-check.sh`, `scripts/package-macos.sh`, `Package.swift`, or macOS packaging targets.
- This is an infrastructure contract because packaging depends on GitHub runner labels, Swift/Xcode toolchains, artifact actions, and optional signing/export environment variables.

#### 2. Signatures

- CI check command:
  ```bash
  scripts/ci-swift-check.sh <release|debug>
  ```
- Packaging command:
  ```bash
  scripts/package-macos.sh <release|debug>
  ```
- Optional Xcode archive inputs:
  ```text
  RIGHTTOOL_XCODE_PROJECT=<path-to-xcodeproj>
  RIGHTTOOL_XCODE_SCHEME=<scheme-name>
  RIGHTTOOL_EXPORT_OPTIONS_PLIST=<optional-export-options-plist>
  ```
- Preview bundle identifiers and entitlements:
  ```text
  BUNDLE_IDENTIFIER=com.righttool.app
  XPC_BUNDLE_IDENTIFIER=com.righttool.app.ActionRunner
  FINDER_EXTENSION_BUNDLE_IDENTIFIER=com.righttool.app.FinderExtension
  APP_GROUP_IDENTIFIER=group.com.righttool.app
  CODE_SIGN_IDENTITY=-
  ```

#### 3. Contracts

- GitHub workflow must use explicit macOS runner labels, not `macos-latest`, to avoid packaging drift when GitHub changes aliases.
- The default packaging path is SwiftPM preview bundling while no complete Xcode project exists.
- The SwiftPM preview bundle must still include `Contents/PlugIns/RightToolFinderExtension.appex`.
- The preview Finder Sync `.appex` must be a Mach-O `EXECUTE` binary linked with `_NSExtensionMain`; a Swift dylib inside an `.appex` is not a valid Finder Sync extension bundle for PlugInKit discovery.
- The preview `.appex` Info.plist must contain `NSExtensionPointIdentifier=com.apple.FinderSync`.
- The preview app, XPC service, Finder extension, and their embedded `libRightToolCore.dylib` copies must be signed before zipping. Ad-hoc signing is acceptable for local test artifacts; public distribution still requires Developer ID signing and notarization.
- The packaging script must validate the preview bundle before upload so CI cannot publish an artifact that lacks a discoverable Finder Sync extension.
- When both `RIGHTTOOL_XCODE_PROJECT` and `RIGHTTOOL_XCODE_SCHEME` are configured, packaging must use `xcodebuild archive`.
- If only one Xcode variable is configured, packaging must fail instead of silently falling back to SwiftPM preview output.
- Artifacts are written to `dist/*.zip`.
- The current default artifacts are non-notarized test builds. Developer ID signing/notarization requires a separate secrets/keychain flow.

#### 4. Validation & Error Matrix

- Unsupported configuration argument -> exit 64.
- Only one of `RIGHTTOOL_XCODE_PROJECT` / `RIGHTTOOL_XCODE_SCHEME` is set -> exit 64.
- `RIGHTTOOL_XCODE_PROJECT` path is missing -> exit 66.
- No Xcode variables are set -> build SwiftPM preview bundle.
- Preview Finder Sync binary is not `EXECUTE` -> exit 65.
- Preview Finder Sync extension point is not `com.apple.FinderSync` -> exit 65.
- Preview deep code-sign verification fails -> packaging fails before zip upload.
- No `dist/*.zip` output in GitHub Actions -> artifact upload must fail.

#### 5. Good/Base/Bad Cases

- Good: tag `v1.2.3` produces `RightTool-1.2.3-<arch>-preview.zip` containing `RightToolFinderExtension.appex` as an `_NSExtensionMain` executable, or an exported Xcode archive artifact.
- Base: manual workflow dispatch with no Xcode env vars produces a SwiftPM preview bundle with App, XPC service, Finder extension, and shared core dylib.
- Bad: `RIGHTTOOL_XCODE_PROJECT` set without `RIGHTTOOL_XCODE_SCHEME` silently falls back to preview bundling.
- Bad: preview bundle contains `Contents/PlugIns/RightToolFinderExtension.appex` but the appex executable is a `DYLIB`.

#### 6. Tests Required

- Run shell syntax checks:
  ```bash
  bash -n scripts/ci-swift-check.sh scripts/package-macos.sh
  ```
- Parse the workflow YAML:
  ```bash
  ruby -e 'require "yaml"; YAML.load_file(".github/workflows/package-macos.yml")'
  ```
- Run preview package validation:
  ```bash
  scripts/package-macos.sh debug
  codesign --verify --deep --strict --verbose=2 dist/staging/RightTool.app
  otool -hv dist/staging/RightTool.app/Contents/PlugIns/RightToolFinderExtension.appex/Contents/MacOS/RightToolFinderExtension
  ```
- Run Swift type checks or `swift test` where the local toolchain allows it.
- For future Xcode project work, run at least one GitHub Actions workflow dispatch before calling packaging complete.

#### 7. Wrong vs Correct

Wrong:
```yaml
runs-on: macos-latest
```

Correct:
```yaml
runs-on: macos-26
```

Wrong:
```bash
RIGHTTOOL_XCODE_PROJECT=RightTool.xcodeproj scripts/package-macos.sh release
```

Correct:
```bash
RIGHTTOOL_XCODE_PROJECT=RightTool.xcodeproj \
RIGHTTOOL_XCODE_SCHEME=RightTool \
scripts/package-macos.sh release
```

Wrong:
```text
RightToolFinderExtension.appex/Contents/MacOS/RightToolFinderExtension: Mach-O ... dynamically linked shared library
```

Correct:
```text
RightToolFinderExtension.appex/Contents/MacOS/RightToolFinderExtension: Mach-O ... executable
```
