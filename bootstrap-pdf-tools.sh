#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"
VENDOR_ROOT="$PROJECT_ROOT/.build/vendor"
SOURCE_ROOT="$VENDOR_ROOT/src"
PREFIX="$VENDOR_ROOT/prefix"
JPEG_SOURCE="$SOURCE_ROOT/libjpeg-turbo"
QPDF_SOURCE="$SOURCE_ROOT/qpdf"
JPEG_BUILD="$VENDOR_ROOT/libjpeg"
QPDF_BUILD="$VENDOR_ROOT/qpdf"
JPEG_COMMIT="c85e6b905bf237038faa936dab160ebfc5da0344"
QPDF_COMMIT="babad179ce5db9a21635c8d1ac17baa59637eada"
TARGET_ARCH="$(uname -m)"

for command_name in git cmake; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        print -u2 "Missing build dependency: $command_name"
        exit 1
    fi
done

mkdir -p "$SOURCE_ROOT" "$PREFIX"

if [[ ! -d "$JPEG_SOURCE/.git" ]]; then
    git clone --filter=blob:none --no-checkout \
        https://github.com/libjpeg-turbo/libjpeg-turbo.git "$JPEG_SOURCE"
    git -C "$JPEG_SOURCE" fetch --depth 1 origin "$JPEG_COMMIT"
    git -C "$JPEG_SOURCE" checkout --detach "$JPEG_COMMIT"
fi
if [[ "$(git -C "$JPEG_SOURCE" rev-parse HEAD)" != "$JPEG_COMMIT" ]]; then
    print -u2 "Unexpected libjpeg-turbo source revision."
    exit 1
fi

if [[ ! -d "$QPDF_SOURCE/.git" ]]; then
    git clone --filter=blob:none --no-checkout https://github.com/qpdf/qpdf.git "$QPDF_SOURCE"
    git -C "$QPDF_SOURCE" fetch --depth 1 origin "$QPDF_COMMIT"
    git -C "$QPDF_SOURCE" checkout --detach "$QPDF_COMMIT"
fi
if [[ "$(git -C "$QPDF_SOURCE" rev-parse HEAD)" != "$QPDF_COMMIT" ]]; then
    print -u2 "Unexpected qpdf source revision."
    exit 1
fi

cmake \
    -S "$JPEG_SOURCE" \
    -B "$JPEG_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DENABLE_SHARED=OFF \
    -DENABLE_STATIC=ON \
    -DWITH_TURBOJPEG=OFF \
    -DREQUIRE_SIMD=OFF
cmake --build "$JPEG_BUILD" --parallel 4 --target install

cmake \
    -S "$QPDF_SOURCE" \
    -B "$QPDF_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DBUILD_DOC=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DUSE_IMPLICIT_CRYPTO=OFF \
    -DREQUIRE_CRYPTO_NATIVE=ON
cmake --build "$QPDF_BUILD" --parallel 4 --target libqpdf

print "Pinned PDF dependencies built at $VENDOR_ROOT"
