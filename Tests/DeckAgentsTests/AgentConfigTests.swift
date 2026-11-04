import XCTest
@testable import DeckAgents

final class AgentConfigTests: XCTestCase {
    private func tempFile(_ contents: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("agents.json")
        if let contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    func testMissingFileDefaults() throws {
        let url = try tempFile(nil)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let config = AgentConfig.load(from: url)
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.maxRows, 5)
        XCTAssertEqual(config.refreshSeconds, 3)
        XCTAssertEqual(config.lookbackHours, 24)
        XCTAssertFalse(config.redactTitles)
        XCTAssertEqual(config.excludeProjects, [])
        XCTAssertEqual(config.sources["claude"], SourceToggle())
        XCTAssertEqual(config.sources["codex"], SourceToggle())
        XCTAssertEqual(config.sources["opencode"], SourceToggle())
    }

    func testValidOverrides() throws {
        let url = try tempFile("""
        {
          "refreshSeconds": 9,
          "redactTitles": true,
          "sources": { "codex": { "enabled": false } }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let config = AgentConfig.load(from: url)
        XCTAssertEqual(config.refreshSeconds, 9)
        XCTAssertTrue(config.redactTitles)
        XCTAssertFalse(config.sources["codex"]!.enabled)
        XCTAssertTrue(config.sources["claude"]!.enabled)
        XCTAssertTrue(config.sources["opencode"]!.enabled)
    }

    func testInvalidJSONFallsBackToDefaults() throws {
        let url = try tempFile("not json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        XCTAssertEqual(AgentConfig.load(from: url), .default)
    }

    func testClamping() throws {
        let url = try tempFile(#"{"refreshSeconds": 1, "maxRows": 99}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let config = AgentConfig.load(from: url)
        XCTAssertEqual(config.refreshSeconds, 2)
        XCTAssertEqual(config.maxRows, 10)
    }

    func testUnknownKeysIgnored() throws {
        let url = try tempFile(#"{"refreshSeconds": 4, "futureKey": true}"#)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        XCTAssertEqual(AgentConfig.load(from: url).refreshSeconds, 4)
    }
}
