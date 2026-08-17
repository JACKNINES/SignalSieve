#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"

"$PROJECT_ROOT/test-local.sh"
"$PROJECT_ROOT/package-app.sh"

if rg --line-number 'try!|fatalError\(|TODO|FIXME' "$PROJECT_ROOT/Sources"; then
    print -u2 "Disallowed source marker found."
    exit 1
fi

STANDARD_TEST_COUNT="$(rg --count '^@Test' "$PROJECT_ROOT/Tests/SignalSieveCoreTests"/*.swift | awk -F: '{ total += $2 } END { print total + 0 }')"
print "Static quality checks passed."
print "Swift Testing declarations: $STANDARD_TEST_COUNT"
