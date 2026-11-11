#!/bin/sh
# Builds the SPIR-V the GPU backend loads.
#
# The shaders are compiled with glslc, which comes with the Vulkan SDK.
# The compiled files are kept in the repository, so a build of CalcUI
# does not need the SDK; run this script after every change of ui.vert
# or ui.frag.
#
#   ./build_shaders.sh

set -e

DIR=$(cd "$(dirname "$0")" && pwd)
SHADERS="$DIR/Shaders"

if ! command -v glslc >/dev/null 2>&1; then
    echo "glslc was not found. It comes with the Vulkan SDK." >&2
    exit 1
fi

echo "Building ui.spv.vert"
glslc -fshader-stage=vertex "$SHADERS/ui.vert" -o "$SHADERS/ui.spv.vert"

echo "Building ui.spv.frag"
glslc -fshader-stage=fragment "$SHADERS/ui.frag" -o "$SHADERS/ui.spv.frag"

echo "Done."
