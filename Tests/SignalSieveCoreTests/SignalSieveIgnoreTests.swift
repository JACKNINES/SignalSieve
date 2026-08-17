// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import SignalSieveCore

@Test("Matches root, directory, recursive, and filename ignore patterns")
func matchesSignalSieveIgnorePatterns() {
    let rules = SignalSieveIgnore(patterns: [
        "# test fixtures",
        "/fixtures/",
        "*.generated.py",
        "snapshots/**",
        "secret?.txt"
    ])

    #expect(rules.ignores("fixtures", isDirectory: true))
    #expect(!rules.ignores("nested/fixtures", isDirectory: true))
    #expect(rules.ignores("src/model.generated.py", isDirectory: false))
    #expect(rules.ignores("snapshots/a/b.txt", isDirectory: false))
    #expect(rules.ignores("private/secret1.txt", isDirectory: false))
    #expect(!rules.ignores("src/model.py", isDirectory: false))
}
