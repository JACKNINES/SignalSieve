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
THEME_ICON_DARK="$APP_BUNDLE/Contents/Resources/ThemeIcons/SignalSieveIcon-Dark.png"
THEME_ICON_LIGHT="$APP_BUNDLE/Contents/Resources/ThemeIcons/SignalSieveIcon-Light.png"
THEME_ICON_PINK="$APP_BUNDLE/Contents/Resources/ThemeIcons/SignalSieveIcon-IridescentPink.png"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
TESTING_FRAMEWORK_FLAGS=()
for framework_directory in \
    "$(xcode-select -p)/Library/Developer/Frameworks" \
    "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
    "$(xcrun --show-sdk-platform-path 2>/dev/null)/Developer/Library/Frameworks"; do
    if [[ -d "$framework_directory/Testing.framework" ]]; then
        TESTING_FRAMEWORK_FLAGS+=(-F "$framework_directory")
    fi
done
if (( ${#TESTING_FRAMEWORK_FLAGS} == 0 )); then
    print -u2 "Testing.framework not found in any known toolchain layout."
    exit 1
fi
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
TARGET_ARCH="$(uname -m)"

require_command_output() {
    local expected="$1"
    local failure_message="$2"
    shift 2

    local command_output
    if ! command_output="$("$@")"; then
        print -u2 "Inspection command failed: $failure_message"
        return 1
    fi
    if [[ "$command_output" != *"$expected"* ]]; then
        print -u2 "$failure_message"
        return 1
    fi
}

reject_command_output() {
    local rejected="$1"
    local failure_message="$2"
    shift 2

    local command_output
    if ! command_output="$("$@")"; then
        print -u2 "Inspection command failed: $failure_message"
        return 1
    fi
    if [[ "$command_output" == *"$rejected"* ]]; then
        print -u2 "$failure_message"
        return 1
    fi
}

if [[ -d "$COMPATIBLE_SDK" ]]; then
    SDK_PATH="$COMPATIBLE_SDK"
else
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

"$PROJECT_ROOT/check.sh"

swiftc \
    -typecheck \
    -warnings-as-errors \
    -target "$TARGET_ARCH-apple-macosx13.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -I "$PROJECT_ROOT/.build/manual" \
    -I "$PROJECT_ROOT/Sources/CSignalSieveZip/include" \
    "${TESTING_FRAMEWORK_FLAGS[@]}" \
    -enable-testing \
    -Xfrontend -disable-cross-import-overlays \
    "$PROJECT_ROOT/Tests/SignalSieveCoreTests"/*.swift

for script in "$PROJECT_ROOT"/*.sh "$PROJECT_ROOT"/*.command; do
    zsh -n "$script"
done

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --verify --deep --strict "$APP_BUNDLE"

require_command_output \
    '@rpath/libSignalSieveCore.dylib' \
    'Packaged executable does not use the expected private framework path.' \
    otool -L "$EXECUTABLE"

require_command_output \
    '@executable_path/../Frameworks' \
    'Packaged executable is missing its private Frameworks rpath.' \
    otool -l "$EXECUTABLE"

if [[ ! -x "$EXECUTABLE" \
    || ! -r "$FRAMEWORK" \
    || ! -x "$PIXEL_MODULE" \
    || ! -r "$PIXEL_MANIFEST" \
    || ! -x "$SPECTRAL_MODULE" \
    || ! -r "$SPECTRAL_MANIFEST" \
    || ! -x "$PDF_SANITIZER" \
    || ! -r "$PROJECT_LICENSE" \
    || ! -r "$SOURCE_NOTICE" \
    || ! -r "$TRADEMARK_NOTICE" \
    || ! -r "$THEME_ICON_DARK" \
    || ! -r "$THEME_ICON_LIGHT" \
    || ! -r "$THEME_ICON_PINK" ]]; then
    print -u2 "Packaged executable or core framework has invalid permissions."
    exit 1
fi

for theme_icon in "$THEME_ICON_DARK" "$THEME_ICON_LIGHT" "$THEME_ICON_PINK"; do
    if ! THEME_ICON_METADATA="$(sips -g pixelWidth -g pixelHeight "$theme_icon")"; then
        print -u2 "Unable to inspect packaged theme icon: $theme_icon"
        exit 1
    fi
    if [[ "$THEME_ICON_METADATA" != *'pixelWidth: 1024'* \
        || "$THEME_ICON_METADATA" != *'pixelHeight: 1024'* ]]; then
        print -u2 "Packaged theme icon is not 1024 by 1024: $theme_icon"
        exit 1
    fi
done

if ! grep -F 'Mozilla Public License Version 2.0' "$PROJECT_LICENSE" \
        || ! grep -F 'MPL-2.0' "$SOURCE_NOTICE"; then
    print -u2 "Packaged application is missing its MPL source notice."
    exit 1
fi

reject_command_output \
    '/opt/homebrew' \
    'Bundled PDF sanitizer has an unexpected Homebrew runtime dependency.' \
    otool -L "$PDF_SANITIZER"
require_command_output \
    'minos 13.0' \
    'Bundled PDF sanitizer does not preserve the macOS 13 deployment target.' \
    vtool -show-build "$PDF_SANITIZER"

require_command_output \
    '@rpath/libSignalSieveCore.dylib' \
    'Bundled pixel baseline does not use the private core framework.' \
    otool -L "$PIXEL_MODULE"

require_command_output \
    '@executable_path/../../../Frameworks' \
    'Bundled pixel baseline is missing its packaged Frameworks rpath.' \
    otool -l "$PIXEL_MODULE"

require_command_output \
    '@rpath/libSignalSieveCore.dylib' \
    'Bundled spectral pixel module does not use the private core framework.' \
    otool -L "$SPECTRAL_MODULE"

require_command_output \
    '@executable_path/../../../Frameworks' \
    'Bundled spectral pixel module is missing its packaged Frameworks rpath.' \
    otool -l "$SPECTRAL_MODULE"

if grep -rnE 'URLSession|NWConnection|NWBrowser|import Network|WKWebView' \
        "$PROJECT_ROOT/Sources"; then
    print -u2 "Unexpected in-process network client found in privacy-sensitive sources."
    exit 1
else
    NETWORK_SCAN_STATUS=$?
    if (( NETWORK_SCAN_STATUS != 1 )); then
        print -u2 "Unable to scan privacy-sensitive sources for network clients."
        exit 1
    fi
fi

# Subprocess networking is also a privacy boundary. Only the two documented,
# fixed-path curl bridges may exist, and both must remain pinned to numeric
# loopback literals. Any new network-capable executable or shell bridge fails
# closed until it is reviewed and explicitly allowlisted here.
NETWORK_TOOL_PATTERN='/((usr/bin)|(usr/local/bin)|(opt/homebrew/bin))/(curl|wget|nc|ncat|socat|ftp|telnet)'
if ! NETWORK_TOOL_MATCHES="$(grep -rnE "$NETWORK_TOOL_PATTERN" "$PROJECT_ROOT/Sources")"; then
    print -u2 "Expected documented loopback curl bridges were not found."
    exit 1
fi
NETWORK_TOOL_MATCH_COUNT="$(print -r -- "$NETWORK_TOOL_MATCHES" | grep -c '.')"
if [[ "$NETWORK_TOOL_MATCH_COUNT" != "2" ]] \
    || [[ "$NETWORK_TOOL_MATCHES" != *'Sources/SignalSieveCore/LocalRewriteEngine.swift'* ]] \
    || [[ "$NETWORK_TOOL_MATCHES" != *'Sources/SignalSieveCore/CommunityWatermarkService.swift'* ]]; then
    print -r -- "$NETWORK_TOOL_MATCHES"
    print -u2 "Unexpected subprocess network tool found in privacy-sensitive sources."
    exit 1
fi
if ! grep -F 'http://127.0.0.1:11434/api/chat' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/LocalRewriteEngine.swift" >/dev/null \
    || ! grep -F 'http://127.0.0.1:8765' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/CommunityWatermarkService.swift" >/dev/null; then
    print -u2 "Approved subprocess network bridges are no longer pinned to numeric loopback."
    exit 1
fi
if grep -rnE 'fileURLWithPath: "/bin/(sh|bash|zsh)"' "$PROJECT_ROOT/Sources"; then
    print -u2 "Shell subprocesses are not allowed in privacy-sensitive sources."
    exit 1
else
    SHELL_SCAN_STATUS=$?
    if (( SHELL_SCAN_STATUS != 1 )); then
        print -u2 "Unable to scan privacy-sensitive sources for shell subprocesses."
        exit 1
    fi
fi

# Defensive-analysis invariants. These prevent later refactors from silently
# removing the bounds and serialization verified by adversarial regression
# tests in this repository.
if ! grep -F 'private actor ClipboardAnalysisWorker' \
        "$PROJECT_ROOT/Sources/SignalSieve/App/SignalSieveViewModel.swift" >/dev/null \
    || ! grep -F 'guard pasteboard.changeCount == expectedChangeCount' \
        "$PROJECT_ROOT/Sources/SignalSieve/App/SignalSieveViewModel.swift" >/dev/null; then
    print -u2 "Active Guard lost its serial off-main worker or stale-pasteboard guard."
    exit 1
fi
if ! grep -F 'public static let maximumReportedFindings = 10_000' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/HiddenTextAnalyzer.swift" >/dev/null \
    || ! grep -F 'omittedActionableFindingCount' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/HiddenTextAnalyzer.swift" >/dev/null; then
    print -u2 "Hidden Unicode evidence is no longer bounded with complete risk accounting."
    exit 1
fi
if ! grep -F 'timeout.isFinite' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/CommunityWatermarkService.swift" >/dev/null \
    || ! grep -F 'readBoundedResponse(at: outputURL)' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/CommunityWatermarkService.swift" >/dev/null; then
    print -u2 "Community Engine timeout or response-size preflight was removed."
    exit 1
fi
for pixel_source in \
    "$PROJECT_ROOT/Sources/SignalSieveCore/PixelLSBForensics.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/PixelSpectralForensics.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ExternalPixelWatermarkEngine.swift"; do
    if ! grep -F 'strength.isFinite' "$pixel_source" >/dev/null; then
        print -u2 "A pixel regeneration path no longer rejects non-finite strength: $pixel_source"
        exit 1
    fi
done
if ! grep -F 'data.count.isMultiple(of: 2)' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/TextEncodingDetector.swift" >/dev/null \
    || ! grep -F 'data.count.isMultiple(of: 4)' \
        "$PROJECT_ROOT/Sources/SignalSieveCore/TextEncodingDetector.swift" >/dev/null; then
    print -u2 "Strict UTF-16/UTF-32 code-unit validation was removed."
    exit 1
fi

if ! SOURCE_SYMLINK="$(
    find "$PROJECT_ROOT/Sources" "$PROJECT_ROOT/Tests" -type l -print -quit
)"; then
    print -u2 "Unable to scan sources and tests for symbolic links."
    exit 1
fi
if [[ -n "$SOURCE_SYMLINK" ]]; then
    print -r -- "$SOURCE_SYMLINK"
    print -u2 "Source or test symlinks are not allowed by the quality gate."
    exit 1
fi

print "Quality gate passed: tests, warnings, scripts, privacy restrictions, linkage, plist, and signature."
