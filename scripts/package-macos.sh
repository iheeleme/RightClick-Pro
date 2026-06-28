#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
APP_NAME="${APP_NAME:-RightClick Pro}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.iheeleme.rightclickpro}"
XPC_BUNDLE_IDENTIFIER="${XPC_BUNDLE_IDENTIFIER:-com.iheeleme.rightclickpro.ActionRunner}"
FINDER_EXTENSION_BUNDLE_IDENTIFIER="${FINDER_EXTENSION_BUNDLE_IDENTIFIER:-com.iheeleme.rightclickpro.FinderExtension}"
APP_GROUP_IDENTIFIER="${APP_GROUP_IDENTIFIER:-group.com.iheeleme.rightclickpro}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:-$(uname -m)}"
DIST_DIR="${DIST_DIR:-dist}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-DerivedData}"
APP_ICON_SOURCE="${APP_ICON_SOURCE:-design/icon.png}"
APP_ICON_NAME="${APP_ICON_NAME:-RightClickProIcon}"
RIGHTCLICKPRO_PACKAGE_DMG="${RIGHTCLICKPRO_PACKAGE_DMG:-0}"
PACKAGED_FINDER_EXTENSION_PATH=""

case "$CONFIGURATION" in
  release|debug) ;;
  *)
    echo "Unsupported configuration: $CONFIGURATION" >&2
    exit 64
    ;;
esac

case "$RIGHTCLICKPRO_PACKAGE_DMG" in
  0|1) ;;
  *)
    echo "Unsupported RIGHTCLICKPRO_PACKAGE_DMG value: $RIGHTCLICKPRO_PACKAGE_DMG. Use 1 to build a DMG." >&2
    exit 64
    ;;
esac

version_name() {
  if [[ -n "${RIGHTCLICKPRO_VERSION:-}" ]]; then
    printf "%s" "$RIGHTCLICKPRO_VERSION"
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
  if [[ -n "${RIGHTCLICKPRO_BUILD_NUMBER:-}" ]]; then
    printf "%s" "$RIGHTCLICKPRO_BUILD_NUMBER"
    return
  fi

  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    printf "%s" "$GITHUB_RUN_NUMBER"
    return
  fi

  printf "1"
}

package_xcode_archive_if_configured() {
  if [[ -z "${RIGHTCLICKPRO_XCODE_PROJECT:-}" && -z "${RIGHTCLICKPRO_XCODE_SCHEME:-}" ]]; then
    return 1
  fi

  if [[ -z "${RIGHTCLICKPRO_XCODE_PROJECT:-}" || -z "${RIGHTCLICKPRO_XCODE_SCHEME:-}" ]]; then
    echo "Both RIGHTCLICKPRO_XCODE_PROJECT and RIGHTCLICKPRO_XCODE_SCHEME are required for Xcode packaging." >&2
    exit 64
  fi

  if [[ ! -e "$RIGHTCLICKPRO_XCODE_PROJECT" ]]; then
    echo "RIGHTCLICKPRO_XCODE_PROJECT does not exist: $RIGHTCLICKPRO_XCODE_PROJECT" >&2
    exit 66
  fi

  local archive_path="$PWD/$DIST_DIR/$APP_NAME.xcarchive"
  mkdir -p "$DIST_DIR"

  xcodebuild archive \
    -project "$RIGHTCLICKPRO_XCODE_PROJECT" \
    -scheme "$RIGHTCLICKPRO_XCODE_SCHEME" \
    -configuration "$(tr '[:lower:]' '[:upper:]' <<< "${CONFIGURATION:0:1}")${CONFIGURATION:1}" \
    -archivePath "$archive_path" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

  if [[ -n "${RIGHTCLICKPRO_EXPORT_OPTIONS_PLIST:-}" && -f "$RIGHTCLICKPRO_EXPORT_OPTIONS_PLIST" ]]; then
    xcodebuild -exportArchive \
      -archivePath "$archive_path" \
      -exportOptionsPlist "$RIGHTCLICKPRO_EXPORT_OPTIONS_PLIST" \
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
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
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
  <string>RightClickProActionRunner</string>
  <key>CFBundleIdentifier</key>
  <string>$XPC_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>RightClickProActionRunner</string>
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
  <string>$APP_NAME Finder Extension</string>
  <key>CFBundleExecutable</key>
  <string>RightClickProFinderExtension</string>
  <key>CFBundleIdentifier</key>
  <string>$FINDER_EXTENSION_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>RightClickProFinderExtension</string>
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
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
  <key>com.apple.security.files.bookmarks.app-scope</key>
  <true/>
</dict>
</plist>
PLIST
}

write_xpc_entitlements_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>$APP_GROUP_IDENTIFIER</string>
  </array>
