import Foundation

public struct AgentScanner {
    public let refreshSeconds: Int
    public let maxRows: Int

    private let sources: [AgentSource]
    private let maxAgents: Int
    private let excludeProjects: Set<String>

    public init(sources: [AgentSource], maxAgents: Int = 20,
                excludeProjects: [String] = [], refreshSeconds: Int = 3, maxRows: Int = 5) {
        self.sources = sources
        self.maxAgents = maxAgents
        self.excludeProjects = Set(excludeProjects)
        self.refreshSeconds = min(10, max(2, refreshSeconds))
        self.maxRows = min(10, max(1, maxRows))
    }

    public func scan(now: Date) -> AgentSnapshot {
        var statuses: [String: String] = [:]
        var byID: [String: AgentSession] = [:]

        for source in sources {
            let result = source.scan(now: now)
            statuses[source.provider] = result.status

            for agent in result.agents where !excludeProjects.contains(agent.project) {
                if let existing = byID[agent.id] {
                    if agent.lastActivity > existing.lastActivity {
                        byID[agent.id] = agent
                    }
                } else {
                    byID[agent.id] = agent
                }
            }
        }

        let rank: [AgentStatus: Int] = [
            .working: 0,
            .idle: 1,
            .stale: 2,
            .unknown: 3,
        ]
        let sorted = byID.values.sorted { lhs, rhs in
            let leftRank = rank[lhs.status] ?? 4
            let rightRank = rank[rhs.status] ?? 4
            if leftRank != rightRank { return leftRank < rightRank }
            if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
            return lhs.id < rhs.id
        }

        let capped = Array(sorted.prefix(maxAgents))
        return AgentSnapshot(
            updated: now,
            refreshSeconds: refreshSeconds,
            sources: statuses,
            agents: capped,
            maxRows: maxRows
        )
    }
}
