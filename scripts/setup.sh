#!/bin/sh
# Prepares a working copy of CalcUI.
#
#   ./scripts/setup.sh
#
# The Runa text engine is a submodule, so it has to be fetched before
# anything can be built. The Odin compiler has to be on the PATH.

set -e

DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)

echo "Fetching the submodules..."
git -C "$ROOT" submodule update --init --recursive

if ! command -v odin >/dev/null 2>&1; then
    echo "odin was not found. Put the Odin compiler on the PATH." >&2
    exit 1
fi

echo "The compiler is:"
odin version

echo "The submodules are at:"
git -C "$ROOT" submodule status
