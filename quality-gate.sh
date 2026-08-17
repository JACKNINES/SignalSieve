#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"
APP_BUNDLE="$PROJECT_ROOT/.build/app/Signal Sieve.app"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/SignalSieve"
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/libSignalSieveCore.dylib"
PIXEL_MODULE="$APP_BUNDLE/Contents/Resources/PixelModules/Baseline/SignalSievePixelBaseline"
PIXEL_MANIFEST="$APP_BUNDLE/Contents/Resources/PixelModules/Baseline/signalsieve-pixel-module.json"
SPECTRAL_MODULE="$APP_BUNDLE/Contents/Resources/PixelModules/Spectral/SignalSievePixelSpectral"
SPECTRAL_MANIFEST="$APP_BUNDLE/Contents/Resources/PixelModules/Spectral/signalsieve-pixel-module.json"
PDF_SANITIZER="$APP_BUNDLE/Contents/Resources/PDFTools/SignalSievePDFSanitizer"
PROJECT_LICENSE="$APP_BUNDLE/Contents/Resources/Licenses/SignalSieve/LICENSE"
SOURCE_NOTICE="$APP_BUNDLE/Contents/Resources/SOURCE.md"
TRADEMARK_NOTICE="$APP_BUNDLE/Contents/Resources/TRADEMARKS.md"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
TESTING_FRAMEWORKS="$(xcode-select -p)/Library/Developer/Frameworks"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
TARGET_ARCH="$(uname -m)"

if [[ -d "$COMPATIBLE_SDK" ]]; then
    SDK_PATH="$COMPATIBLE_SDK"
else
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

"$PROJECT_ROOT/check.sh"

RESTRICTION_TESTS=(
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/ClipboardProtectionAnalyzerTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/ClipboardImageImporterTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/ExternalPixelWatermarkEngineTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/FileMetadataCleanerTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/FileProvenanceAnalyzerTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/HiddenTextAnalyzerTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/LocalRewriteEngineTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/PixelLSBForensicsTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/PixelSpectralForensicsTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/TextCleanerTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/VaccineEngineTests.swift"
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests/WatermarkProbeAnalyzerTests.swift"
)
for test_file in "${RESTRICTION_TESTS[@]}"; do
    swiftc \
        -typecheck \
        -warnings-as-errors \
        -target "$TARGET_ARCH-apple-macosx13.0" \
        -sdk "$SDK_PATH" \
        -module-cache-path "$MODULE_CACHE" \
        -I "$PROJECT_ROOT/.build/manual" \
        -I "$PROJECT_ROOT/Sources/CSignalSieveZip/include" \
        -F "$TESTING_FRAMEWORKS" \
        -enable-testing \
        -Xfrontend -disable-cross-import-overlays \
        "$test_file"
done

for script in "$PROJECT_ROOT"/*.sh "$PROJECT_ROOT"/*.command; do
    zsh -n "$script"
done

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --verify --deep --strict "$APP_BUNDLE"

if ! otool -L "$EXECUTABLE" | rg --fixed-strings '@rpath/libSignalSieveCore.dylib'; then
    print -u2 "Packaged executable does not use the expected private framework path."
    exit 1
fi

if ! otool -l "$EXECUTABLE" | rg --fixed-strings '@executable_path/../Frameworks'; then
    print -u2 "Packaged executable is missing its private Frameworks rpath."
    exit 1
fi

if [[ ! -x "$EXECUTABLE" \
    || ! -r "$FRAMEWORK" \
    || ! -x "$PIXEL_MODULE" \
    || ! -r "$PIXEL_MANIFEST" \
    || ! -x "$SPECTRAL_MODULE" \
    || ! -r "$SPECTRAL_MANIFEST" \
    || ! -x "$PDF_SANITIZER" \
    || ! -r "$PROJECT_LICENSE" \
    || ! -r "$SOURCE_NOTICE" \
    || ! -r "$TRADEMARK_NOTICE" ]]; then
    print -u2 "Packaged executable or core framework has invalid permissions."
    exit 1
fi

if ! rg --fixed-strings 'Mozilla Public License Version 2.0' "$PROJECT_LICENSE" \
        || ! rg --fixed-strings 'MPL-2.0' "$SOURCE_NOTICE"; then
    print -u2 "Packaged application is missing its MPL source notice."
    exit 1
fi

if otool -L "$PDF_SANITIZER" | rg --fixed-strings '/opt/homebrew'; then
    print -u2 "Bundled PDF sanitizer has an unexpected Homebrew runtime dependency."
    exit 1
fi
if ! vtool -show-build "$PDF_SANITIZER" | rg --fixed-strings 'minos 13.0'; then
    print -u2 "Bundled PDF sanitizer does not preserve the macOS 13 deployment target."
    exit 1
fi

if ! otool -L "$PIXEL_MODULE" | rg --fixed-strings '@rpath/libSignalSieveCore.dylib'; then
    print -u2 "Bundled pixel baseline does not use the private core framework."
    exit 1
fi

if ! otool -l "$PIXEL_MODULE" | rg --fixed-strings '@executable_path/../../../Frameworks'; then
    print -u2 "Bundled pixel baseline is missing its packaged Frameworks rpath."
    exit 1
fi

if ! otool -L "$SPECTRAL_MODULE" | rg --fixed-strings '@rpath/libSignalSieveCore.dylib'; then
    print -u2 "Bundled spectral pixel module does not use the private core framework."
    exit 1
fi

if ! otool -l "$SPECTRAL_MODULE" | rg --fixed-strings '@executable_path/../../../Frameworks'; then
    print -u2 "Bundled spectral pixel module is missing its packaged Frameworks rpath."
    exit 1
fi

if rg --line-number 'URLSession|NWConnection|NWBrowser|import Network|WKWebView' \
        "$PROJECT_ROOT/Sources"; then
    print -u2 "Unexpected in-process network client found in privacy-sensitive sources."
    exit 1
fi

if find "$PROJECT_ROOT/Sources" "$PROJECT_ROOT/Tests" -type l | rg '.'; then
    print -u2 "Source or test symlinks are not allowed by the quality gate."
    exit 1
fi

print "Quality gate passed: tests, warnings, scripts, privacy restrictions, linkage, plist, and signature."
