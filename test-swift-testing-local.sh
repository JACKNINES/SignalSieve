#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"
BUILD_DIR="$PROJECT_ROOT/.build/manual"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
TARGET_ARCH="$(uname -m)"
# Apple's bundled Testing.framework currently has a macOS 14 deployment
# target. This affects only the local test executable, never the macOS 13 app.
TEST_DEPLOYMENT_TARGET="$TARGET_ARCH-apple-macosx14.0"
CORE_LIBRARY="$BUILD_DIR/libSignalSieveCore.dylib"
APP_LIBRARY="$BUILD_DIR/libSignalSieve.dylib"
PDF_HELPER="$BUILD_DIR/SignalSievePDFSanitizer"
TEST_EXECUTABLE="$BUILD_DIR/SignalSieveSwiftTestingTests"

if [[ -d "$COMPATIBLE_SDK" ]]; then
    SDK_PATH="$COMPATIBLE_SDK"
else
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

TESTING_FRAMEWORK_DIRECTORIES=()
for framework_directory in \
    "$(xcode-select -p)/Library/Developer/Frameworks" \
    "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
    "$(xcrun --show-sdk-platform-path 2>/dev/null)/Developer/Library/Frameworks"; do
    if [[ -d "$framework_directory/Testing.framework" \
        && " ${TESTING_FRAMEWORK_DIRECTORIES[*]} " != *" $framework_directory "* ]]; then
        TESTING_FRAMEWORK_DIRECTORIES+=("$framework_directory")
    fi
done
if (( ${#TESTING_FRAMEWORK_DIRECTORIES} == 0 )); then
    print -u2 "Testing.framework not found in any known toolchain layout."
    exit 1
fi

NEEDS_CORE_BUILD=false
if [[ ! -r "$CORE_LIBRARY" || ! -x "$PDF_HELPER" ]]; then
    NEEDS_CORE_BUILD=true
else
    if ! NEWER_BUILD_INPUT="$(
        find \
            "$PROJECT_ROOT/build-local.sh" \
            "$PROJECT_ROOT/Sources/CSignalSieveZip" \
            "$PROJECT_ROOT/Sources/SignalSieveCore" \
            "$PROJECT_ROOT/Sources/SignalSievePDFSanitizer" \
            -type f -newer "$CORE_LIBRARY" -print -quit
    )"; then
        print -u2 "Unable to check whether the local core build is current."
        exit 1
    fi
    if [[ -n "$NEWER_BUILD_INPUT" ]]; then
        NEEDS_CORE_BUILD=true
    fi
fi

if [[ "$NEEDS_CORE_BUILD" == true ]]; then
    "$PROJECT_ROOT/build-local.sh"
fi

TESTING_FRAMEWORK_FLAGS=()
TESTING_RPATH_FLAGS=()
for framework_directory in "${TESTING_FRAMEWORK_DIRECTORIES[@]}"; do
    TESTING_FRAMEWORK_FLAGS+=(-F "$framework_directory")
    TESTING_RPATH_FLAGS+=(-Xlinker -rpath -Xlinker "$framework_directory")
done

NEEDS_TEST_BUILD=false
if [[ ! -x "$TEST_EXECUTABLE" \
    || ! -r "$APP_LIBRARY" \
    || "$CORE_LIBRARY" -nt "$TEST_EXECUTABLE" \
    || "$APP_LIBRARY" -nt "$TEST_EXECUTABLE" ]]; then
    NEEDS_TEST_BUILD=true
else
    if ! NEWER_TEST_INPUT="$(
        find \
            "$PROJECT_ROOT/test-swift-testing-local.sh" \
            "$PROJECT_ROOT/Sources/SignalSieve/App/SignalSieveViewModel.swift" \
            "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/FindingCopyButton.swift" \
            "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/SheetScaffold.swift" \
            "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/SieveControls.swift" \
            "$PROJECT_ROOT/Sources/SignalSieve/Features/ActiveGuard/ClipboardNoticePanel.swift" \
            "$PROJECT_ROOT/Sources/SignalSieve/Platform/ClipboardImagePasteboardReader.swift" \
            "$PROJECT_ROOT/Tests/SignalSieveAppTests" \
            "$PROJECT_ROOT/Tests/SignalSieveCoreTests" \
            "$PROJECT_ROOT/Tests/SwiftTestingLocalRunner" \
            -type f -newer "$TEST_EXECUTABLE" -print -quit
    )"; then
        print -u2 "Unable to check whether the local test executable is current."
        exit 1
    fi
    if [[ -n "$NEWER_TEST_INPUT" ]]; then
        NEEDS_TEST_BUILD=true
    fi
    for framework_directory in "${TESTING_FRAMEWORK_DIRECTORIES[@]}"; do
        if [[ "$framework_directory/Testing.framework/Testing" -nt "$TEST_EXECUTABLE" \
            || "$framework_directory/Testing.framework/Versions/A/Testing" -nt "$TEST_EXECUTABLE" ]]; then
            NEEDS_TEST_BUILD=true
        fi
    done
fi

if [[ "$NEEDS_TEST_BUILD" == true ]]; then
    swiftc \
        -warnings-as-errors \
        -target "$TEST_DEPLOYMENT_TARGET" \
        -enable-testing \
        -parse-as-library \
        -sdk "$SDK_PATH" \
        -module-cache-path "$MODULE_CACHE" \
        -I "$BUILD_DIR" \
        -I "$PROJECT_ROOT/Sources/CSignalSieveZip/include" \
        -L "$BUILD_DIR" \
        -lSignalSieveCore \
        -emit-module \
        -emit-library \
        -module-name SignalSieve \
        "$PROJECT_ROOT/Sources/SignalSieve/App/SignalSieveViewModel.swift" \
        "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/FindingCopyButton.swift" \
        "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/SheetScaffold.swift" \
        "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/SieveControls.swift" \
        "$PROJECT_ROOT/Sources/SignalSieve/Features/ActiveGuard/ClipboardNoticePanel.swift" \
        "$PROJECT_ROOT/Sources/SignalSieve/Platform/ClipboardImagePasteboardReader.swift" \
        -emit-module-path "$BUILD_DIR/SignalSieve.swiftmodule" \
        -o "$APP_LIBRARY" \
        -Xlinker -install_name \
        -Xlinker @rpath/libSignalSieve.dylib \
        -Xlinker -rpath \
        -Xlinker @executable_path

    swiftc \
        -warnings-as-errors \
        -target "$TEST_DEPLOYMENT_TARGET" \
        -parse-as-library \
        -sdk "$SDK_PATH" \
        -module-cache-path "$MODULE_CACHE" \
        -I "$BUILD_DIR" \
        -I "$PROJECT_ROOT/Sources/CSignalSieveZip/include" \
        -L "$BUILD_DIR" \
        -lSignalSieve \
        -lSignalSieveCore \
        "${TESTING_FRAMEWORK_FLAGS[@]}" \
        -enable-testing \
        -Xfrontend -disable-cross-import-overlays \
        "$PROJECT_ROOT/Tests/SignalSieveAppTests"/*.swift \
        "$PROJECT_ROOT/Tests/SignalSieveCoreTests"/*.swift \
        "$PROJECT_ROOT/Tests/SwiftTestingLocalRunner/main.swift" \
        -o "$TEST_EXECUTABLE" \
        -Xlinker -rpath \
        -Xlinker @executable_path \
        "${TESTING_RPATH_FLAGS[@]}"
fi

cd "$PROJECT_ROOT"
"$TEST_EXECUTABLE" "$@"
