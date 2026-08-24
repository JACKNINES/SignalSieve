#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"
BUILD_DIR="$PROJECT_ROOT/.build/manual"
APP_OUTPUT_ROOT="${1:-$PROJECT_ROOT/.build/app}"
APP_BUNDLE="$APP_OUTPUT_ROOT/Signal Sieve.app"
PREVIOUS_APP="$APP_OUTPUT_ROOT/Signal Sieve.previous.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
RESOURCES_DIR="$CONTENTS/Resources"
PIXEL_MODULE_DIR="$RESOURCES_DIR/PixelModules/Baseline"
SPECTRAL_MODULE_DIR="$RESOURCES_DIR/PixelModules/Spectral"
PDF_TOOLS_DIR="$RESOURCES_DIR/PDFTools"
LICENSES_DIR="$RESOURCES_DIR/Licenses"
THEME_ICONS_DIR="$RESOURCES_DIR/ThemeIcons"
ICON_FILE="$PROJECT_ROOT/Packaging/SignalSieveIcon.icns"

"$PROJECT_ROOT/build-local.sh"

if [[ -e "$APP_BUNDLE" ]]; then
    mv "$APP_BUNDLE" "$PREVIOUS_APP"
fi

mkdir -p \
    "$MACOS_DIR" \
    "$FRAMEWORKS_DIR" \
    "$RESOURCES_DIR" \
    "$PIXEL_MODULE_DIR" \
    "$SPECTRAL_MODULE_DIR" \
    "$PDF_TOOLS_DIR" \
    "$THEME_ICONS_DIR" \
    "$LICENSES_DIR/SignalSieve" \
    "$LICENSES_DIR/qpdf" \
    "$LICENSES_DIR/libjpeg-turbo"
cp "$PROJECT_ROOT/Packaging/Info.plist" "$CONTENTS/Info.plist"
cp "$BUILD_DIR/SignalSieve" "$MACOS_DIR/SignalSieve"
cp "$BUILD_DIR/libSignalSieveCore.dylib" "$FRAMEWORKS_DIR/libSignalSieveCore.dylib"
cp "$ICON_FILE" "$RESOURCES_DIR/SignalSieveIcon.icns"
cp "$PROJECT_ROOT/Packaging/ThemeIcons/SignalSieveIcon-Dark.png" \
    "$THEME_ICONS_DIR/SignalSieveIcon-Dark.png"
cp "$PROJECT_ROOT/Packaging/ThemeIcons/SignalSieveIcon-Light.png" \
    "$THEME_ICONS_DIR/SignalSieveIcon-Light.png"
cp "$PROJECT_ROOT/Packaging/ThemeIcons/SignalSieveIcon-IridescentPink.png" \
    "$THEME_ICONS_DIR/SignalSieveIcon-IridescentPink.png"
cp "$PROJECT_ROOT/Packaging/PixelModules/Baseline/signalsieve-pixel-module.json" \
    "$PIXEL_MODULE_DIR/signalsieve-pixel-module.json"
cp "$BUILD_DIR/SignalSievePixelBaseline" \
    "$PIXEL_MODULE_DIR/SignalSievePixelBaseline"
cp "$PROJECT_ROOT/Packaging/PixelModules/Spectral/signalsieve-pixel-module.json" \
    "$SPECTRAL_MODULE_DIR/signalsieve-pixel-module.json"
cp "$BUILD_DIR/SignalSievePixelSpectral" \
    "$SPECTRAL_MODULE_DIR/SignalSievePixelSpectral"
cp "$BUILD_DIR/SignalSievePDFSanitizer" \
    "$PDF_TOOLS_DIR/SignalSievePDFSanitizer"
cp "$PROJECT_ROOT/.build/vendor/src/qpdf/LICENSE.txt" "$LICENSES_DIR/qpdf/LICENSE.txt"
cp "$PROJECT_ROOT/.build/vendor/src/qpdf/NOTICE.md" "$LICENSES_DIR/qpdf/NOTICE.md"
cp "$PROJECT_ROOT/.build/vendor/src/libjpeg-turbo/LICENSE.md" \
    "$LICENSES_DIR/libjpeg-turbo/LICENSE.md"
cp "$PROJECT_ROOT/LICENSE" "$LICENSES_DIR/SignalSieve/LICENSE"
cp "$PROJECT_ROOT/TRADEMARKS.md" "$RESOURCES_DIR/TRADEMARKS.md"
cp "$PROJECT_ROOT/Packaging/SOURCE.md" "$RESOURCES_DIR/SOURCE.md"

install_name_tool \
    -add_rpath @executable_path/../Frameworks \
    "$MACOS_DIR/SignalSieve"
install_name_tool \
    -add_rpath @executable_path/../../../Frameworks \
    "$PIXEL_MODULE_DIR/SignalSievePixelBaseline"
install_name_tool \
    -add_rpath @executable_path/../../../Frameworks \
    "$SPECTRAL_MODULE_DIR/SignalSievePixelSpectral"

chmod 755 "$MACOS_DIR/SignalSieve"
chmod 755 "$PIXEL_MODULE_DIR/SignalSievePixelBaseline"
chmod 755 "$SPECTRAL_MODULE_DIR/SignalSievePixelSpectral"
chmod 755 "$PDF_TOOLS_DIR/SignalSievePDFSanitizer"
codesign --force --sign - "$FRAMEWORKS_DIR/libSignalSieveCore.dylib"
codesign --force --sign - "$PIXEL_MODULE_DIR/SignalSievePixelBaseline"
codesign --force --sign - "$SPECTRAL_MODULE_DIR/SignalSievePixelSpectral"
codesign --force --sign - "$PDF_TOOLS_DIR/SignalSievePDFSanitizer"
codesign --force --sign - --deep "$APP_BUNDLE"

plutil -lint "$CONTENTS/Info.plist"
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ -e "$PREVIOUS_APP" ]]; then
    rm -R "$PREVIOUS_APP"
fi

print "Signal Sieve app created at $APP_BUNDLE"
