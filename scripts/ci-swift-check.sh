#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
RIGHTCLICKPRO_MACOS_DEPLOYMENT_TARGET="${RIGHTCLICKPRO_MACOS_DEPLOYMENT_TARGET:-${MACOSX_DEPLOYMENT_TARGET:-14.0}}"
export MACOSX_DEPLOYMENT_TARGET="$RIGHTCLICKPRO_MACOS_DEPLOYMENT_TARGET"

case "$CONFIGURATION" in
  release|debug) ;;
  *)
    echo "Unsupported configuration: $CONFIGURATION" >&2
    exit 64
    ;;
esac

if [[ ! "$RIGHTCLICKPRO_MACOS_DEPLOYMENT_TARGET" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Unsupported RIGHTCLICKPRO_MACOS_DEPLOYMENT_TARGET value: $RIGHTCLICKPRO_MACOS_DEPLOYMENT_TARGET" >&2
  exit 64
fi

swift_target_triple() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    arm64|x86_64)
      printf "%s-apple-macosx%s" "$arch" "$RIGHTCLICKPRO_MACOS_DEPLOYMENT_TARGET"
      ;;
    *)
      echo "Unsupported macOS build architecture: $arch" >&2
      exit 64
      ;;
  esac
}

SWIFT_TARGET_TRIPLE="$(swift_target_triple)"

swift package describe >/dev/null
swift build -c "$CONFIGURATION" --triple "$SWIFT_TARGET_TRIPLE"
swift test -c "$CONFIGURATION" --triple "$SWIFT_TARGET_TRIPLE"
