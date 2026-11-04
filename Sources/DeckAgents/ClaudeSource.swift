import Foundation

public struct ClaudeSource: AgentSource {
    public let provider = "claude"
    public let projectsDir: URL
    public let lookback: TimeInterval

    public init(projectsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects"),
                lookback: TimeInterval = 86_400) {
        self.projectsDir = projectsDir
        self.lookback = lookback
    }

    public func scan(now: Date) -> SourceResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: projectsDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return SourceResult(status: "missing", agents: [])
        }
        guard let enumerator = fileManager.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SourceResult(status: "error", agents: [])
        }

        var agents: [AgentSession] = []
        var attempted = 0
        var failed = 0

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
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
                if let agent = ClaudeParser.parse(lines: lines, sessionID: sessionID,
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

public enum ClaudeParser {
    private enum State {
        case none
        case active
        case turnEnded
    }

    public static func parse(lines: [String], sessionID: String,
                             sourcePath: String, now: Date) -> AgentSession? {
        var cwd: String?
        var foundSessionID: String?
        var aiTitle: String?
        var lastTimestamp: Date?
        var lastState: State = .none
        var lastToolName: String?
        var lastToolFile: String?
        var turnEnded = false

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = object["type"] as? String else { continue }

            if let timestamp = object["timestamp"] as? String,
               let date = ISODate.parse(timestamp) {
                lastTimestamp = date
            }
            if let value = object["sessionId"] as? String { foundSessionID = value }
            if let value = object["cwd"] as? String { cwd = value }

            switch type {
            case "ai-title":
                aiTitle = (object["aiTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            case "last-prompt", "cost-state":
                turnEnded = true

            case "system":
                let subtype = object["subtype"] as? String ?? ""
                if ["turn_duration", "away_summary", "stop_hook_summary"].contains(subtype) {
                    turnEnded = true
                    lastState = .turnEnded
                }

            case "assistant", "user":
                turnEnded = false
                let message = object["message"] as? [String: Any]
                let content = message?["content"] as? [[String: Any]] ?? []
                for part in content {
                    switch part["type"] as? String ?? "" {
                    case "tool_use":
                        lastToolName = part["name"] as? String
                        lastToolFile = (part["input"] as? [String: Any])?["file_path"] as? String
                        lastState = .active
                    case "tool_result":
                        lastState = .active
                    case "text":
                        if let text = part["text"] as? String,
                           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            lastState = .active
                        }
                    case "thinking":
                        lastState = .active
                    default:
                        break
                    }
                }
                if content.isEmpty, type == "assistant" {
                    lastState = .active
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
        } else if turnEnded || lastState == .turnEnded {
            status = .idle
        } else if age <= 120, lastState == .active {
            status = .working
        } else if lastState == .none {
            status = .unknown
        } else {
            status = .idle
        }

        let path = cwd ?? ""
        let project: String
        if let cwd {
            project = ProjectLabel.resolve(directory: cwd, title: aiTitle)
        } else if let aiTitle, !aiTitle.isEmpty {
            project = String(aiTitle.prefix(28))
        } else {
            project = "Claude"
        }

        let detail: String?
        if let name = lastToolName {
            if let file = lastToolFile {
                detail = "\(name) · \(URL(fileURLWithPath: file).lastPathComponent)"
            } else {
                detail = name
            }
        } else {
            detail = nil
        }

        let title = aiTitle.flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
        let id = foundSessionID ?? sessionID
        return AgentSession(
            id: "claude:\(id)", provider: "claude", project: project, path: path,
            title: title, detail: detail, status: status,
            lastActivity: timestamp, sessionID: id, sourcePath: sourcePath
        )
    }
}
