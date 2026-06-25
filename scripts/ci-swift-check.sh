#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"

case "$CONFIGURATION" in
  release|debug) ;;
  *)
    echo "Unsupported configuration: $CONFIGURATION" >&2
    exit 64
    ;;
esac

swift package describe >/dev/null
swift build -c "$CONFIGURATION"
swift test -c "$CONFIGURATION"
