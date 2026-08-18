// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import SignalSieveCore

@Test("Maps source-file extensions without overriding content analysis")
func mapsSourceFileExtensions() {
    #expect(CodeLanguageDetector.language(forFileExtension: "swift") == .swift)
    #expect(CodeLanguageDetector.language(forFileExtension: ".py") == .python)
    #expect(CodeLanguageDetector.language(forFileExtension: "unknown") == nil)
}

@Test("Detects distinctive syntax across supported programming languages")
func detectsProgrammingLanguages() {
    let samples: [(CodeLanguage, String)] = [
        (.swift, "import Foundation\nfunc greet(name: String) -> String { return name }") ,
        (.typescript, "interface User { id: number; name: string }\nconst user: User = { id: 1, name: 'A' };") ,
        (.javascript, "const greet = (name) => console.log(name);"),
        (.rust, "fn main() { let mut count = 0; println!(\"{}\", count); }") ,
        (.python, "def greet(name: str) -> str:\n    return name if name is not None else ''"),
        (.c, "#include <stdio.h>\nint main(void) { printf(\"hi\"); return 0; }") ,
        (.cpp, "#include <iostream>\nint main() { std::cout << \"hi\"; }") ,
        (.objectiveC, "#import <Foundation/Foundation.h>\n@interface Greeter : NSObject\n@end"),
        (.go, "package main\nfunc main() { value := 1; fmt.Println(value) }") ,
        (.java, "package demo;\npublic class Main { public static void main(String[] args) { System.out.println(args); } }") ,
        (.kotlin, "data class User(val name: String)\nfun main() { println(User(\"A\")) }") ,
        (.cSharp, "using System;\nnamespace Demo { public class MainClass { void Run() { Console.WriteLine(1); } } }") ,
        (.shell, "#!/usr/bin/env bash\nfor file in *.txt; do echo \"${file}\"; done"),
        (.sql, "SELECT user_id, COUNT(*) FROM events GROUP BY user_id ORDER BY user_id;"),
        (.solidity, "pragma solidity ^0.8.20;\ncontract Vault { mapping(address => uint256) balances; }") ,
        (.move, "module 0x1::vault { public entry fun deposit(account: &signer) { move_to(account, Vault {}); } }") ,
        (.ruby, "def greet\n  puts 'hello'\nend"),
        (.php, "<?php\n$user = 'Ada';\necho $user;"),
        (.dart, "import 'package:flutter/widgets.dart';\nclass App extends StatelessWidget { Widget build(context) => Text('Hi'); }") ,
        (.lua, "local function greet(name)\n  print(name)\nend"),
        (.html, "<!DOCTYPE html><html><body><main>Hello</main></body></html>"),
        (.css, ".card {\n  display: flex;\n  color: blue;\n}"),
        (.json, "{\"name\":\"Signal Sieve\",\"enabled\":true}"),
        (.yaml, "name: Signal Sieve\nenabled: true\nlanguages:\n  - Swift"),
        (.toml, "[package]\nname = \"signal-sieve\"\nversion = \"0.3.0\"")
    ]

    for (expected, source) in samples {
        let detection = CodeLanguageDetector.detect(source)
        #expect(detection.isLikelyCode, "Expected code for \(expected.rawValue)")
        #expect(detection.primary == expected, "Expected \(expected.rawValue), got \(detection.displayName)")
    }
}

@Test("Uses fenced language labels as explicit high-confidence evidence")
func honorsMarkdownLanguageFence() {
    let detection = CodeLanguageDetector.detect("```move\nmodule 0x1::demo {}\n```")

    #expect(detection.primary == .move)
    #expect(detection.confidence == .high)
}

@Test("Leaves short shared syntax language-ambiguous")
func leavesSharedSyntaxAmbiguous() {
    let detection = CodeLanguageDetector.detect("let answer = compute(value);")

    #expect(detection.isLikelyCode)
    #expect(detection.primary == nil)
    #expect(detection.displayName == "Source code")
}

@Test("Does not classify ordinary prose as a programming language")
func rejectsProgrammingLanguageFalsePositive() {
    let detection = CodeLanguageDetector.detect(
        "Let the reader consider this ordinary sentence and return tomorrow for another discussion."
    )

    #expect(!detection.isLikelyCode)
    #expect(detection.primary == nil)
}
