# GitHub Actions Packaging

RightClick Pro uses `.github/workflows/package-macos.yml` to build and upload macOS artifacts from GitHub Actions.

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
package_dmg=false
```

The uploaded artifacts will be named like:

```text
RightClick Pro-arm64-0.1.0-test.1
RightClick Pro-x86_64-0.1.0-test.1
```

## Current Artifact

The repository currently has a Swift Package scaffold, not a complete Xcode `.app` project. Because of that, the workflow produces a SwiftPM preview bundle:

```text
dist/RightClick Pro-<version>-<arch>-preview.zip
```

The preview bundle contains:

```text
RightClick Pro.app
├── Contents/MacOS/RightClick Pro
├── Contents/PlugIns/RightClickProFinderExtension.appex
│   └── Contents/XPCServices/RightClickProActionRunner.xpc
├── Contents/XPCServices/RightClickProActionRunner.xpc
├── Contents/Frameworks/libRightClickProCore.dylib
└── Contents/Resources/PACKAGING-NOTES.txt
```

The Finder Sync extension is manually linked with `_NSExtensionMain` so PlugInKit can discover it during local testing. The ActionRunner XPC service is embedded in both the app and the Finder extension bundle so `NSXPCConnection(serviceName:)` can resolve it from either process. The bundle is ad-hoc signed when `codesign` is available, but it is not Developer ID signed or notarized. Downloaded builds may still require removing quarantine before local testing.

The preview app and Finder Sync extension are sandboxed and include App Group, user-selected read/write, and app-scope bookmark entitlements. The preview ActionRunner XPC service is signed with the App Group entitlement but without app sandboxing so local smoke tests can exercise the auto-injected Desktop/Documents/Downloads/Code directories. Runtime authorization still rejects paths outside the configured monitored/common directory set.

Packaging does not register the staging Finder Sync extension with the local PlugInKit database by default. The installed app owns runtime registration after it is copied to `/Applications`; this avoids Finder showing build-artifact app icons for local source directories such as `~/Code`. For a one-off local smoke test against the staging bundle, run:

```bash
RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
```

Default identifiers for the current preview distribution are:

```text
BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro
XPC_BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro.ActionRunner
FINDER_EXTENSION_BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro.FinderExtension
APP_GROUP_IDENTIFIER=group.com.iheeleme.rightclickpro
```

## Internal DMG

DMG packaging is opt-in for internal/self-test distribution:

```bash
RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh release
```

The script still creates the zip and also writes:

```text
dist/RightClick Pro-<version>-<arch>-preview.dmg
```

The DMG is compressed read-only `UDZO` and contains:

```text
RightClick Pro.app
Applications -> /Applications
README.txt
```

`README.txt` covers drag-to-Applications installation, the non-Developer-ID/non-notarized warning, automatic Finder Extension registration on app launch, one-time Finder reload after successful first setup, manual enablement fallback, and the Finder restart fallback when the right-click menu does not appear. The packaging script mounts the DMG after creation and validates those three entries before it succeeds.

## Switching to Full Xcode Packaging

After adding a real Xcode project, set these repository or workflow environment variables:

```text
RIGHTCLICKPRO_XCODE_PROJECT=RightClickPro.xcodeproj
RIGHTCLICKPRO_XCODE_SCHEME=RightClickPro
```

Then `scripts/package-macos.sh` will use:

```bash
xcodebuild archive
```

If `RIGHTCLICKPRO_EXPORT_OPTIONS_PLIST` points to an export options plist, the script also runs `xcodebuild -exportArchive`.

## Signing and Notarization

The current workflow intentionally builds non-notarized test artifacts. For signed distribution, add the Apple certificate and provisioning material as GitHub Actions secrets, then import the certificate into a temporary keychain during the workflow before `xcodebuild archive`.

Relevant official references:

* GitHub-hosted macOS runners: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
* Workflow syntax: https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions
* Installing Apple certificates on macOS runners: https://docs.github.com/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development
