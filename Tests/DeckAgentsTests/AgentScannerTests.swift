import XCTest
@testable import DeckAgents

final class AgentScannerTests: XCTestCase {
    private struct FakeSource: AgentSource {
        let provider: String
        let status: String
        let agents: [AgentSession]
        func scan(now: Date) -> SourceResult {
            SourceResult(status: status, agents: agents)
        }
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func agent(_ id: String, provider: String, project: String,
                       status: AgentStatus, at date: Date) -> AgentSession {
        AgentSession(
            id: id, provider: provider, project: project, path: "/tmp/\(project)",
            title: nil, detail: nil, status: status, lastActivity: date,
            sessionID: id, sourcePath: "/tmp/\(id).jsonl"
        )
    }

    func testMergeOrderAndSourceStatus() {
        let idle = agent("claude:a", provider: "claude", project: "mmxss", status: .idle, at: now - 60)
        let working = agent("claude:b", provider: "claude", project: "bist", status: .working, at: now - 5)
        let codex = agent("codex:c", provider: "codex", project: "mediapress", status: .working, at: now - 2)

        let scanner = AgentScanner(sources: [
            FakeSource(provider: "claude", status: "ok", agents: [idle, working]),
            FakeSource(provider: "codex", status: "missing", agents: [codex]),
        ])
        let snapshot = scanner.scan(now: now)

        XCTAssertEqual(snapshot.agents.map(\.id), ["codex:c", "claude:b", "claude:a"])
        XCTAssertEqual(snapshot.sources, ["claude": "ok", "codex": "missing"])
        XCTAssertEqual(snapshot.refreshSeconds, 3)
        XCTAssertEqual(snapshot.maxRows, 5)
    }

    func testMaxAgentsAndExcludeProjects() {
        let scratch = agent("claude:s", provider: "claude", project: "scratch", status: .working, at: now - 1)
        let first = agent("claude:1", provider: "claude", project: "one", status: .working, at: now - 1)
        let second = agent("claude:2", provider: "claude", project: "two", status: .working, at: now - 2)

        let scanner = AgentScanner(
            sources: [FakeSource(provider: "claude", status: "ok", agents: [scratch, first, second])],
            maxAgents: 1,
            excludeProjects: ["scratch"]
        )
        let snapshot = scanner.scan(now: now)
        XCTAssertEqual(snapshot.agents.map(\.id), ["claude:1"])
    }

    func testDuplicateIDKeepsLatest() {
        let old = agent("shared", provider: "claude", project: "old", status: .idle, at: now - 100)
        let new = agent("shared", provider: "codex", project: "new", status: .working, at: now - 2)

        let scanner = AgentScanner(sources: [
            FakeSource(provider: "claude", status: "ok", agents: [old]),
            FakeSource(provider: "codex", status: "ok", agents: [new]),
        ])
        let snapshot = scanner.scan(now: now)
        XCTAssertEqual(snapshot.agents.count, 1)
        XCTAssertEqual(snapshot.agents.first?.provider, "codex")
        XCTAssertEqual(snapshot.agents.first?.project, "new")
    }

    func testClamping() {
        let scanner = AgentScanner(sources: [], refreshSeconds: 1, maxRows: 99)
        XCTAssertEqual(scanner.refreshSeconds, 2)
        XCTAssertEqual(scanner.maxRows, 10)
    }
}
