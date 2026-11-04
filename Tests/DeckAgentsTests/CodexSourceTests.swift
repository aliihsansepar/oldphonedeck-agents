import XCTest
@testable import DeckAgents

final class CodexSourceTests: XCTestCase {
    private let now = ISODate.parse("2026-11-04T20:00:12.000Z")!

    private let meta = #"{"timestamp":"2026-11-04T20:00:00.000Z","type":"session_meta","payload":{"id":"c1","cwd":"/Users/ali/projects/mmxss"}}"#
    private let started = #"{"timestamp":"2026-11-04T20:00:02.000Z","type":"event_msg","payload":{"type":"task_started"}}"#
    private let complete = #"{"timestamp":"2026-11-04T20:00:02.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#

    func testTaskStartedIsWorking() {
        let agent = CodexParser.parse(lines: [meta, started], sessionID: "c1",
                                      sourcePath: "/tmp/rollout-c1.jsonl", now: now)
        XCTAssertEqual(agent?.status, .working)
        XCTAssertEqual(agent?.project, "mmxss")
        XCTAssertEqual(agent?.path, "/Users/ali/projects/mmxss")
    }

    func testTaskCompleteIsIdle() {
        let agent = CodexParser.parse(lines: [meta, complete], sessionID: "c1",
                                      sourcePath: "/tmp/rollout-c1.jsonl", now: now)
        XCTAssertEqual(agent?.status, .idle)
    }

    func testIncompleteLastLineIgnored() {
        let lines = [meta, complete, #"{"type":"event_msg","payload":{"type":"task_"#]
        let agent = CodexParser.parse(lines: lines, sessionID: "c1",
                                      sourcePath: "/tmp/rollout-c1.jsonl", now: now)
        XCTAssertEqual(agent?.status, .idle)
    }

    func testSourceReadsRolloutAndMissingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let day = root.appendingPathComponent("2026/11/04")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = day.appendingPathComponent("rollout-c1.jsonl")
        try ([meta, complete].joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        let result = CodexSource(sessionsDir: root, lookback: 86_400).scan(now: now)
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.agents.count, 1)
        XCTAssertEqual(result.agents.first?.status, .idle)

        let missing = CodexSource(sessionsDir: root.appendingPathComponent("nope"), lookback: 86_400).scan(now: now)
        XCTAssertEqual(missing.status, "missing")
        XCTAssertTrue(missing.agents.isEmpty)
    }
}
