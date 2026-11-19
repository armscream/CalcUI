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
echo "== Checking src/GUI/NodeGraph"
odin check src/GUI/NodeGraph -no-entry-point

echo
echo "== Testing src/GUI/NodeGraph"
odin test src/GUI/NodeGraph -define:ODIN_TEST_THREADS=1

echo
echo "== Checking src/Tests"
odin check src/Tests -no-entry-point

echo
echo "== Testing src/Tests"
CALCUI_BENCH_BUDGET=0 \
CALCUI_BENCH_OUTPUT=docs/other/internalbenchmarks.md \
CALCUI_BENCH_BUILD=minimal \
odin test src/Tests -define:ODIN_TEST_THREADS=1

echo
echo "== Testing src/GUI/Accessibility"
odin test src/GUI/Accessibility -define:ODIN_TEST_THREADS=1

echo
echo "== Testing examples/09_node_graph/blueprint"
odin test examples/09_node_graph/blueprint -define:ODIN_TEST_THREADS=1

echo
echo "== Testing examples/09_node_graph"
odin test examples/09_node_graph -define:ODIN_TEST_THREADS=1

echo
echo "== Checking examples/09_node_graph/features"
odin check examples/09_node_graph/features -no-entry-point

echo
echo "== Building the examples"
for EXAMPLE in examples/*/; do
    [ -f "$EXAMPLE/main.odin" ] || continue

    NAME=$(basename "$EXAMPLE")

    echo "Building $NAME"
    odin build "$EXAMPLE" -out:"$BIN/$NAME$EXE_EXT"
done

echo
echo "== Checking src/Platform"
odin check src/Platform -no-entry-point

echo
echo "== Checking src/GUI/Accessibility"
odin check src/GUI/Accessibility -no-entry-point

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
echo "== Rendering the node graph picture"
SDL_VIDEODRIVER=dummy odin run tools/shot_node_graph -- "$BIN/shot_node_graph.png"

if [ ! -s "$BIN/shot_node_graph.png" ]; then
    echo "The node graph picture was not written." >&2
    exit 1
fi

echo
echo "== Rendering the SDF picture and checking its pixels"
odin run tools/shot_sdf -- "$BIN/shot_sdf.ppm"

if [ ! -s "$BIN/shot_sdf.ppm" ]; then
    echo "The SDF picture was not written." >&2
    exit 1
fi

odin run tools/shot_sdf -- verify
odin run tools/shot_sdf -- parity

echo
echo "Passed: src/GUI/NodeGraph and its tests, src/GUI, src/Tests, src/GUI/Accessibility, the blueprint tests,"
echo "the examples, src/Platform, src/Backend and the three pictures."
