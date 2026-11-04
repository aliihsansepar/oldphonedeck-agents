import Foundation

public struct SourceToggle: Codable, Equatable {
    public var enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public struct AgentConfig: Codable, Equatable {
    public var enabled: Bool
    public var maxRows: Int
    public var refreshSeconds: Int
    public var lookbackHours: Int
    public var redactTitles: Bool
    public var sources: [String: SourceToggle]
    public var excludeProjects: [String]

    public static let `default` = AgentConfig()

    public init(enabled: Bool = true, maxRows: Int = 5, refreshSeconds: Int = 3,
                lookbackHours: Int = 24, redactTitles: Bool = false,
                sources: [String: SourceToggle]? = nil,
                excludeProjects: [String] = []) {
        self.enabled = enabled
        self.maxRows = maxRows
        self.refreshSeconds = refreshSeconds
        self.lookbackHours = lookbackHours
        self.redactTitles = redactTitles
        self.sources = sources ?? Self.defaultSources
        self.excludeProjects = excludeProjects
    }

    private static var defaultSources: [String: SourceToggle] {
        ["claude": SourceToggle(), "codex": SourceToggle(), "opencode": SourceToggle()]
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case maxRows
        case refreshSeconds
        case lookbackHours
        case redactTitles
        case sources
        case excludeProjects
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        maxRows = try container.decodeIfPresent(Int.self, forKey: .maxRows) ?? 5
        refreshSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshSeconds) ?? 3
        lookbackHours = try container.decodeIfPresent(Int.self, forKey: .lookbackHours) ?? 24
        redactTitles = try container.decodeIfPresent(Bool.self, forKey: .redactTitles) ?? false

        var merged = Self.defaultSources
        let decoded = try container.decodeIfPresent([String: SourceToggle].self, forKey: .sources) ?? [:]
        for (key, value) in decoded { merged[key] = value }
        sources = merged

        excludeProjects = try container.decodeIfPresent([String].self, forKey: .excludeProjects) ?? []
    }

    public static func load(from url: URL) -> AgentConfig {
        guard let data = try? Data(contentsOf: url),
              var config = try? JSONDecoder().decode(AgentConfig.self, from: data) else {
            return .default
        }
        config.refreshSeconds = min(10, max(2, config.refreshSeconds))
        config.maxRows = min(10, max(1, config.maxRows))
        return config
    }
}
