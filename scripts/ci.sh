```sh
#!/bin/sh
# Runs CalcUI checks.
#
#   ./scripts/ci.sh

set -e

DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/.." && pwd)
BIN="$ROOT/bin"

if ! command -v odin >/dev/null 2>&1; then
    echo "odin was not found. Put the Odin compiler on the PATH." >&2
    exit 1
fi

mkdir -p "$BIN"
cd "$ROOT"

# Determine executable extension.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        EXE_EXT=".exe"
        ;;
    *)
        EXE_EXT=""
        ;;
esac

echo
echo "== Checking src/GUI"
odin check src/GUI -no-entry-point

echo
echo "== Testing src/GUI"
CALCUI_SKIP_BENCH=1 odin test src/GUI

echo
echo "== Building the examples"
for EXAMPLE in examples/*/; do
    [ -f "$EXAMPLE/main.odin" ] || continue

    NAME=$(basename "$EXAMPLE")

    echo "Building $NAME"
    odin build "$EXAMPLE" -out:"$BIN/$NAME$EXE_EXT"
done

echo
echo "== Checking src/Window"
odin check src/Window -no-entry-point

echo
echo "== Checking src/Backend"
odin check src/Backend -no-entry-point

echo
echo "== Rendering a picture"
SDL_VIDEODRIVER=dummy odin run tools/shot -- "$BIN/shot.png"

if [ ! -s "$BIN/shot.png" ]; then
    echo "The picture was not written." >&2
    exit 1
fi

echo
echo "Passed: src/GUI, the tests of src/GUI, the examples, src/Window,"
echo "src/Backend and the picture in bin/shot.png."
```