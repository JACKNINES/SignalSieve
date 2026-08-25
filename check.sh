#!/bin/zsh
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

PROJECT_ROOT="${0:A:h}"

"$PROJECT_ROOT/test-local.sh"
"$PROJECT_ROOT/test-swift-testing-local.sh"
"$PROJECT_ROOT/package-app.sh"

if grep -rnE 'try!|fatalError\(|TODO|FIXME' "$PROJECT_ROOT/Sources"; then
    print -u2 "Disallowed source marker found."
    exit 1
else
    SOURCE_SCAN_STATUS=$?
    if (( SOURCE_SCAN_STATUS != 1 )); then
        print -u2 "Unable to scan sources for disallowed markers."
        exit 1
    fi
fi

if ! STANDARD_TEST_COUNT="$(
    awk '/^@Test/ { count += 1 } END { print count + 0 }' \
        "$PROJECT_ROOT/Tests/SignalSieveCoreTests"/*.swift
)"; then
    print -u2 "Unable to count Swift Testing declarations."
    exit 1
fi
if (( STANDARD_TEST_COUNT == 0 )); then
    print -u2 "No Swift Testing declarations were found."
    exit 1
fi
print "Static quality checks passed."
print "Swift Testing declarations: $STANDARD_TEST_COUNT"
