#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
APP_NAME="${APP_NAME:-RightTool}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.righttool.app}"
XPC_BUNDLE_IDENTIFIER="${XPC_BUNDLE_IDENTIFIER:-com.righttool.app.ActionRunner}"
FINDER_EXTENSION_BUNDLE_IDENTIFIER="${FINDER_EXTENSION_BUNDLE_IDENTIFIER:-com.righttool.app.FinderExtension}"
APP_GROUP_IDENTIFIER="${APP_GROUP_IDENTIFIER:-group.com.righttool.app}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
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

write_finder_extension_info_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>RightTool Finder Extension</string>
  <key>CFBundleExecutable</key>
  <string>RightToolFinderExtension</string>
  <key>CFBundleIdentifier</key>
  <string>$FINDER_EXTENSION_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>RightToolFinderExtension</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>$(version_name)</string>
  <key>CFBundleVersion</key>
  <string>$(build_number)</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionAttributes</key>
    <dict/>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.FinderSync</string>
    <key>NSExtensionPrincipalClass</key>
    <string>FinderSyncController</string>
  </dict>
</dict>
</plist>
PLIST
}

write_entitlements_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>$APP_GROUP_IDENTIFIER</string>
  </array>
</dict>
</plist>
PLIST
}

build_righttool_core_dylib() {
  local build_dir="$1"
  mkdir -p "$build_dir"

  local swift_flags=()
  if [[ "$CONFIGURATION" == "release" ]]; then
    swift_flags=(-O)
  else
    swift_flags=(-Onone -g)
  fi

  swiftc \
    "${swift_flags[@]}" \
    -emit-library \
    -emit-module \
    -module-name RightToolCore \
    -emit-module-path "$build_dir/RightToolCore.swiftmodule" \
    -Xlinker -install_name \
    -Xlinker "@rpath/libRightToolCore.dylib" \
    Sources/RightToolCore/*.swift \
    -o "$build_dir/libRightToolCore.dylib"
}

build_finder_extension_bundle() {
  local core_build_dir="$1"
  local appex_path="$2"
  local executable_path="$appex_path/Contents/MacOS/RightToolFinderExtension"

  mkdir -p \
    "$appex_path/Contents/MacOS" \
    "$appex_path/Contents/Frameworks" \
    "$appex_path/Contents/Resources"

  local swift_flags=()
  if [[ "$CONFIGURATION" == "release" ]]; then
    swift_flags=(-O)
  else
    swift_flags=(-Onone -g)
  fi

  swiftc \
    "${swift_flags[@]}" \
    -parse-as-library \
    -module-name RightToolFinderExtension \
    -I "$core_build_dir" \
    -L "$core_build_dir" \
    -lRightToolCore \
    -framework AppKit \
    -framework FinderSync \
    -Xlinker -e \
    -Xlinker _NSExtensionMain \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    Sources/RightToolFinderExtension/FinderSyncController.swift \
    -o "$executable_path"

  cp "$core_build_dir/libRightToolCore.dylib" "$appex_path/Contents/Frameworks/"
  write_finder_extension_info_plist "$appex_path/Contents/Info.plist"
}

build_preview_executables() {
  local core_build_dir="$1"
  local app_executable_path="$2"
  local xpc_executable_path="$3"
  local bin_path
  local swiftpm_log="$DIST_DIR/swiftpm-build.log"

  if swift build -c "$CONFIGURATION" --product righttool-app-preview >"$swiftpm_log" 2>&1 \
    && swift build -c "$CONFIGURATION" --product righttool-action-runner >>"$swiftpm_log" 2>&1 \
    && bin_path="$(swift build -c "$CONFIGURATION" --show-bin-path 2>>"$swiftpm_log")"; then
    cp "$bin_path/righttool-app-preview" "$app_executable_path"
    cp "$bin_path/righttool-action-runner" "$xpc_executable_path"
    return
  fi

  echo "SwiftPM build failed; falling back to direct swiftc preview compilation. See $swiftpm_log." >&2

  local swift_flags=()
  if [[ "$CONFIGURATION" == "release" ]]; then
    swift_flags=(-O)
  else
    swift_flags=(-Onone -g)
  fi

  swiftc \
    "${swift_flags[@]}" \
    -parse-as-library \
    -module-name RightTool \
    -I "$core_build_dir" \
    -L "$core_build_dir" \
    -lRightToolCore \
    -framework AppKit \
    -framework SwiftUI \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    Sources/RightToolAppPreview/RightToolAppPreview.swift \
    -o "$app_executable_path"

  swiftc \
    "${swift_flags[@]}" \
    -module-name RightToolActionRunner \
    -I "$core_build_dir" \
    -L "$core_build_dir" \
    -lRightToolCore \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    Sources/RightToolActionRunnerService/main.swift \
    -o "$xpc_executable_path"
}

codesign_if_available() {
  local entitlements_path="$1"
  local app_path="$2"
  local xpc_path="$3"
  local appex_path="$4"

  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign not found; leaving preview bundle unsigned." >&2
    return
  fi

  codesign --force --sign "$CODE_SIGN_IDENTITY" "$app_path/Contents/Frameworks/libRightToolCore.dylib"
  codesign --force --sign "$CODE_SIGN_IDENTITY" "$xpc_path/Contents/Frameworks/libRightToolCore.dylib"
  codesign --force --sign "$CODE_SIGN_IDENTITY" "$appex_path/Contents/Frameworks/libRightToolCore.dylib"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements_path" "$xpc_path"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements_path" "$appex_path"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements_path" "$app_path"
}

validate_preview_bundle() {
  local app_path="$1"
  local xpc_path="$2"
  local appex_path="$3"
  local appex_executable="$appex_path/Contents/MacOS/RightToolFinderExtension"
  local extension_point

  test -x "$app_path/Contents/MacOS/$APP_NAME"
  test -x "$xpc_path/Contents/MacOS/RightToolActionRunner"
  test -x "$appex_executable"
  test -f "$app_path/Contents/Frameworks/libRightToolCore.dylib"
  test -f "$xpc_path/Contents/Frameworks/libRightToolCore.dylib"
  test -f "$appex_path/Contents/Frameworks/libRightToolCore.dylib"

  extension_point="$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$appex_path/Contents/Info.plist")"
  if [[ "$extension_point" != "com.apple.FinderSync" ]]; then
    echo "Invalid Finder extension point: $extension_point" >&2
    exit 65
  fi

  if ! otool -hv "$appex_executable" | grep -q " EXECUTE "; then
    echo "Finder extension executable is not a Mach-O EXECUTE binary." >&2
    exit 65
  fi

  if command -v codesign >/dev/null 2>&1; then
    codesign --verify --deep --strict --verbose=2 "$app_path"
  fi
}

package_swiftpm_preview_bundle() {
  local staging="$PWD/$DIST_DIR/staging"
  local app_path="$staging/$APP_NAME.app"
  local xpc_path="$app_path/Contents/Library/XPCServices/RightToolActionRunner.xpc"
  local appex_path="$app_path/Contents/PlugIns/RightToolFinderExtension.appex"
  local manual_build_dir="$PWD/$DIST_DIR/manual-build"
  local entitlements_path="$manual_build_dir/RightTool.entitlements"

  rm -rf "$staging" "$manual_build_dir"
  mkdir -p \
    "$app_path/Contents/MacOS" \
    "$app_path/Contents/Frameworks" \
    "$app_path/Contents/PlugIns" \
    "$app_path/Contents/Resources" \
    "$xpc_path/Contents/MacOS" \
    "$xpc_path/Contents/Frameworks"

  build_righttool_core_dylib "$manual_build_dir/core"
  build_preview_executables \
    "$manual_build_dir/core" \
    "$app_path/Contents/MacOS/$APP_NAME" \
    "$xpc_path/Contents/MacOS/RightToolActionRunner"
  cp "$manual_build_dir/core/libRightToolCore.dylib" "$app_path/Contents/Frameworks/"
  cp "$manual_build_dir/core/libRightToolCore.dylib" "$xpc_path/Contents/Frameworks/"
  write_app_info_plist "$app_path/Contents/Info.plist"
  write_xpc_info_plist "$xpc_path/Contents/Info.plist"
  build_finder_extension_bundle "$manual_build_dir/core" "$appex_path"

  cat > "$app_path/Contents/Resources/PACKAGING-NOTES.txt" <<'NOTES'
RightTool SwiftPM preview bundle.

This artifact is useful for validating the menu-bar app scaffold and embedded
ActionRunner binary. It includes a manually packaged Finder Sync .appex for
local testing. It is ad-hoc signed when codesign is available, but it is not
Developer ID signed or notarized.
NOTES

  write_entitlements_plist "$entitlements_path"
  codesign_if_available "$entitlements_path" "$app_path" "$xpc_path" "$appex_path"
  validate_preview_bundle "$app_path" "$xpc_path" "$appex_path"

  mkdir -p "$DIST_DIR"
  ditto -c -k --keepParent "$app_path" "$DIST_DIR/$APP_NAME-$(version_name)-$ARTIFACT_SUFFIX-preview.zip"
}

if ! package_xcode_archive_if_configured; then
  package_swiftpm_preview_bundle
fi
