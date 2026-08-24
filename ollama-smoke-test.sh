#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"
BUILD_DIR="$PROJECT_ROOT/.build/manual"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
TARGET_ARCH="$(uname -m)"
DEPLOYMENT_TARGET="$TARGET_ARCH-apple-macosx13.0"
SIGNALSIEVE_OLLAMA_MODEL="${1:-qwen3.5:4b}"

if [[ -d "$COMPATIBLE_SDK" ]]; then
    SDK_PATH="$COMPATIBLE_SDK"
else
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

"$PROJECT_ROOT/build-local.sh"

swiftc \
    -warnings-as-errors \
    -target "$DEPLOYMENT_TARGET" \
    -parse-as-library \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -I "$BUILD_DIR" \
    -I "$PROJECT_ROOT/Sources/CSignalSieveZip/include" \
    -L "$BUILD_DIR" \
    -lSignalSieveCore \
    "$PROJECT_ROOT/Tests/OllamaIntegrationRunner/main.swift" \
    -o "$BUILD_DIR/SignalSieveOllamaIntegration" \
    -Xlinker -rpath \
    -Xlinker @executable_path

"$BUILD_DIR/SignalSieveOllamaIntegration" "$SIGNALSIEVE_OLLAMA_MODEL"
