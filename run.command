#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -e
cd "${0:A:h}"
if [[ ! -r .build/vendor/qpdf/libqpdf/libqpdf.a \
    || ! -r .build/vendor/prefix/lib/libjpeg.a ]]; then
    ./bootstrap-pdf-tools.sh
fi
./package-app.sh
open "./.build/app/Signal Sieve.app"
