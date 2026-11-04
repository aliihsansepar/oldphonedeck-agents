import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct OpenCodeSource: AgentSource {
    public let provider = "opencode"
    public let dbURL: URL
    public let lookback: TimeInterval

    public init(dbURL: URL = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent(".local/share/opencode/opencode.db"),
                lookback: TimeInterval = 86_400) {
        self.dbURL = dbURL
        self.lookback = lookback
    }

    public func scan(now: Date) -> SourceResult {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return SourceResult(status: "missing", agents: [])
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db else {
            if db != nil { sqlite3_close(db) }
            return SourceResult(status: "error", agents: [])
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        if tableExists(db, "session_v2") && tableExists(db, "session_message") {
            return scanV2(db, now: now)
        }
        if tableExists(db, "session") && tableExists(db, "message") {
            return scanLegacy(db, now: now)
        }
        return SourceResult(status: "error", agents: [])
    }

    private func scanV2(_ db: OpaquePointer, now: Date) -> SourceResult {
        let sql = """
        select s.id, s.parent_id, s.directory, s.title,
               s.time_updated, s.time_archived, s.time_busy, s.time_idle,
               p.name as project_name,
               (select sm.data from session_message sm
                where sm.session_id = s.id and sm.type = 'assistant'
                order by sm.time_created desc limit 1) as last_data
        from session_v2 s
        left join project p on p.id = s.project_id
        where (s.parent_id is null or s.parent_id = '')
          and s.time_archived is null
        order by s.time_updated desc
        limit 20;
        """
        guard let records = rows(db, sql) else {
            return SourceResult(status: "error", agents: [])
        }

        var agents: [AgentSession] = []
        for record in records {
            guard let id = record["id"] as? String,
                  let updatedMs = int(record, "time_updated") else { continue }
            let updated = Date(timeIntervalSince1970: Double(updatedMs) / 1_000)
            if updated < now.addingTimeInterval(-lookback) { continue }

            let directory = record["directory"] as? String ?? ""
            let title = (record["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let projectName = (record["project_name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let project: String
            if let projectName, !projectName.isEmpty {
                project = projectName
            } else {
                project = ProjectLabel.resolve(directory: directory, title: title)
            }

            let busy = int(record, "time_busy")
            let idle = int(record, "time_idle")
            let status: AgentStatus
            if now.timeIntervalSince(updated) > 3_600 {
                status = .stale
            } else if idle == nil {
                status = .working
            } else if let busy, let idle, busy > idle {
                status = .working
            } else {
                status = .idle
            }

            var detail: String?
            if let data = record["last_data"] as? String,
               let object = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any] {
                detail = (object["agent"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let cleanTitle = title.flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
            agents.append(AgentSession(
                id: "opencode:\(id)", provider: "opencode", project: project,
                path: directory, title: cleanTitle, detail: detail, status: status,
                lastActivity: updated, sessionID: id, sourcePath: dbURL.path
            ))
        }
        return SourceResult(status: "ok", agents: agents)
    }

    private func scanLegacy(_ db: OpaquePointer, now: Date) -> SourceResult {
        let sql = """
        select s.id, s.directory, s.title, s.time_updated, s.time_archived,
               (select m.data from message m
                where m.session_id = s.id
                order by m.time_created desc limit 1) as last_data
        from session s
        where s.time_archived is null
        order by s.time_updated desc
        limit 20;
        """
        guard let records = rows(db, sql) else {
            return SourceResult(status: "error", agents: [])
        }

        var agents: [AgentSession] = []
        for record in records {
            guard let id = record["id"] as? String,
                  let updatedMs = int(record, "time_updated") else { continue }
            let updated = Date(timeIntervalSince1970: Double(updatedMs) / 1_000)
            if updated < now.addingTimeInterval(-lookback) { continue }

            let directory = record["directory"] as? String ?? ""
            let title = (record["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let project = ProjectLabel.resolve(directory: directory, title: title)

            var detail: String?
            var status: AgentStatus = .idle
            if let data = record["last_data"] as? String,
               let object = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any] {
                if let finish = object["finish"] as? String {
                    detail = finish
                } else if let agent = object["agent"] as? String {
                    detail = agent
                }
                if object["role"] as? String == "assistant" {
                    let time = object["time"] as? [String: Any]
                    let completed = time?["completed"] != nil
                    status = (!completed && now.timeIntervalSince(updated) <= 120) ? .working : .idle
                }
            }
            if now.timeIntervalSince(updated) > 3_600 { status = .stale }

            let cleanTitle = title.flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
            agents.append(AgentSession(
                id: "opencode:\(id)", provider: "opencode", project: project,
                path: directory, title: cleanTitle, detail: detail, status: status,
                lastActivity: updated, sessionID: id, sourcePath: dbURL.path
            ))
        }
        return SourceResult(status: "ok", agents: agents)
    }

    private func tableExists(_ db: OpaquePointer, _ name: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "select 1 from sqlite_master where type = 'table' and name = ?1 limit 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func rows(_ db: OpaquePointer, _ sql: String) -> [[String: Any]]? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        var result: [[String: Any]] = []
        while true {
            let rc = sqlite3_step(statement)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { return nil }

            var row: [String: Any] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let key = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    row[key] = Int(sqlite3_column_int64(statement, column))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, column) {
                        let bytes = Int(sqlite3_column_bytes(statement, column))
                        row[key] = String(decoding: UnsafeBufferPointer(start: text, count: bytes), as: UTF8.self)
                    } else {
                        row[key] = NSNull()
                    }
                default:
                    row[key] = NSNull()
                }
            }
            result.append(row)
        }
        return result
    }

    private func int(_ row: [String: Any], _ key: String) -> Int? {
        if let value = row[key] as? Int { return value }
        if let value = row[key] as? Int64 { return Int(value) }
        return nil
    }
}
