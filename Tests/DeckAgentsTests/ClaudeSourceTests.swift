import XCTest
@testable import DeckAgents

final class ClaudeSourceTests: XCTestCase {
    private let now = ISODate.parse("2026-11-04T20:00:12.000Z")!

    private let workingLines = [
        #"{"type":"assistant","timestamp":"2026-11-04T20:00:00.000Z","sessionId":"s1","cwd":"/Users/ali/projects/mmxss","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/ali/projects/mmxss/main.swift"}}]}}"#,
        #"{"type":"ai-title","aiTitle":"Kod düzenleme","sessionId":"s1"}"#,
    ]

    private let idleLines = [
        #"{"type":"assistant","timestamp":"2026-11-04T19:59:00.000Z","sessionId":"s2","cwd":"/Users/ali/projects/mmxss","message":{"role":"assistant","content":[{"type":"text","text":"Bitti"}]}}"#,
        #"{"type":"system","subtype":"turn_duration","timestamp":"2026-11-04T19:59:01.000Z","sessionId":"s2","cwd":"/Users/ali/projects/mmxss"}"#,
        #"{"type":"last-prompt","lastPrompt":"gizli prompt","sessionId":"s2"}"#,
    ]

    func testWorkingToolUse() {
        let agent = ClaudeParser.parse(lines: workingLines, sessionID: "s1",
                                      sourcePath: "/tmp/s1.jsonl", now: now)
        XCTAssertEqual(agent?.status, .working)
        XCTAssertEqual(agent?.project, "mmxss")
        XCTAssertEqual(agent?.title, "Kod düzenleme")
        XCTAssertEqual(agent?.detail, "Edit · main.swift")
        XCTAssertEqual(agent?.path, "/Users/ali/projects/mmxss")
    }

    func testTurnEndedIsIdle() {
        let agent = ClaudeParser.parse(lines: idleLines, sessionID: "s2",
                                      sourcePath: "/tmp/s2.jsonl", now: now)
        XCTAssertEqual(agent?.status, .idle)
        XCTAssertNil(agent?.title)
    }

    func testIncompleteLastLineIgnored() {
        let lines = workingLines + [#"{"type":"assistant","timestamp":"2026-11-04T20:00:"#]
        let agent = ClaudeParser.parse(lines: lines, sessionID: "s1",
                                      sourcePath: "/tmp/s1.jsonl", now: now)
        XCTAssertEqual(agent?.status, .working)
    }

    func testSourceReadsTailAndMissingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("proj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = project.appendingPathComponent("s1.jsonl")
        let contents = workingLines.joined(separator: "\n") + "\n" + #"{"type":"assistant","timestamp":"2026-11-04T20:00:"# + "\n"
        try contents.write(to: file, atomically: true, encoding: .utf8)

        let result = ClaudeSource(projectsDir: root, lookback: 86_400).scan(now: now)
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.agents.count, 1)
        XCTAssertEqual(result.agents.first?.status, .working)

        let missing = ClaudeSource(projectsDir: root.appendingPathComponent("nope"), lookback: 86_400).scan(now: now)
        XCTAssertEqual(missing.status, "missing")
        XCTAssertTrue(missing.agents.isEmpty)
    }
}
