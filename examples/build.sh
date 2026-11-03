#!/bin/sh
# Builds every example.
#
#   ./build.sh
#
# The examples are built into the bin directory of the repository, so
# that they can be started from one place.

set -e

DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
BIN="$ROOT/bin"

if ! command -v odin >/dev/null 2>&1; then
    echo "odin was not found. Put the Odin compiler on the PATH." >&2
    exit 1
fi

mkdir -p "$BIN"

for EXAMPLE in "$DIR"/*/; do
    [ -f "$EXAMPLE/main.odin" ] || continue
    NAME=$(basename "$EXAMPLE")
    echo "Building $NAME"
    odin build "$EXAMPLE" -out:"$BIN/$NAME"
done

echo "Done. The programs are in $BIN."