</dict>
</plist>
PLIST
}

copy_app_icon_resources() {
  local resources_dir="$1"
  local icon_png_path="$resources_dir/$APP_ICON_NAME.png"
  local iconset_path="$resources_dir/$APP_ICON_NAME.iconset"
  local icon_path="$resources_dir/$APP_ICON_NAME.icns"

  if [[ ! -f "$APP_ICON_SOURCE" ]]; then
    echo "App icon source does not exist: $APP_ICON_SOURCE" >&2
    exit 66
  fi

  cp "$APP_ICON_SOURCE" "$icon_png_path"

  if ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    echo "sips and iconutil are required to build the macOS app icon." >&2
    exit 69
  fi

  rm -rf "$iconset_path"
  mkdir -p "$iconset_path"

  local size
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$APP_ICON_SOURCE" \
      --out "$iconset_path/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$APP_ICON_SOURCE" \
      --out "$iconset_path/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$iconset_path" -o "$icon_path"
  rm -rf "$iconset_path"
}

build_rightclickpro_core_dylib() {
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
    -module-name RightClickProCore \
    -emit-module-path "$build_dir/RightClickProCore.swiftmodule" \
    -Xlinker -install_name \
    -Xlinker "@rpath/libRightClickProCore.dylib" \
    Sources/RightClickProCore/*.swift \
    -o "$build_dir/libRightClickProCore.dylib"
}

build_finder_extension_bundle() {
  local core_build_dir="$1"
  local appex_path="$2"
  local executable_path="$appex_path/Contents/MacOS/RightClickProFinderExtension"

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
    -module-name RightClickProFinderExtension \
    -I "$core_build_dir" \
    -L "$core_build_dir" \
    -lRightClickProCore \
    -framework AppKit \
    -framework FinderSync \
    -Xlinker -e \
    -Xlinker _NSExtensionMain \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    Sources/RightClickProFinderExtension/FinderSyncController.swift \
    -o "$executable_path"

  cp "$core_build_dir/libRightClickProCore.dylib" "$appex_path/Contents/Frameworks/"
  write_finder_extension_info_plist "$appex_path/Contents/Info.plist"
}

build_preview_executables() {
  local core_build_dir="$1"
  local app_executable_path="$2"
  local xpc_executable_path="$3"
  local bin_path
  local swiftpm_log="$DIST_DIR/swiftpm-build.log"

  if swift build -c "$CONFIGURATION" --product rightclickpro-app-preview >"$swiftpm_log" 2>&1 \
    && swift build -c "$CONFIGURATION" --product rightclickpro-action-runner >>"$swiftpm_log" 2>&1 \
    && bin_path="$(swift build -c "$CONFIGURATION" --show-bin-path 2>>"$swiftpm_log")"; then
    cp "$bin_path/rightclickpro-app-preview" "$app_executable_path"
    cp "$bin_path/rightclickpro-action-runner" "$xpc_executable_path"
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
    -module-name RightClickPro \
    -I "$core_build_dir" \
    -L "$core_build_dir" \
    -lRightClickProCore \
    -framework AppKit \
    -framework SwiftUI \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    Sources/RightClickProAppPreview/RightClickProAppPreview.swift \
    -o "$app_executable_path"

  swiftc \
    "${swift_flags[@]}" \
    -module-name RightClickProActionRunner \
    -I "$core_build_dir" \
    -L "$core_build_dir" \
    -lRightClickProCore \
    -Xlinker -rpath \
    -Xlinker "@executable_path/../Frameworks" \
    Sources/RightClickProActionRunnerService/main.swift \
    -o "$xpc_executable_path"
}

codesign_if_available() {
  local entitlements_path="$1"
  local xpc_entitlements_path="$2"
  local app_path="$3"
  local xpc_path="$4"
  local appex_path="$5"
  local appex_xpc_path="$6"

  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign not found; leaving preview bundle unsigned." >&2
    return
  fi

  codesign --force --sign "$CODE_SIGN_IDENTITY" "$app_path/Contents/Frameworks/libRightClickProCore.dylib"
  codesign --force --sign "$CODE_SIGN_IDENTITY" "$xpc_path/Contents/Frameworks/libRightClickProCore.dylib"
  codesign --force --sign "$CODE_SIGN_IDENTITY" "$appex_path/Contents/Frameworks/libRightClickProCore.dylib"
  codesign --force --sign "$CODE_SIGN_IDENTITY" "$appex_xpc_path/Contents/Frameworks/libRightClickProCore.dylib"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$xpc_entitlements_path" "$xpc_path"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$xpc_entitlements_path" "$appex_xpc_path"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements_path" "$appex_path"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --entitlements "$entitlements_path" "$app_path"
}

validate_preview_bundle() {
  local app_path="$1"
  local xpc_path="$2"
  local appex_path="$3"
  local appex_xpc_path="$4"
  local appex_executable="$appex_path/Contents/MacOS/RightClickProFinderExtension"
  local extension_point

  test -x "$app_path/Contents/MacOS/$APP_NAME"
  test -x "$xpc_path/Contents/MacOS/RightClickProActionRunner"
  test -x "$appex_xpc_path/Contents/MacOS/RightClickProActionRunner"
  test -x "$appex_executable"
  test -f "$app_path/Contents/Resources/$APP_ICON_NAME.icns"
  test -f "$app_path/Contents/Resources/$APP_ICON_NAME.png"
  test -f "$app_path/Contents/Frameworks/libRightClickProCore.dylib"
  test -f "$xpc_path/Contents/Frameworks/libRightClickProCore.dylib"
  test -f "$appex_path/Contents/Frameworks/libRightClickProCore.dylib"
  test -f "$appex_xpc_path/Contents/Frameworks/libRightClickProCore.dylib"

  local app_icon
  app_icon="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$app_path/Contents/Info.plist")"
  if [[ "$app_icon" != "$APP_ICON_NAME" ]]; then
    echo "Invalid app icon file: $app_icon" >&2
    exit 65
  fi

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
    local entitlements_dump
    entitlements_dump="$(mktemp)"
    codesign -d --entitlements :- "$appex_xpc_path" >"$entitlements_dump" 2>/dev/null || true
    if /usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$entitlements_dump" >/dev/null 2>&1; then
      echo "Preview ActionRunner XPC must not be app-sandboxed." >&2
      rm -f "$entitlements_dump"
      exit 65
    fi
    rm -f "$entitlements_dump"

    codesign --verify --deep --strict --verbose=2 "$app_path"
  fi
}

write_dmg_readme() {
  local readme_path="$1"
  cat > "$readme_path" <<README
${APP_NAME} 内测构建

安装方式
1. 将 "${APP_NAME}.app" 拖到 Applications。
2. 从 Applications 打开 ${APP_NAME}。

安全提示
这个构建用于自用/内测分发，未使用 Developer ID 签名，也未公证。
如果 macOS 阻止打开，可以到 系统设置 > 隐私与安全性 中允许打开；
也可以在 Finder 中右键 "${APP_NAME}.app"，选择“打开”，再确认打开。

启用 Finder Extension
1. 打开 ${APP_NAME}，App 会自动注册并尝试启用 Finder Extension。
2. 如果系统要求手动确认，请前往 系统设置 > 隐私与安全性 > 扩展 > Finder 扩展。
3. 启用 "${APP_NAME} Finder Extension"。

如果 Finder 右键菜单没有出现
1. 在 ${APP_NAME} 概览页点击“重启 Finder”，App 会重新注册扩展并重启 Finder。
2. 确认 Finder 扩展已启用。
3. 重新打开 Finder 右键菜单。
4. 如仍未出现，可在终端手动运行：
   killall Finder

技术信息
App Bundle ID: ${BUNDLE_IDENTIFIER}
Finder Extension Bundle ID: ${FINDER_EXTENSION_BUNDLE_IDENTIFIER}
App Group: ${APP_GROUP_IDENTIFIER}
README
}

smoke_test_dmg() {
  local dmg_path="$1"
  local mount_dir="$PWD/$DIST_DIR/dmg-smoke-mount"

  rm -rf "$mount_dir"
  mkdir -p "$mount_dir"

  hdiutil attach "$dmg_path" -readonly -nobrowse -mountpoint "$mount_dir" >/dev/null

  local status=0
  if [[ ! -d "$mount_dir/$APP_NAME.app" ]]; then
    echo "DMG smoke test failed: missing $APP_NAME.app" >&2
    status=65
  fi
  if [[ ! -L "$mount_dir/Applications" ]]; then
    echo "DMG smoke test failed: missing Applications alias" >&2
    status=65
  fi
  if [[ ! -f "$mount_dir/README.txt" ]]; then
    echo "DMG smoke test failed: missing README.txt" >&2
    status=65
  fi

  hdiutil detach "$mount_dir" >/dev/null || hdiutil detach "$mount_dir" -force >/dev/null
  rm -rf "$mount_dir"

  if [[ "$status" -ne 0 ]]; then
    exit "$status"
  fi
}

package_preview_dmg() {
  local app_path="$1"
  local dmg_root="$PWD/$DIST_DIR/dmg-root"
  local dmg_path="$PWD/$DIST_DIR/$APP_NAME-$(version_name)-$ARTIFACT_SUFFIX-preview.dmg"

  if ! command -v hdiutil >/dev/null 2>&1; then
    echo "hdiutil is required to build a DMG." >&2
    exit 69
  fi

  rm -rf "$dmg_root" "$dmg_path"
  mkdir -p "$dmg_root"

  ditto "$app_path" "$dmg_root/$APP_NAME.app"
  ln -s /Applications "$dmg_root/Applications"
  write_dmg_readme "$dmg_root/README.txt"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$dmg_root" \
    -format UDZO \
    -ov \
    "$dmg_path" >/dev/null

  smoke_test_dmg "$dmg_path"
}

package_swiftpm_preview_bundle() {
  local staging="$PWD/$DIST_DIR/staging"
  local app_path="$staging/$APP_NAME.app"
  local xpc_path="$app_path/Contents/XPCServices/RightClickProActionRunner.xpc"
  local appex_path="$app_path/Contents/PlugIns/RightClickProFinderExtension.appex"
  local appex_xpc_path="$appex_path/Contents/XPCServices/RightClickProActionRunner.xpc"
  local manual_build_dir="$PWD/$DIST_DIR/manual-build"
  local entitlements_path="$manual_build_dir/RightClickPro.entitlements"
  local xpc_entitlements_path="$manual_build_dir/RightClickProActionRunner.entitlements"

  rm -rf "$staging" "$manual_build_dir"
  mkdir -p \
    "$app_path/Contents/MacOS" \
    "$app_path/Contents/Frameworks" \
    "$app_path/Contents/PlugIns" \
    "$app_path/Contents/Resources" \
    "$app_path/Contents/XPCServices" \
    "$xpc_path/Contents/MacOS" \
    "$xpc_path/Contents/Frameworks" \
    "$appex_xpc_path/Contents/MacOS" \
    "$appex_xpc_path/Contents/Frameworks"

  build_rightclickpro_core_dylib "$manual_build_dir/core"
  build_preview_executables \
    "$manual_build_dir/core" \
    "$app_path/Contents/MacOS/$APP_NAME" \
    "$xpc_path/Contents/MacOS/RightClickProActionRunner"
  cp "$manual_build_dir/core/libRightClickProCore.dylib" "$app_path/Contents/Frameworks/"
  cp "$manual_build_dir/core/libRightClickProCore.dylib" "$xpc_path/Contents/Frameworks/"
  copy_app_icon_resources "$app_path/Contents/Resources"
  write_app_info_plist "$app_path/Contents/Info.plist"
  write_xpc_info_plist "$xpc_path/Contents/Info.plist"
  build_finder_extension_bundle "$manual_build_dir/core" "$appex_path"
  ditto "$xpc_path" "$appex_xpc_path"

  cat > "$app_path/Contents/Resources/PACKAGING-NOTES.txt" <<NOTES
${APP_NAME} SwiftPM preview bundle.

This artifact is useful for validating the menu-bar app scaffold and embedded
ActionRunner binary. It includes a manually packaged Finder Sync .appex for
local testing. It is ad-hoc signed when codesign is available, but it is not
Developer ID signed or notarized.
NOTES

  write_entitlements_plist "$entitlements_path"
  write_xpc_entitlements_plist "$xpc_entitlements_path"
  codesign_if_available "$entitlements_path" "$xpc_entitlements_path" "$app_path" "$xpc_path" "$appex_path" "$appex_xpc_path"
  validate_preview_bundle "$app_path" "$xpc_path" "$appex_path" "$appex_xpc_path"

  mkdir -p "$DIST_DIR"
  ditto -c -k --keepParent "$app_path" "$DIST_DIR/$APP_NAME-$(version_name)-$ARTIFACT_SUFFIX-preview.zip"
  if [[ "$RIGHTCLICKPRO_PACKAGE_DMG" == "1" ]]; then
    package_preview_dmg "$app_path"
  fi
  PACKAGED_FINDER_EXTENSION_PATH="$appex_path"
}

enable_finder_extension() {
  local appex_path="${1:-}"
  if ! command -v pluginkit >/dev/null 2>&1; then
    return
  fi

  if [[ -n "$appex_path" && -d "$appex_path" ]]; then
    pluginkit -a "$appex_path" >/dev/null 2>&1 || true
  fi

  pluginkit -e use -i "$FINDER_EXTENSION_BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
}

if [[ "$RIGHTCLICKPRO_PACKAGE_DMG" == "1" && -n "${RIGHTCLICKPRO_XCODE_PROJECT:-}" && -n "${RIGHTCLICKPRO_XCODE_SCHEME:-}" ]]; then
  echo "RIGHTCLICKPRO_PACKAGE_DMG=1 is only supported for the SwiftPM preview bundle path." >&2
  exit 64
fi

if ! package_xcode_archive_if_configured; then
  package_swiftpm_preview_bundle
fi

enable_finder_extension "$PACKAGED_FINDER_EXTENSION_PATH"
