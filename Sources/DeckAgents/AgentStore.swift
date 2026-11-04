import Foundation

public final class AgentStore {
    public let refreshSeconds: Int

    private let scanner: AgentScanner
    private let queue = DispatchQueue(label: "oldphonedeck.agents")
    private let lock = NSLock()
    private var current: AgentSnapshot
    private var timer: DispatchSourceTimer?

    public init(scanner: AgentScanner) {
        self.scanner = scanner
        self.refreshSeconds = min(10, max(2, scanner.refreshSeconds))
        self.current = AgentSnapshot(
            updated: Date(),
            refreshSeconds: self.refreshSeconds,
            sources: [:],
            agents: [],
            maxRows: scanner.maxRows
        )
    }

    deinit {
        timer?.cancel()
    }

    public func start() {
        guard timer == nil else { return }
        refreshNow()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .seconds(refreshSeconds),
            repeating: .seconds(refreshSeconds),
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            self?.refreshNow()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func refreshNow() {
        let snapshot = scanner.scan(now: Date())
        lock.lock()
        current = snapshot
        lock.unlock()
    }

    public func snapshot() -> AgentSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func path(for id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return current.agents.first { $0.id == id }?.path
    }
}
