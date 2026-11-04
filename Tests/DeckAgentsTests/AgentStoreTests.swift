import XCTest
@testable import DeckAgents

final class AgentStoreTests: XCTestCase {
    private final class FakeSource: AgentSource {
        let provider = "claude"
        var agent: AgentSession

        init(agent: AgentSession) {
            self.agent = agent
        }

        func scan(now: Date) -> SourceResult {
            SourceResult(status: "ok", agents: [agent])
        }
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func agent(id: String, project: String) -> AgentSession {
        AgentSession(
            id: id, provider: "claude", project: project, path: "/tmp/\(project)",
            title: nil, detail: nil, status: .working, lastActivity: now,
            sessionID: id, sourcePath: "/tmp/\(id).jsonl"
        )
    }

    func testRefreshAndPath() {
        let source = FakeSource(agent: agent(id: "claude:s1", project: "mmxss"))
        let store = AgentStore(scanner: AgentScanner(sources: [source]))

        store.refreshNow()
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.agents.count, 1)
        XCTAssertEqual(snapshot.agents.first?.project, "mmxss")
        XCTAssertEqual(store.path(for: "claude:s1"), "/tmp/mmxss")
        XCTAssertNil(store.path(for: "missing"))
    }

    func testRefreshReplacesSnapshot() {
        let source = FakeSource(agent: agent(id: "claude:s1", project: "old"))
        let store = AgentStore(scanner: AgentScanner(sources: [source]))
        store.refreshNow()
        XCTAssertEqual(store.snapshot().agents.first?.project, "old")

        source.agent = agent(id: "claude:s1", project: "new")
        store.refreshNow()
        XCTAssertEqual(store.snapshot().agents.first?.project, "new")
    }

    func testClamping() {
        let low = AgentStore(scanner: AgentScanner(sources: [], refreshSeconds: 1))
        XCTAssertEqual(low.refreshSeconds, 2)

        let high = AgentStore(scanner: AgentScanner(sources: [], refreshSeconds: 99))
        XCTAssertEqual(high.refreshSeconds, 10)
    }

    func testStartStopLeavesValidSnapshot() {
        let source = FakeSource(agent: agent(id: "claude:s1", project: "mmxss"))
        let store = AgentStore(scanner: AgentScanner(sources: [source], refreshSeconds: 2))

        store.start()
        store.stop()
        XCTAssertEqual(store.snapshot().agents.count, 1)
    }
}
