import Foundation

public enum AgentStatus: String, Codable, Equatable {
    case working
    case idle
    case stale
    case unknown
}

public struct AgentSession: Equatable {
    public let id: String
    public let provider: String
    public let project: String
    public let path: String
    public let title: String?
    public let detail: String?
    public let status: AgentStatus
    public let lastActivity: Date
    public let sessionID: String
    public let sourcePath: String

    public init(id: String, provider: String, project: String, path: String,
                title: String?, detail: String?, status: AgentStatus,
                lastActivity: Date, sessionID: String, sourcePath: String) {
        self.id = id
        self.provider = provider
        self.project = project
        self.path = path
        self.title = title
        self.detail = detail
        self.status = status
        self.lastActivity = lastActivity
        self.sessionID = sessionID
        self.sourcePath = sourcePath
    }

    public func jsonObject(now: Date, redactTitles: Bool = false) -> [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "provider": provider,
            "project": project,
            "path": path,
            "status": status.rawValue,
            "lastActivity": Int(lastActivity.timeIntervalSince1970),
            "ageSeconds": max(0, Int(now.timeIntervalSince(lastActivity))),
            "sessionId": sessionID,
            "sourcePath": sourcePath,
        ]
        if !redactTitles {
            if let title { object["title"] = title }
            if let detail { object["detail"] = detail }
        }
        return object
    }
}

public struct SourceResult {
    public let status: String
    public let agents: [AgentSession]

    public init(status: String, agents: [AgentSession]) {
        self.status = status
        self.agents = agents
    }
}

public protocol AgentSource {
    var provider: String { get }
    func scan(now: Date) -> SourceResult
}

public struct AgentSnapshot {
    public let updated: Date
    public let refreshSeconds: Int
    public let maxRows: Int
    public let sources: [String: String]
    public let agents: [AgentSession]

    public init(updated: Date, refreshSeconds: Int, sources: [String: String],
                agents: [AgentSession], maxRows: Int = 5) {
        self.updated = updated
        self.refreshSeconds = refreshSeconds
        self.maxRows = maxRows
        self.sources = sources
        self.agents = agents
    }

    public func jsonObject(now: Date, redactTitles: Bool = false) -> [String: Any] {
        [
            "updated": Int(updated.timeIntervalSince1970),
            "refreshSeconds": refreshSeconds,
            "maxRows": maxRows,
            "sources": sources,
            "agents": agents.map { $0.jsonObject(now: now, redactTitles: redactTitles) },
        ]
    }
}
