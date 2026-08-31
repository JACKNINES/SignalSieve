#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"
BUILD_DIR="$PROJECT_ROOT/.build/manual"
MODULE_CACHE="$PROJECT_ROOT/.build/module-cache"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
TARGET_ARCH="$(uname -m)"
DEPLOYMENT_TARGET="$TARGET_ARCH-apple-macosx13.0"
PDF_VENDOR="$PROJECT_ROOT/.build/vendor"
QPDF_SOURCE="$PDF_VENDOR/src/qpdf"
QPDF_BUILD="$PDF_VENDOR/qpdf"
PDF_PREFIX="$PDF_VENDOR/prefix"

if [[ -d "$COMPATIBLE_SDK" ]]; then
    SDK_PATH="$COMPATIBLE_SDK"
else
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

if [[ ! -r "$QPDF_BUILD/libqpdf/libqpdf.a" \
    || ! -r "$PDF_PREFIX/lib/libjpeg.a" \
    || ! -d "$QPDF_SOURCE/include" ]]; then
    print -u2 "Pinned PDF dependencies are missing. Run ./bootstrap-pdf-tools.sh first."
    exit 1
fi

clang++ \
    -std=c++20 \
    -Wall \
    -Wextra \
    -Werror \
    -mmacosx-version-min=13.0 \
    -isysroot "$SDK_PATH" \
    -I "$QPDF_SOURCE/include" \
    -I "$QPDF_SOURCE/libqpdf" \
    -I "$QPDF_BUILD/libqpdf" \
    -I "$PDF_PREFIX/include" \
    "$PROJECT_ROOT/Sources/SignalSievePDFSanitizer/main.cpp" \
    "$QPDF_BUILD/libqpdf/libqpdf.a" \
    "$PDF_PREFIX/lib/libjpeg.a" \
    -lz \
    -o "$BUILD_DIR/SignalSievePDFSanitizer"

clang \
    -target "$DEPLOYMENT_TARGET" \
    -isysroot "$SDK_PATH" \
    -I "$PROJECT_ROOT/Sources/CSignalSieveZip/include" \
    -c "$PROJECT_ROOT/Sources/CSignalSieveZip/CSignalSieveZip.c" \
    -o "$BUILD_DIR/CSignalSieveZip.o"

swiftc \
    -warnings-as-errors \
    -target "$DEPLOYMENT_TARGET" \
    -enable-testing \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -I "$PROJECT_ROOT/Sources/CSignalSieveZip/include" \
    -parse-as-library \
    -emit-module \
    -emit-library \
    -module-name SignalSieveCore \
    "$PROJECT_ROOT/Sources/SignalSieveCore/AppLocalization.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/AppTheme.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/AdaptiveCopyModel.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/BinaryContentDetector.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/BoundedZIPReader.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/BoundedZIPRewriter.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ClipboardProtectionAnalyzer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ClipboardAutomationProtocol.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ClipboardPlainTextWriter.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ClipboardTypeInventory.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ClipboardHistory.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ClipboardImageImporter.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/CommunityWatermarkService.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/CovertTextChannelAnalyzer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/CodeLanguageDetector.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/CodeGuard.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/EvidenceConfidence.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ExternalPixelWatermarkEngine.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ExternalTextWatermarkEngine.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ExtendedContainerInspector.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ExtendedMetadataCleaner.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/FileMetadataCleaner.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/FileProvenanceAnalyzer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/FindingReportFormatter.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/FolderTriageEngine.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/HiddenTextAnalyzer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/InputResultAutomation.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/InvisibleFragmentRevealer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/LocalRewriteEngine.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/LinkSanitizationModels.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/OpaqueIdentifierAnalyzer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/PayloadEquivalenceDetector.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/PDFMetadataSanitizer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/PatternAnalyzer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/PixelLSBForensics.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/PixelSpectralForensics.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ProviderWatermarkRegistry.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/RuleSystem.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/ScamAttemptDetector.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/RewriteIntegrityAnalyzer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/SignalSieveIgnore.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/SignatureHunt.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/TextCleaner.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/TextEncodingDetector.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/URLTrackerCleaner.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/VisualTransfer.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/VaccineEngine.swift" \
    "$PROJECT_ROOT/Sources/SignalSieveCore/WatermarkProbeAnalyzer.swift" \
    "$BUILD_DIR/CSignalSieveZip.o" \
    -emit-module-path "$BUILD_DIR/SignalSieveCore.swiftmodule" \
    -o "$BUILD_DIR/libSignalSieveCore.dylib" \
    -Xlinker -install_name \
    -Xlinker @rpath/libSignalSieveCore.dylib \
    -lz \
    -framework PDFKit

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
    "$PROJECT_ROOT/Sources/SignalSievePixelBaseline/main.swift" \
    -o "$BUILD_DIR/SignalSievePixelBaseline" \
    -Xlinker -rpath \
    -Xlinker @executable_path

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
    "$PROJECT_ROOT/Sources/SignalSievePixelSpectral/main.swift" \
    -o "$BUILD_DIR/SignalSievePixelSpectral" \
    -Xlinker -rpath \
    -Xlinker @executable_path

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
    "$PROJECT_ROOT/Sources/SignalSieve/App/SignalSieveApp.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/App/SignalSieveViewModel.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/App/ContentView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/WindowAppearanceBridge.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/SieveControls.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/SheetScaffold.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/DesignSystem/FindingCopyButton.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/ActiveGuard/ClipboardNoticePanel.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/ActiveGuard/ThreatInsightsView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/FileInspector/FileProvenanceView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Help/GlossaryView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/History/ClipboardHistoryView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Integrations/CommunityEnginesView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Links/LinkCoverageView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Patterns/PatternReportView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Patterns/WatermarkProbeView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Patterns/RewriteIntegrityView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Pixel/PixelWatermarkModuleView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Reveal/RevealView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Reveal/CovertChannelView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Rules/PrivateRulesView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Vaccine/FolderTriageView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Vaccine/SignatureHuntView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Features/Vaccine/VaccineView.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Platform/ApplicationIconController.swift" \
    "$PROJECT_ROOT/Sources/SignalSieve/Platform/ClipboardImagePasteboardReader.swift" \
    -o "$BUILD_DIR/SignalSieve" \
    -Xlinker -rpath \
    -Xlinker @executable_path

echo "SignalSieve built at $BUILD_DIR/SignalSieve"
