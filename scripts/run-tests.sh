#!/usr/bin/env bash
# scripts/run-tests.sh — run the busted unit test suite.
#
# Requires: lua5.3+ and busted. Install once with:
#   sudo apt-get install lua5.3 luarocks
#   sudo luarocks install busted

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v busted >/dev/null 2>&1; then
    echo "error: busted not found in PATH" >&2
    echo "install with: luarocks install busted" >&2
    exit 127
fi

busted --verbose spec/
