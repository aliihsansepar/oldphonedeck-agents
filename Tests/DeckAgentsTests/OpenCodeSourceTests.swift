import XCTest
import SQLite3
@testable import DeckAgents

final class OpenCodeSourceTests: XCTestCase {
    private final class TestDB {
        let url: URL
        private var db: OpaquePointer?

        init() {
            url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
            precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        }

        func exec(_ sql: String) {
            var error: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &error)
            if rc != SQLITE_OK {
                XCTFail(error.map { String(cString: $0) } ?? "sqlite error \(rc)")
            }
            sqlite3_free(error)
        }

        func cleanup() {
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
            try? FileManager.default.removeItem(at: url)
        }

        deinit { cleanup() }
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var nowMs: Int { Int(now.timeIntervalSince1970 * 1_000) }

    func testV2WorkingSessionExcludesChildren() {
        let db = TestDB()
        defer { db.cleanup() }

        db.exec("""
        create table project (id text primary key, name text, worktree text);
        create table session_v2 (
          id text primary key, project_id text, parent_id text, directory text, title text,
          time_created integer, time_updated integer, time_archived integer,
          time_busy integer, time_idle integer
        );
        create table session_message (
          id text primary key, session_id text, type text, seq integer,
          time_created integer, time_updated integer, data text
        );
        insert into project values ('p1', 'kresim', '/Users/ali/projects/kresim');
        insert into session_v2 values ('ses_root', 'p1', null, '/Users/ali/projects/kresim',
          'Dosya inceleme', \(nowMs - 60_000), \(nowMs - 10_000), null,
          \(nowMs - 5_000), \(nowMs - 20_000));
        insert into session_v2 values ('ses_child', 'p1', 'ses_root', '/Users/ali/projects/kresim',
          'Alt görev', \(nowMs - 60_000), \(nowMs - 10_000), null,
          \(nowMs - 5_000), \(nowMs - 20_000));
        insert into session_message values ('m1', 'ses_root', 'assistant', 1,
          \(nowMs - 8_000), \(nowMs - 8_000), '{"agent":"build","time":{"created":\(nowMs - 8_000)}}');
        """)

        let result = OpenCodeSource(dbURL: db.url, lookback: 86_400).scan(now: now)
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.agents.count, 1)
        XCTAssertEqual(result.agents.first?.id, "opencode:ses_root")
        XCTAssertEqual(result.agents.first?.project, "kresim")
        XCTAssertEqual(result.agents.first?.status, .working)
        XCTAssertEqual(result.agents.first?.detail, "build")
    }

    func testLegacyIdleSession() {
        let db = TestDB()
        defer { db.cleanup() }

        db.exec("""
        create table session (
          id text primary key, directory text, title text,
          time_created integer, time_updated integer, time_archived integer
        );
        create table message (
          id text primary key, session_id text,
          time_created integer, time_updated integer, data text
        );
        insert into session values ('ses_legacy', '/Users/ali/projects/mmxss', 'Eski oturum',
          \(nowMs - 60_000), \(nowMs - 10_000), null);
        insert into message values ('m1', 'ses_legacy', \(nowMs - 9_000), \(nowMs - 9_000),
          '{"role":"assistant","time":{"created":\(nowMs - 9_000),"completed":\(nowMs - 8_000)},"finish":"stop"}');
        """)

        let result = OpenCodeSource(dbURL: db.url, lookback: 86_400).scan(now: now)
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.agents.count, 1)
        XCTAssertEqual(result.agents.first?.id, "opencode:ses_legacy")
        XCTAssertEqual(result.agents.first?.project, "mmxss")
        XCTAssertEqual(result.agents.first?.status, .idle)
    }

    func testMissingDatabase() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        let result = OpenCodeSource(dbURL: url, lookback: 86_400).scan(now: now)
        XCTAssertEqual(result.status, "missing")
        XCTAssertTrue(result.agents.isEmpty)
    }

    func testUnknownSchemaIsError() {
        let db = TestDB()
        defer { db.cleanup() }
        db.exec("create table something (id text);")

        let result = OpenCodeSource(dbURL: db.url, lookback: 86_400).scan(now: now)
        XCTAssertEqual(result.status, "error")
        XCTAssertTrue(result.agents.isEmpty)
    }

    func testCorruptDatabaseIsError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        defer { try? FileManager.default.removeItem(at: url) }
        try "not a sqlite database".write(to: url, atomically: true, encoding: .utf8)

        let result = OpenCodeSource(dbURL: url, lookback: 86_400).scan(now: now)
        XCTAssertEqual(result.status, "error")
        XCTAssertTrue(result.agents.isEmpty)
    }
}
