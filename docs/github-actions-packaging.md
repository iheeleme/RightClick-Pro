# GitHub Actions Packaging

RightTool uses `.github/workflows/package-macos.yml` to build and upload macOS artifacts from GitHub Actions.

## What the Workflow Does

The workflow runs on:

* manual `workflow_dispatch`;
* version tags matching `v*`;
* pull requests that touch build, source, test, script, or docs files.

It uses GitHub-hosted macOS runners and uploads packaged artifacts with `actions/upload-artifact`.

## First Test Package

Use manual dispatch with:

```text
version=0.1.0-test.1
configuration=release
```

The uploaded artifacts will be named like:

```text
RightTool-arm64-0.1.0-test.1
RightTool-x86_64-0.1.0-test.1
```

## Current Artifact

The repository currently has a Swift Package scaffold, not a complete Xcode `.app` project with embedded Finder Sync and XPC targets. Because of that, the workflow produces a SwiftPM preview bundle:

```text
dist/RightTool-<version>-<arch>-preview.zip
```

The preview bundle contains:

```text
RightTool.app
├── Contents/MacOS/RightTool
├── Contents/Library/XPCServices/RightToolActionRunner.xpc
└── Contents/Resources/PACKAGING-NOTES.txt
```

This artifact is unsigned and does not yet include a packaged Finder Sync `.appex`.

## Switching to Full Xcode Packaging

After adding a real Xcode project, set these repository or workflow environment variables:

```text
RIGHTTOOL_XCODE_PROJECT=RightTool.xcodeproj
RIGHTTOOL_XCODE_SCHEME=RightTool
```

Then `scripts/package-macos.sh` will use:

```bash
xcodebuild archive
```

If `RIGHTTOOL_EXPORT_OPTIONS_PLIST` points to an export options plist, the script also runs `xcodebuild -exportArchive`.

## Signing and Notarization

The current workflow intentionally builds unsigned artifacts. For signed distribution, add the Apple certificate and provisioning material as GitHub Actions secrets, then import the certificate into a temporary keychain during the workflow before `xcodebuild archive`.

Relevant official references:

* GitHub-hosted macOS runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
* Workflow syntax: https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions
* Installing Apple certificates on macOS runners: https://docs.github.com/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development
