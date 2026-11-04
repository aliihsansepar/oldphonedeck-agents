import Foundation

public struct CodexSource: AgentSource {
    public let provider = "codex"
    public let sessionsDir: URL
    public let lookback: TimeInterval

    public init(sessionsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions"),
                lookback: TimeInterval = 86_400) {
        self.sessionsDir = sessionsDir
        self.lookback = lookback
    }

    public func scan(now: Date) -> SourceResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return SourceResult(status: "missing", agents: [])
        }
        guard let enumerator = fileManager.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SourceResult(status: "error", agents: [])
        }

        var agents: [AgentSession] = []
        var attempted = 0
        var failed = 0

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            if let modified = values?.contentModificationDate,
               modified < now.addingTimeInterval(-lookback) {
                continue
            }

            attempted += 1
            do {
                let lines = try tailLines(of: url)
                let sessionID = url.deletingPathExtension().lastPathComponent
                if let agent = CodexParser.parse(lines: lines, sessionID: sessionID,
                                                 sourcePath: url.path, now: now) {
                    agents.append(agent)
                }
            } catch {
                failed += 1
            }
        }

        let status = (attempted > 0 && failed == attempted) ? "error" : "ok"
        return SourceResult(status: status, agents: agents)
    }

    private func tailLines(of url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let offset = size > 65_536 ? size - 65_536 : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()

        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }
}

public enum CodexParser {
    public static func parse(lines: [String], sessionID: String,
                             sourcePath: String, now: Date) -> AgentSession? {
        var cwd: String?
        var foundSessionID: String?
        var title: String?
        var lastTimestamp: Date?
        var lastLifecycle: String?
        var lastTool: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = object["type"] as? String else { continue }

            if let timestamp = object["timestamp"] as? String,
               let date = ISODate.parse(timestamp) {
                lastTimestamp = date
            }

            switch type {
            case "session_meta":
                let payload = object["payload"] as? [String: Any] ?? [:]
                foundSessionID = payload["id"] as? String ?? payload["session_id"] as? String
                cwd = payload["cwd"] as? String
                title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            case "event_msg":
                let payload = object["payload"] as? [String: Any] ?? [:]
                if let event = payload["type"] as? String,
                   ["task_started", "task_complete", "agent_message", "user_message"].contains(event) {
                    lastLifecycle = event
                }

            case "response_item":
                let payload = object["payload"] as? [String: Any] ?? [:]
                if payload["type"] as? String == "function_call",
                   let name = payload["name"] as? String {
                    lastTool = name
                }

            default:
                break
            }
        }

        guard let timestamp = lastTimestamp else { return nil }

        let age = now.timeIntervalSince(timestamp)
        let status: AgentStatus
        if age > 3_600 {
            status = .stale
        } else if lastLifecycle == "task_complete" {
            status = .idle
        } else if ["task_started", "agent_message", "user_message"].contains(lastLifecycle) {
            status = age <= 120 ? .working : .idle
        } else if lastTool != nil {
            status = age <= 120 ? .working : .idle
        } else {
            status = .unknown
        }

        let project: String
        if let cwd {
            project = ProjectLabel.resolve(directory: cwd, title: title)
        } else if let title, !title.isEmpty {
            project = String(title.prefix(28))
        } else {
            project = "Codex"
        }

        let detail: String?
        if let lastTool {
            detail = lastTool
        } else {
            switch lastLifecycle {
            case "task_started": detail = "çalışıyor"
            case "task_complete": detail = "tamamlandı"
            case "agent_message": detail = "yanıt"
            case "user_message": detail = "istek"
            default: detail = nil
            }
        }

        let id = foundSessionID ?? sessionID
        let cleanTitle = title.flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
        return AgentSession(
            id: "codex:\(id)", provider: "codex", project: project, path: cwd ?? "",
            title: cleanTitle, detail: detail, status: status,
            lastActivity: timestamp, sessionID: id, sourcePath: sourcePath
        )
    }
}
