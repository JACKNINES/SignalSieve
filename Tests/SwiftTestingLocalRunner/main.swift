// SPDX-License-Identifier: MPL-2.0
import Testing

@main
enum SignalSieveSwiftTestingLocalRunner {
    static func main() async {
        // SwiftPM generates an equivalent call for `swift test`. This symbol
        // is intentionally internal integration API; compilation must fail if
        // a future toolchain removes or changes it, rather than skipping tests.
        await Testing.__swiftPMEntryPoint() as Never
    }
}
