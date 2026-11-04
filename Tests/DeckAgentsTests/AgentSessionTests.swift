import XCTest
@testable import DeckAgents

final class AgentSessionTests: XCTestCase {
    func testJSONIncludesAgeAndRedaction() {
        let now = Date(timeIntervalSince1970: 1_000)
        let agent = AgentSession(
            id: "claude:s1", provider: "claude", project: "mmxss",
            path: "/tmp/mmxss", title: "Kod düzenleme", detail: "Edit · main.swift",
            status: .working, lastActivity: Date(timeIntervalSince1970: 988),
            sessionID: "s1", sourcePath: "/tmp/s1.jsonl"
        )

        let json = agent.jsonObject(now: now)
        XCTAssertEqual(json["id"] as? String, "claude:s1")
        XCTAssertEqual(json["status"] as? String, "working")
        XCTAssertEqual(json["lastActivity"] as? Int, 988)
        XCTAssertEqual(json["ageSeconds"] as? Int, 12)
        XCTAssertEqual(json["sessionId"] as? String, "s1")

        let redacted = agent.jsonObject(now: now, redactTitles: true)
        XCTAssertNil(redacted["title"])
        XCTAssertNil(redacted["detail"])
    }

    func testSnapshotJSONShape() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = AgentSnapshot(
            updated: now, refreshSeconds: 3,
            sources: ["claude": "ok", "codex": "missing"],
            agents: []
        )
        let json = snapshot.jsonObject(now: now)
        XCTAssertEqual(json["refreshSeconds"] as? Int, 3)
        XCTAssertEqual(json["maxRows"] as? Int, 5)
        XCTAssertEqual((json["sources"] as? [String: String])?["codex"], "missing")
        XCTAssertEqual((json["agents"] as? [Any])?.count, 0)
        XCTAssertEqual(json["updated"] as? Int, 1_000)
    }
}
