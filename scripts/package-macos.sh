#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
APP_NAME="${APP_NAME:-RightTool}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.righttool.app}"
XPC_BUNDLE_IDENTIFIER="${XPC_BUNDLE_IDENTIFIER:-com.righttool.app.ActionRunner}"
ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:-$(uname -m)}"
DIST_DIR="${DIST_DIR:-dist}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-DerivedData}"

case "$CONFIGURATION" in
  release|debug) ;;
  *)
    echo "Unsupported configuration: $CONFIGURATION" >&2
    exit 64
    ;;
esac

version_name() {
  if [[ -n "${RIGHTTOOL_VERSION:-}" ]]; then
    printf "%s" "$RIGHTTOOL_VERSION"
    return
  fi

  if [[ "${GITHUB_REF_TYPE:-}" == "tag" && -n "${GITHUB_REF_NAME:-}" ]]; then
    printf "%s" "${GITHUB_REF_NAME#v}"
    return
  fi

  if [[ -n "${GITHUB_SHA:-}" ]]; then
    printf "0.0.0-%s" "${GITHUB_SHA:0:7}"
    return
  fi

  printf "0.0.0-dev"
}

build_number() {
  if [[ -n "${RIGHTTOOL_BUILD_NUMBER:-}" ]]; then
    printf "%s" "$RIGHTTOOL_BUILD_NUMBER"
    return
  fi

  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    printf "%s" "$GITHUB_RUN_NUMBER"
    return
  fi

  printf "1"
}

package_xcode_archive_if_configured() {
  if [[ -z "${RIGHTTOOL_XCODE_PROJECT:-}" && -z "${RIGHTTOOL_XCODE_SCHEME:-}" ]]; then
    return 1
  fi

  if [[ -z "${RIGHTTOOL_XCODE_PROJECT:-}" || -z "${RIGHTTOOL_XCODE_SCHEME:-}" ]]; then
    echo "Both RIGHTTOOL_XCODE_PROJECT and RIGHTTOOL_XCODE_SCHEME are required for Xcode packaging." >&2
    exit 64
  fi

  if [[ ! -e "$RIGHTTOOL_XCODE_PROJECT" ]]; then
    echo "RIGHTTOOL_XCODE_PROJECT does not exist: $RIGHTTOOL_XCODE_PROJECT" >&2
    exit 66
  fi

  local archive_path="$PWD/$DIST_DIR/$APP_NAME.xcarchive"
  mkdir -p "$DIST_DIR"

  xcodebuild archive \
    -project "$RIGHTTOOL_XCODE_PROJECT" \
    -scheme "$RIGHTTOOL_XCODE_SCHEME" \
    -configuration "$(tr '[:lower:]' '[:upper:]' <<< "${CONFIGURATION:0:1}")${CONFIGURATION:1}" \
    -archivePath "$archive_path" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

  if [[ -n "${RIGHTTOOL_EXPORT_OPTIONS_PLIST:-}" && -f "$RIGHTTOOL_EXPORT_OPTIONS_PLIST" ]]; then
    xcodebuild -exportArchive \
      -archivePath "$archive_path" \
      -exportOptionsPlist "$RIGHTTOOL_EXPORT_OPTIONS_PLIST" \
      -exportPath "$PWD/$DIST_DIR/export"
    ditto -c -k --keepParent "$DIST_DIR/export" "$DIST_DIR/$APP_NAME-$(version_name)-$ARTIFACT_SUFFIX-export.zip"
  else
    ditto -c -k --keepParent "$archive_path" "$DIST_DIR/$APP_NAME-$(version_name)-$ARTIFACT_SUFFIX-xcarchive.zip"
  fi
}

write_app_info_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$(version_name)</string>
  <key>CFBundleVersion</key>
  <string>$(build_number)</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
}

write_xpc_info_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>RightToolActionRunner</string>
  <key>CFBundleIdentifier</key>
  <string>$XPC_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>RightToolActionRunner</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$(version_name)</string>
  <key>CFBundleVersion</key>
  <string>$(build_number)</string>
  <key>XPCService</key>
  <dict>
    <key>ServiceType</key>
    <string>Application</string>
  </dict>
</dict>
</plist>
PLIST
}

package_swiftpm_preview_bundle() {
  swift build -c "$CONFIGURATION" --product righttool-app-preview
  swift build -c "$CONFIGURATION" --product righttool-action-runner

  local bin_path
  bin_path="$(swift build -c "$CONFIGURATION" --show-bin-path)"
  local staging="$PWD/$DIST_DIR/staging"
  local app_path="$staging/$APP_NAME.app"
  local xpc_path="$app_path/Contents/Library/XPCServices/RightToolActionRunner.xpc"

  rm -rf "$staging"
  mkdir -p \
    "$app_path/Contents/MacOS" \
    "$app_path/Contents/Resources" \
    "$xpc_path/Contents/MacOS"

  cp "$bin_path/righttool-app-preview" "$app_path/Contents/MacOS/$APP_NAME"
  cp "$bin_path/righttool-action-runner" "$xpc_path/Contents/MacOS/RightToolActionRunner"
  write_app_info_plist "$app_path/Contents/Info.plist"
  write_xpc_info_plist "$xpc_path/Contents/Info.plist"

  cat > "$app_path/Contents/Resources/PACKAGING-NOTES.txt" <<'NOTES'
RightTool SwiftPM preview bundle.

This artifact is useful for validating the menu-bar app scaffold and embedded
ActionRunner binary. It is unsigned and does not yet include a packaged Finder
Sync .appex. Add a full Xcode project/scheme to produce a signed app bundle with
the Finder Sync extension.
NOTES

  mkdir -p "$DIST_DIR"
  ditto -c -k --keepParent "$app_path" "$DIST_DIR/$APP_NAME-$(version_name)-$ARTIFACT_SUFFIX-preview.zip"
}

if ! package_xcode_archive_if_configured; then
  package_swiftpm_preview_bundle
fi
