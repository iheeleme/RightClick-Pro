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

#### 3. Contracts

- GitHub workflow must use explicit macOS runner labels, not `macos-latest`, to avoid packaging drift when GitHub changes aliases.
- The default packaging path is SwiftPM preview bundling while no complete Xcode project exists.
- When both `RIGHTTOOL_XCODE_PROJECT` and `RIGHTTOOL_XCODE_SCHEME` are configured, packaging must use `xcodebuild archive`.
- If only one Xcode variable is configured, packaging must fail instead of silently falling back to SwiftPM preview output.
- Artifacts are written to `dist/*.zip`.
- The current default artifacts are unsigned. Signing/notarization requires a separate secrets/keychain flow.

#### 4. Validation & Error Matrix

- Unsupported configuration argument -> exit 64.
- Only one of `RIGHTTOOL_XCODE_PROJECT` / `RIGHTTOOL_XCODE_SCHEME` is set -> exit 64.
- `RIGHTTOOL_XCODE_PROJECT` path is missing -> exit 66.
- No Xcode variables are set -> build SwiftPM preview bundle.
- No `dist/*.zip` output in GitHub Actions -> artifact upload must fail.

#### 5. Good/Base/Bad Cases

- Good: tag `v1.2.3` produces `RightTool-1.2.3-<arch>-preview.zip` or an exported Xcode archive artifact.
- Base: manual workflow dispatch with no Xcode env vars produces a SwiftPM preview bundle.
- Bad: `RIGHTTOOL_XCODE_PROJECT` set without `RIGHTTOOL_XCODE_SCHEME` silently falls back to preview bundling.

#### 6. Tests Required

- Run shell syntax checks:
  ```bash
  bash -n scripts/ci-swift-check.sh scripts/package-macos.sh
  ```
- Parse the workflow YAML:
  ```bash
  ruby -e 'require "yaml"; YAML.load_file(".github/workflows/package-macos.yml")'
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
