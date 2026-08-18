#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"

"$PROJECT_ROOT/test-local.sh"
"$PROJECT_ROOT/package-app.sh"

if grep -rnE 'try!|fatalError\(|TODO|FIXME' "$PROJECT_ROOT/Sources"; then
    print -u2 "Disallowed source marker found."
    exit 1
fi

STANDARD_TEST_COUNT="$(cat "$PROJECT_ROOT/Tests/SignalSieveCoreTests"/*.swift | grep -c '^@Test' || true)"
print "Static quality checks passed."
print "Swift Testing declarations: $STANDARD_TEST_COUNT"
