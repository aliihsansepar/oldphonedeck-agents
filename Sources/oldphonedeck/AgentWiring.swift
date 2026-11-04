import Foundation
import DeckAgents

func makeAgentSources(config: AgentConfig) -> [AgentSource] {
    guard config.enabled else { return [] }

    let home = URL(fileURLWithPath: NSHomeDirectory())
    let lookback = TimeInterval(config.lookbackHours * 3_600)
    var sources: [AgentSource] = []

    if config.sources["claude"]?.enabled != false {
        sources.append(ClaudeSource(
            projectsDir: home.appendingPathComponent(".claude/projects"),
            lookback: lookback
        ))
    }
    if config.sources["codex"]?.enabled != false {
        sources.append(CodexSource(
            sessionsDir: home.appendingPathComponent(".codex/sessions"),
            lookback: lookback
        ))
    }
    if config.sources["opencode"]?.enabled != false {
        sources.append(OpenCodeSource(
            dbURL: home.appendingPathComponent(".local/share/opencode/opencode.db"),
            lookback: lookback
        ))
    }
    return sources
}

func makeAgentStore(config: AgentConfig) -> AgentStore {
    let scanner = AgentScanner(
        sources: makeAgentSources(config: config),
        maxAgents: 20,
        excludeProjects: config.excludeProjects,
        refreshSeconds: config.refreshSeconds,
        maxRows: config.maxRows
    )
    return AgentStore(scanner: scanner)
}
