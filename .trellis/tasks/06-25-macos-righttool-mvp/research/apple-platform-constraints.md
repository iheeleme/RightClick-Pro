# Apple Platform Constraints for RightTool MVP

## Scope

This note records the Apple platform constraints that shaped the RightTool MVP requirements.

## Finder Sync Extension

Apple's Finder Sync extension point lets an app register one or more folders for Finder to monitor. The extension can add badges, labels, toolbar items, sidebar icons, and contextual menus for items inside those monitored folders.

Key implications for RightTool:

* RightTool should not promise a universal Finder-wide context menu in MVP.
* The safest MVP scope is user-configured monitored folders.
* The containing app should let the user choose those folders and share configuration with the extension through an App Group.
* The extension can provide different menus for selected items, container/background clicks, sidebar entries, and toolbar menu interactions.
* Finder Sync extensions should stay lightweight because they can live for a long time and may have multiple instances, including inside Open/Save panels.

Primary source:

* Apple Developer Documentation Archive: Finder Sync — https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html

## XPC

Apple describes XPC as a lightweight interprocess communication mechanism on Apple platforms. For Swift and Objective-C apps, `NSXPCConnection` is the high-level API commonly used for structured communication between an app and an XPC service/helper.

Key implications for RightTool:

* The Finder Sync extension should not directly own complex action execution.
* A non-privileged user-level ActionRunner can receive ActionRequests and execute file operations under the current user account.
* The MVP does not need a privileged helper because the agreed actions only touch user-authorized locations.
* XPC adds implementation complexity, but gives a cleaner boundary than URL Scheme request files for the first durable architecture.

Primary sources:

* Apple Developer Documentation: XPC — https://developer.apple.com/documentation/xpc
* Apple Developer Documentation Archive: Creating XPC Services — https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html
* Apple Developer Documentation: NSXPCConnection — https://developer.apple.com/documentation/Foundation/NSXPCConnection

## App Group Storage

Finder Sync guidance describes sharing user-selected monitored folders between the containing app and Finder Sync extension via an App Group and shared user defaults. RightTool's configuration is richer than simple defaults, so MVP will use the App Group container for versioned JSON files and operation logs.

Key implications for RightTool:

* Shared config must be readable by the main app, Finder extension, and ActionRunner.
* Writes should be atomic so the extension never reads partially written JSON.
* Config files need a `schemaVersion` for future migration.
* Operation logs should be append-friendly and capped to avoid unbounded growth.

## Security Boundary

RightTool should follow a conservative permission model:

* Users explicitly add directories in the settings window.
* The app stores security-scoped bookmarks for those directories.
* File operations are allowed only inside or between authorized locations.
* Full Disk Access and privileged helpers are out of scope for MVP.

This keeps the tool aligned with the macOS user-consent model and makes failures easier to explain.
