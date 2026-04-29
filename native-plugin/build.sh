#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_TYPE="${BUILD_TYPE:-Release}"
GENERATOR="${CMAKE_GENERATOR:-Unix Makefiles}"

cd "$SCRIPT_DIR"
rm -rf build

cmake -S . -B build -G "$GENERATOR" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" "$@"
cmake --build build --config "$BUILD_TYPE"
