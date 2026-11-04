# OldPhoneDeck Agent Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live, read-only agent panel — Claude Code, Codex, OpenCode — beside the existing 8-key deck on an iPhone 8 Plus, served from the Mac over Wi-Fi.

**Architecture:** Extract agent parsing/merging into a new `DeckAgents` SwiftPM library with one adapter per provider and a cached `AgentStore`. The existing executable serves `GET /agents` and `POST /focus`; the existing ES5 `index.html` gains a right-hand agent column in wide landscape and a compact fallback in portrait.

**Tech Stack:** Swift 6.2 / SwiftPM, Foundation, Network.framework (existing), system `libsqlite3`, ES5 HTML/CSS/JS (no build step).

**Spec:** `docs/superpowers/specs/2026-11-04-oldphonedeck-agent-panel-design.md`

## Global Constraints

- macOS 14+; user machine is macOS 27 with Swift 6.2.4.
- Target phone: iPhone 8 Plus, iOS 16.7.x, landscape 736×414 pt; PWA in Safari.
- Data path is Wi-Fi; cable is charging only. Do not add USB tethering or HTTPS requirements.
- No new runtime services or third-party Swift packages. Only system `libsqlite3`.
- Every API request requires the existing `?k=<token>`; no port-forward, no cloud.
- Agent panel: max 5 rows, 24-hour lookback, 3-second refresh, read-only in v1.
- Read at most the last 64 KB of each JSONL file; never parse a whole transcript.
- New UI JavaScript stays ES5 (`var`, `function`, `XMLHttpRequest`); no `fetch`, `let`, arrow functions, or template literals.
- Keep existing deck behavior: 7 app keys + Take note, long-press app picker, now playing, launcher.json.
- Ports stay 8045 (HTTP), 8047 (HTTPS), 8048 (WSS). Do not break the optional Phone tab code.
- One commit per task; commit messages use `feat:`, `test:`, `docs:`, or `fix:`.

## Review Focus

These are the failure modes a real user will hit that the spec implies but no single happy-path test covers. Each line gets a test in the task that owns the code.

1. **Half-written or rotated JSONL:** a transcript ending in a partial line, or a file larger than 64 KB, must not crash the scanner or report a false `working`.
2. **OpenCode DB missing, locked, legacy, or v2:** `/agents` must still return the other providers; a schema problem becomes `sources.opencode = "missing"|"error"`, never a 500 or an empty whole response.
3. **Child/subagent sessions:** Claude `isSidechain` and OpenCode `parent_id` rows must not fill the five visible rows or inflate the working count.
4. **Workspace-root cwd:** sessions whose `cwd` is `/Users/<user>/projects` must still get distinct, useful labels instead of every row saying “projects”.
5. **Phone reconnect / stale data:** if the server stops or the phone drops Wi-Fi, the panel must visibly age out and mark itself offline, not keep showing a green “working” row forever.

---

### Task 1: DeckAgents library, model, and project labels

**Files:**
- Modify: `Package.swift`
- Create: `Sources/DeckAgents/AgentSession.swift`
- Create: `Sources/DeckAgents/ProjectLabel.swift`
- Create: `Sources/DeckAgents/ISODate.swift`
- Test: `Tests/DeckAgentsTests/AgentSessionTests.swift`
- Test: `Tests/DeckAgentsTests/ProjectLabelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```swift
  public enum AgentStatus: String, Codable, Equatable { case working, idle, stale, unknown }

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
                  lastActivity: Date, sessionID: String, sourcePath: String)
      public func jsonObject(now: Date, redactTitles: Bool = false) -> [String: Any]
  }

  public struct SourceResult {
      public let status: String          // "ok" | "missing" | "error"
      public let agents: [AgentSession]
      public init(status: String, agents: [AgentSession])
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
                  agents: [AgentSession], maxRows: Int = 5)
      public func jsonObject(now: Date, redactTitles: Bool = false) -> [String: Any]
  }

  public enum ProjectLabel {
      public static func resolve(directory: String, title: String?,
                                 home: String = NSHomeDirectory(),
                                 fileManager: FileManager = .default) -> String
  }

  public enum ISODate {
      public static func parse(_ value: String) -> Date?
  }
  ```

- [ ] **Step 1: Add the library and test targets**

Modify `Package.swift` to add:

```swift
.target(
    name: "DeckAgents",
    path: "Sources/DeckAgents",
    linkerSettings: [.linkedLibrary("sqlite3")]
),
```

Make `oldphonedeck` depend on `DeckAgents`:

```swift
.executableTarget(
    name: "oldphonedeck",
    dependencies: ["DeckAgents"],
    path: "Sources/oldphonedeck",
    resources: [.copy("web")],
    linkerSettings: [.linkedFramework("AppKit")]
),
```

Add a test target:

```swift
.testTarget(
    name: "DeckAgentsTests",
    dependencies: ["DeckAgents"],
    path: "Tests/DeckAgentsTests",
    linkerSettings: [.linkedLibrary("sqlite3")]
),
```

- [ ] **Step 2: Write the failing model tests**

Create `Tests/DeckAgentsTests/AgentSessionTests.swift`:

```swift
import XCTest
@testable import DeckAgents

final class AgentSessionTests: XCTestCase {
    func testJSONIncludesAgeAndRedaction() {
        let now = Date(timeIntervalSince1970: 1_000)
        let agent = AgentSession(
            id: "claude:s1", provider: "claude", project: "mmxss",
            path: "/tmp/mmxss", title: "Kod düzenleme", detail: "Edit · main.swift",
            status: .working, lastActivity: Date(timeIntervalSince1970: 988),
            sessionID: "s1", sourcePath: "/tmp/s1.jsonl"
        )

        let json = agent.jsonObject(now: now)
        XCTAssertEqual(json["id"] as? String, "claude:s1")
        XCTAssertEqual(json["status"] as? String, "working")
        XCTAssertEqual(json["lastActivity"] as? Int, 988)
        XCTAssertEqual(json["ageSeconds"] as? Int, 12)
        XCTAssertEqual(json["sessionId"] as? String, "s1")

        let redacted = agent.jsonObject(now: now, redactTitles: true)
        XCTAssertNil(redacted["title"])
        XCTAssertNil(redacted["detail"])
    }

    func testSnapshotJSONShape() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = AgentSnapshot(
            updated: now, refreshSeconds: 3,
            sources: ["claude": "ok", "codex": "missing"],
            agents: []
        )
        let json = snapshot.jsonObject(now: now)
        XCTAssertEqual(json["refreshSeconds"] as? Int, 3)
        XCTAssertEqual(json["maxRows"] as? Int, 5)
        XCTAssertEqual((json["sources"] as? [String: String])?["codex"], "missing")
        XCTAssertEqual((json["agents"] as? [Any])?.count, 0)
        XCTAssertEqual(json["updated"] as? Int, 1_000)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter AgentSessionTests`
Expected: compile error — `DeckAgents` / `AgentSession` not found.

- [ ] **Step 4: Implement the model**

Create `Sources/DeckAgents/AgentSession.swift` with the public types above. JSON keys are exactly:
`id`, `provider`, `project`, `path`, `title` (omitted when nil), `detail` (omitted when nil), `status`, `lastActivity` (epoch seconds, `Int`), `ageSeconds` (`max(0, Int(now.timeIntervalSince(lastActivity)))`), `sessionId`, `sourcePath`.
`redactTitles: true` omits both `title` and `detail`.
`AgentSnapshot.jsonObject` emits `updated` (epoch seconds), `refreshSeconds`, `maxRows`, `sources`, `agents`; forward `redactTitles`.

- [ ] **Step 5: Write the failing project-label tests**

Create `Tests/DeckAgentsTests/ProjectLabelTests.swift`:

```swift
import XCTest
@testable import DeckAgents

final class ProjectLabelTests: XCTestCase {
    func testNormalDirectoryUsesBasename() {
        XCTAssertEqual(ProjectLabel.resolve(directory: "/Users/ali/projects/mmxss", title: "x"), "mmxss")
    }

    func testWorkspaceRootUsesSessionTitle() {
        let home = "/Users/ali"
        XCTAssertEqual(
            ProjectLabel.resolve(directory: "/Users/ali/projects", title: "iPhone deck çalışması", home: home),
            "iPhone deck çalışması"
        )
    }

    func testWorkspaceRootWithoutTitleFallsBackToBasename() {
        XCTAssertEqual(ProjectLabel.resolve(directory: "/Users/ali/projects", title: nil, home: "/Users/ali"), "projects")
    }

    func testGitRootWinsOverSubdirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repo = root.appendingPathComponent("my-repo")
        let sub = repo.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(ProjectLabel.resolve(directory: sub.path, title: "ignored"), "my-repo")
    }
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `swift test --filter ProjectLabelTests`
Expected: compile error — `ProjectLabel` not found.

- [ ] **Step 7: Implement `ProjectLabel` and `ISODate`**

`ProjectLabel.resolve`:
1. Walk up from `directory` to `/`, returning the first ancestor containing a `.git` entry; return that ancestor's `lastPathComponent`.
2. If no git root: if `directory == home` or the basename is in `["projects", "Desktop", "Documents", "Downloads"]`, return `title` trimmed to 28 characters if non-empty, else the basename.
3. Otherwise return the basename.

`ISODate.parse` uses `ISO8601DateFormatter` with `[.withInternetDateTime, .withFractionalSeconds]`, then falls back to `[.withInternetDateTime]`.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `swift test --filter 'AgentSessionTests|ProjectLabelTests'`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/DeckAgents Tests/DeckAgentsTests
git commit -m "feat: add DeckAgents model and project labels"
```

---

### Task 2: Claude Code source

**Files:**
- Create: `Sources/DeckAgents/ClaudeSource.swift`
- Test: `Tests/DeckAgentsTests/ClaudeSourceTests.swift`

**Interfaces:**
- Consumes: `AgentSession`, `AgentSource`, `SourceResult`, `ProjectLabel`, `ISODate` (Task 1).
- Produces:
  ```swift
  public struct ClaudeSource: AgentSource {
      public let provider: String   // "claude"
      public let projectsDir: URL
      public let lookback: TimeInterval
      public init(projectsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects"),
                  lookback: TimeInterval = 86_400)
      public func scan(now: Date) -> SourceResult
  }

  public enum ClaudeParser {
      public static func parse(lines: [String], sessionID: String,
                               sourcePath: String, now: Date) -> AgentSession?
  }
  ```

- [ ] **Step 1: Write the failing parser tests**

Create `Tests/DeckAgentsTests/ClaudeSourceTests.swift` with three tests. Use fixed `now = ISODate.parse("2026-11-04T20:00:12.000Z")!`.

Working fixture (last stateful line is a tool call, 12 s old):

```json
{"type":"assistant","timestamp":"2026-11-04T20:00:00.000Z","sessionId":"s1","cwd":"/Users/ali/projects/mmxss","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/ali/projects/mmxss/main.swift"}}]}}
{"type":"ai-title","aiTitle":"Kod düzenleme","sessionId":"s1"}
```

Assert: `status == .working`, `project == "mmxss"`, `title == "Kod düzenleme"`, `detail == "Edit · main.swift"`.

Idle fixture (turn ended):

```json
{"type":"assistant","timestamp":"2026-11-04T19:59:00.000Z","sessionId":"s2","cwd":"/Users/ali/projects/mmxss","message":{"role":"assistant","content":[{"type":"text","text":"Bitti"}]}}
{"type":"system","subtype":"turn_duration","timestamp":"2026-11-04T19:59:01.000Z","sessionId":"s2","cwd":"/Users/ali/projects/mmxss"}
{"type":"last-prompt","lastPrompt":"gizli prompt","sessionId":"s2"}
```

Assert: `status == .idle`, `title == nil` (never use `lastPrompt`).

Incomplete line test: pass the working fixture plus `{"type":"assistant","timestamp":"2026-11-` as the last line; assert it still returns the working agent and does not crash.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ClaudeSourceTests`
Expected: compile error — `ClaudeSource` / `ClaudeParser` not found.

- [ ] **Step 3: Implement `ClaudeParser`**

Rules:
- Parse each line as JSON; ignore invalid lines.
- Track `cwd`, `sessionId`, `aiTitle`, last valid timestamp, last stateful event, last tool name and file path.
- Stateful events: `assistant`, `user`, `system`; ignore `ai-title`, `last-prompt`, `cost-state` for state, but use `last-prompt`/`cost-state` as “turn ended”.
- `age = now - lastTimestamp`; `age > 3600` → `.stale`.
- `system` with subtype `turn_duration`, `away_summary`, or `stop_hook_summary` → `.idle`.
- Last stateful event is `assistant` with a `tool_use` part, or `user` with a `tool_result` part, or `assistant` text → `.working` when `age <= 120`; otherwise `.idle`.
- Project from `ProjectLabel.resolve(directory: cwd, title: aiTitle)`.
- `detail` = `"<toolName> · <fileBasename>"` when both exist; otherwise `toolName` or `nil`.
- Return `nil` if there is no timestamp and no usable `cwd`.

- [ ] **Step 4: Implement `ClaudeSource`**

- If `projectsDir` does not exist → `SourceResult(status: "missing", agents: [])`.
- Enumerate `projectsDir/*/*.jsonl`; skip files with mtime older than `now - lookback`.
- Read the last 64 KB only:
  ```swift
  let handle = try FileHandle(forReadingFrom: url)
  let size = try handle.seekToEnd()
  try handle.seek(toOffset: max(0, size - 65_536))
  let data = try handle.readToEnd() ?? Data()
  ```
- If the read started mid-file, drop the first partial line.
- Pass lines to `ClaudeParser`; collect non-nil results.
- Return `"ok"` even when there are zero agents; a per-file read error is ignored, but if every file throws return `"error"`.

- [ ] **Step 5: Add a source-level test**

Create a temp directory with `proj/s1.jsonl` containing the working fixture plus a partial last line. Call `ClaudeSource(projectsDir: temp, lookback: 86_400).scan(now:)`. Assert `status == "ok"`, one agent, `.working`. Add a second assertion: a missing directory returns `"missing"` and zero agents.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter ClaudeSourceTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/DeckAgents/ClaudeSource.swift Tests/DeckAgentsTests/ClaudeSourceTests.swift
git commit -m "feat: read Claude Code sessions"
```

---

### Task 3: Codex source

**Files:**
- Create: `Sources/DeckAgents/CodexSource.swift`
- Test: `Tests/DeckAgentsTests/CodexSourceTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  ```swift
  public struct CodexSource: AgentSource {
      public let provider: String   // "codex"
      public let sessionsDir: URL
      public let lookback: TimeInterval
      public init(sessionsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions"),
                  lookback: TimeInterval = 86_400)
      public func scan(now: Date) -> SourceResult
  }

  public enum CodexParser {
      public static func parse(lines: [String], sessionID: String,
                               sourcePath: String, now: Date) -> AgentSession?
  }
  ```

- [ ] **Step 1: Write the failing parser tests**

Working fixture: a `session_meta` line with `payload.cwd` and `payload.id`, followed by `event_msg` `task_started` at `now - 10 s`. Assert `.working`, project `mmxss`.

Idle fixture: same `session_meta`, followed by `task_complete` at `now - 10 s`. Assert `.idle`.

Partial-line test: idle fixture plus `{"type":"event_msg","payload":{"type":"task_`; assert it still returns `.idle`.

Use this shape (field names may vary; inspect a real rollout with `head -1` before writing the parser):

```json
{"timestamp":"2026-11-04T20:00:00.000Z","type":"session_meta","payload":{"id":"c1","cwd":"/Users/ali/projects/mmxss"}}
{"timestamp":"2026-11-04T20:00:02.000Z","type":"event_msg","payload":{"type":"task_started"}}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CodexSourceTests`
Expected: compile error.

- [ ] **Step 3: Implement `CodexParser`**

- Read `session_meta.payload.id`, `payload.cwd`, and optional `payload.title`/`payload.originator`.
- Track the last `event_msg.payload.type` (`task_started`, `task_complete`, `agent_message`).
- `task_complete` → `.idle`; `task_started` → `.working` when `age <= 120`, else `.idle`; `age > 3600` → `.stale`.
- `title` = session title if present, else `nil`; never use a raw user prompt.
- `detail` = last event type or last tool name.
- `project` from `ProjectLabel`.

- [ ] **Step 4: Implement `CodexSource`**

Mirror `ClaudeSource`: missing dir → `"missing"`, enumerate `sessionsDir/**/rollout-*.jsonl` (recursive), filter by mtime/lookback, read last 64 KB, drop partial first line, call parser.

- [ ] **Step 5: Add a source-level test with a temp directory**

Create `2026/11/04/rollout-c1.jsonl` with the idle fixture; assert one `.idle` agent. Add a missing-directory assertion.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter CodexSourceTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/DeckAgents/CodexSource.swift Tests/DeckAgentsTests/CodexSourceTests.swift
git commit -m "feat: read Codex sessions"
```

---

### Task 4: OpenCode source (v2 + legacy)

**Files:**
- Create: `Sources/DeckAgents/OpenCodeSource.swift`
- Test: `Tests/DeckAgentsTests/OpenCodeSourceTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  ```swift
  public struct OpenCodeSource: AgentSource {
      public let provider: String   // "opencode"
      public let dbURL: URL
      public let lookback: TimeInterval
      public init(dbURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/opencode/opencode.db"),
                  lookback: TimeInterval = 86_400)
      public func scan(now: Date) -> SourceResult
  }
  ```

- [ ] **Step 1: Add a test SQLite helper**

In `Tests/DeckAgentsTests/OpenCodeSourceTests.swift`, add:

```swift
import XCTest
import SQLite3
@testable import DeckAgents

final class OpenCodeSourceTests: XCTestCase {
    private func makeDB() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        sqlite3_close(db)
        return url
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            XCTFail(err.map { String(cString: $0) } ?? "sqlite error \(rc)")
        }
        sqlite3_free(err)
    }
}
```

Add a `TestDB` helper with `open()`, `exec()`, and `close()`; create temporary DBs in each test and delete them in `defer`.

- [ ] **Step 2: Write the failing v2 test**

Create the v2 schema:

```sql
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
```

Insert:

- `project`: `id='p1', name='kresim', worktree='/Users/ali/projects/kresim'`
- `session_v2`: parent row `id='ses_root'`, `project_id='p1'`, `directory='/Users/ali/projects/kresim'`, `title='Dosya inceleme'`, `time_updated=now-10s`, `time_busy=now-5s`, `time_idle=now-20s`
- child row `id='ses_child'`, `parent_id='ses_root'`, same times.
- `session_message`: one `assistant` row for `ses_root` with data `{"agent":"build","time":{"created":...}}`.

Assert: one agent, `id == "opencode:ses_root"`, project `kresim`, status `.working`, child excluded.

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift test --filter OpenCodeSourceTests`
Expected: compile error / query failure.

- [ ] **Step 4: Implement v2 scan**

- Open with `sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)`; `sqlite3_busy_timeout(db, 100)`.
- Detect `session_v2` and `session_message` in `sqlite_master`; if both exist use v2, else legacy `session`+`message`, else `"error"`.
- v2 SQL:
  ```sql
  select s.id, s.parent_id, s.directory, s.title,
         s.time_created, s.time_updated, s.time_archived,
         s.time_busy, s.time_idle, p.name
  from session_v2 s
  left join project p on p.id = s.project_id
  where (s.parent_id is null or s.parent_id = '')
    and s.time_archived is null
  order by s.time_updated desc
  limit 20;
  ```
- Status: `time_idle` null or `time_busy > time_idle` → `.working`; `time_updated` older than 1 h → `.stale`; else `.idle`.
- `title` = session title (≤60 chars); `detail` = last `session_message` with `type='assistant'`, parse `data` JSON and use `agent` if present, else `nil`.
- `project`: `p.name` if non-empty; else `ProjectLabel.resolve(directory: s.directory, title: s.title)`.
- Missing DB file → `"missing"`; SQL/opening error → `"error"`.

- [ ] **Step 5: Add legacy and missing tests**

Create the legacy schema:

```sql
create table session (
  id text primary key, directory text, title text,
  time_created integer, time_updated integer, time_archived integer
);
create table message (
  id text primary key, session_id text,
  time_created integer, time_updated integer, data text
);
```

Insert one idle assistant message with `{"role":"assistant","time":{"created":...,"completed":...},"finish":"stop"}`. Assert status `.idle` and the agent appears. Add a missing-DB test asserting `"missing"`.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter OpenCodeSourceTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/DeckAgents/OpenCodeSource.swift Tests/DeckAgentsTests/OpenCodeSourceTests.swift
git commit -m "feat: read OpenCode v2 and legacy sessions"
```

---

### Task 5: Scanner, merge, and ordering

**Files:**
- Create: `Sources/DeckAgents/AgentScanner.swift`
- Test: `Tests/DeckAgentsTests/AgentScannerTests.swift`

**Interfaces:**
- Consumes: `AgentSource`, `SourceResult`, `AgentSnapshot`, `AgentSession` (Task 1).
- Produces:
  ```swift
  public struct AgentScanner {
      public let refreshSeconds: Int
      public let maxRows: Int
      public init(sources: [AgentSource], maxAgents: Int = 20,
                  excludeProjects: [String] = [], refreshSeconds: Int = 3, maxRows: Int = 5)
      public func scan(now: Date) -> AgentSnapshot
  }
  ```

- [ ] **Step 1: Write the failing scanner tests**

Use two fake sources:
- source A (`claude`) returns one `.idle` agent at `now-60` and one `.working` at `now-5`.
- source B (`codex`) returns one `.working` at `now-2`, plus `status: "missing"`.

Assert:
- Order is `codex` working at `now-2`, `claude` working at `now-5`, `claude` idle at `now-60`.
- `sources == ["claude": "ok", "codex": "missing"]`.
- `snapshot.refreshSeconds == 3` and `snapshot.maxRows == 5` with defaults.
- `maxAgents: 1` returns only the newest working agent.
- `excludeProjects: ["scratch"]` drops an agent whose project is `scratch`.
- Duplicate `id` from two sources keeps the latest `lastActivity` (last wins).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AgentScannerTests`
Expected: compile error.

- [ ] **Step 3: Implement `AgentScanner.scan`**

- In `init`, clamp `refreshSeconds` to `2...10` and `maxRows` to `1...10`.
- Call each source with `now`; collect statuses into `sources[provider]`.
- Merge agents; dedupe by `id` (keep the one with the newest `lastActivity`).
- Drop projects in `excludeProjects`.
- Sort by status rank (`working` 0, `idle` 1, `stale` 2, `unknown` 3), then `lastActivity` descending, then `id`.
- Cap at `maxAgents`.
- Return `AgentSnapshot(updated: now, refreshSeconds: refreshSeconds, sources: sources, agents: capped, maxRows: maxRows)`.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter AgentScannerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DeckAgents/AgentScanner.swift Tests/DeckAgentsTests/AgentScannerTests.swift
git commit -m "feat: merge and order agent sessions"
```

---

### Task 6: Agent configuration

**Files:**
- Create: `Sources/DeckAgents/AgentConfig.swift`
- Test: `Tests/DeckAgentsTests/AgentConfigTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```swift
  public struct SourceToggle: Codable, Equatable {
      public var enabled: Bool
      public init(enabled: Bool = true)
  }

  public struct AgentConfig: Codable, Equatable {
      public var enabled: Bool
      public var maxRows: Int
      public var refreshSeconds: Int
      public var lookbackHours: Int
      public var redactTitles: Bool
      public var sources: [String: SourceToggle]
      public var excludeProjects: [String]
      public static let `default`: AgentConfig
      public static func load(from url: URL) -> AgentConfig
  }
  ```

- [ ] **Step 1: Write the failing tests**

- Missing file → defaults: enabled true, maxRows 5, refreshSeconds 3, lookbackHours 24, redactTitles false, all three sources enabled, excludeProjects empty.
- Valid JSON overrides `refreshSeconds: 9`, `redactTitles: true`, `sources.codex.enabled: false`.
- Invalid JSON → defaults.
- `refreshSeconds: 1` clamps to 2; `refreshSeconds: 99` clamps to 10.
- Unknown keys are ignored.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AgentConfigTests`
Expected: compile error.

- [ ] **Step 3: Implement `AgentConfig`**

Use `Codable` with a custom `init(from:)` that supplies defaults for missing keys. `load(from:)` returns `default` on any read/decode error. Clamp `refreshSeconds` to `2...10` and `maxRows` to `1...10` in `load`.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter AgentConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DeckAgents/AgentConfig.swift Tests/DeckAgentsTests/AgentConfigTests.swift
git commit -m "feat: add agent panel configuration"
```

---

### Task 7: Cached agent store

**Files:**
- Create: `Sources/DeckAgents/AgentStore.swift`
- Test: `Tests/DeckAgentsTests/AgentStoreTests.swift`

**Interfaces:**
- Consumes: `AgentScanner`, `AgentSnapshot`, `AgentSession` (Tasks 1, 5).
- Produces:
  ```swift
  public final class AgentStore {
      public let refreshSeconds: Int          // clamped 2...10
      public init(scanner: AgentScanner)
      public func start()
      public func stop()
      public func refreshNow()
      public func snapshot() -> AgentSnapshot
      public func path(for id: String) -> String?
  }
  ```

- [ ] **Step 1: Write the failing tests**

- A fake source returns one agent; `refreshNow()` then `snapshot()` contains it.
- `path(for: "claude:s1")` returns the agent's `path`; unknown id returns `nil`.
- A scanner with `refreshSeconds: 1` produces a store with `refreshSeconds == 2`; `99` clamps to `10`.
- Calling `refreshNow()` twice with a source that changes its result replaces the snapshot.
- `start()` followed immediately by `stop()` does not crash and leaves a valid snapshot.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AgentStoreTests`
Expected: compile error.

- [ ] **Step 3: Implement `AgentStore`**

- Private serial queue `DispatchQueue(label: "oldphonedeck.agents")`.
- `NSLock` around `snapshot`.
- `init` clamps `scanner.refreshSeconds` to `2...10` into the public `refreshSeconds` property.
- `start()`: refresh immediately, then a `DispatchSourceTimer` every `refreshSeconds`, leeway 0.5 s.
- `refreshNow()`: synchronous scan for tests/CLI; update snapshot under lock.
- `snapshot()`: lock, return.
- `path(for:)`: lock, find by `id`, return `path`.
- `stop()`: cancel timer.

- [ ] **Step 4: Run the tests**

Run: `swift test --filter AgentStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DeckAgents/AgentStore.swift Tests/DeckAgentsTests/AgentStoreTests.swift
git commit -m "feat: cache agent snapshots"
```

---

### Task 8: HTTP routes and CLI dump

**Files:**
- Modify: `Sources/oldphonedeck/main.swift`
- Create: `Sources/oldphonedeck/AgentWiring.swift`
- Test: manual via `curl`

**Interfaces:**
- Consumes: `AgentConfig`, `AgentScanner`, `AgentStore`, `ClaudeSource`, `CodexSource`, `OpenCodeSource` (Tasks 2–7).
- Produces:
  ```swift
  func makeAgentSources(config: AgentConfig) -> [AgentSource]
  func makeAgentStore(config: AgentConfig) -> AgentStore
  ```
  Routes:
  - `GET /agents?k=<token>` → `agentStore.snapshot().jsonObject(now: Date(), redactTitles: config.redactTitles)`
  - `POST /focus?k=<token>` with `id=<agent id>` → Finder reveals `agent.path`; 404 for unknown.

- [ ] **Step 1: Add the wiring file**

Create `AgentWiring.swift`:
- If `config.enabled == false`, return an empty source list.
- Default Claude path `~/.claude/projects`, Codex `~/.codex/sessions`, OpenCode `~/.local/share/opencode/opencode.db`.
- Include a source only when `config.sources[provider]?.enabled != false`.
- `lookback = TimeInterval(config.lookbackHours * 3600)`; pass it to all three sources.
- `AgentScanner(sources:, maxAgents: 20, excludeProjects: config.excludeProjects,
  refreshSeconds: config.refreshSeconds, maxRows: config.maxRows)`.
- `AgentStore(scanner: scanner)`.

- [ ] **Step 2: Add `--dump-agents` to `Options`**

Add `var dumpAgents = false` and `case "--dump-agents": dumpAgents = true` in `Options.init`. Print help text.

- [ ] **Step 3: Wire `main.swift`**

- Load `AgentConfig` from `~/.oldphonedeck/agents.json`.
- Build `agentStore`; call `start()` after the server starts.
- Add routes inside the existing switch, after the token guard:
  ```swift
  case ("GET", "/agents"):
      conn.respondJSON(agentStore.snapshot().jsonObject(now: Date(), redactTitles: agentsConfig.redactTitles))
  case ("POST", "/focus"):
      guard let path = agentStore.path(for: p["id"] ?? "") else { return conn.respond(404, text: "unknown agent") }
      DispatchQueue.main.async {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
      conn.respond(text: "ok")
  ```
- If `--dump-agents`: build the store, `refreshNow()`, print `JSONSerialization` pretty output, `exit(0)` before creating the server.

- [ ] **Step 4: Verify build and JSON**

Run:
```bash
swift build -c release
.build/release/oldphonedeck --dump-agents | jq '.sources, (.agents | length)'
```
Expected: valid JSON; `sources` has claude/codex/opencode; no crash when a directory is missing.

- [ ] **Step 5: Verify HTTP routes**

Run the server, copy the printed token, then:
```bash
curl -s "http://localhost:8045/agents?k=$TOKEN" | jq '.agents[0]'
curl -s -o /dev/null -w '%{http_code}\n' "http://localhost:8045/agents"
```
Expected: first prints an agent or `null`; second prints `403`.

Test `/focus` with a real id from `/agents`; Finder should reveal the project folder. Unknown id returns 404.

- [ ] **Step 6: Commit**

```bash
git add Sources/oldphonedeck/AgentWiring.swift Sources/oldphonedeck/main.swift
git commit -m "feat: serve agent snapshots and focus requests"
```

---

### Task 9: Agent panel UI (wide landscape)

**Files:**
- Modify: `Sources/oldphonedeck/web/index.html`

**Interfaces:**
- Consumes: `GET /agents`, `POST /focus` (Task 8).
- Produces: `#agents` card with 5 rows; `loadAgents()`, `renderAgents()`, `agentState`; wide layout branch.

- [ ] **Step 1: Add the markup**

Inside `#deck`, after `#music`, add:

```html
<div id="agents" class="card">
  <div id="agentHead"><h3>Agents</h3><span id="agentCount">—</span></div>
  <div id="agentList"></div>
  <div id="agentFoot">son 24 saat</div>
</div>
```

- [ ] **Step 2: Add the CSS**

Add rules for `#agents`, `#agentHead`, `#agentCount`, `.arow`, `.adot`, `.an`, `.as`, `.at`, `.aempty`, and `.offline`. Use the existing card colors and 18 pt radius. Row height 40 pt; status dot 7 pt; name 11.5 pt; subtitle 9.5 pt; time 8.5 pt. Add `.wide` overrides:

```css
.wide #keys { width: 294px; }
.wide .key { width: 66px; margin: 0 10px 10px 0; }
.wide .key:nth-child(4n) { margin-right: 0; }
.wide .cap { width: 66px; height: 66px; border-radius: 17px; }
.wide .cap img { left: 9px; top: 9px; width: 48px; height: 48px; }
.wide .key .label { font-size: 9.5px; margin-top: 5px; }
```

- [ ] **Step 3: Add the wide layout branch**

In `layout()`, after `portrait` is known:

```js
var wide = !portrait && W >= 520;
document.body.className = wide ? 'wide' : '';
$('agents').style.display = (wide || portrait) ? 'block' : 'none';
```

- Wide: keys at `left: 14, top: 46`; music at `left: 14, top: 242, width: 312, height: 58`; agents at `left: 336, top: 46, width: 218, height: 266`; hide `#net` and `#bat`.
- In the wide branch set `cardW = 218; batH = 266;` so the shared `batteryRows`/spark math stays finite even though those cards are hidden.
- Narrow landscape: restore `#net`/`#bat` display, hide `#agents`.
- Portrait: see Task 10.

- [ ] **Step 4: Add polling and rendering (ES5)**

Add near the stats polling:

```js
var agentState = { agents: [], sources: {} };
function loadAgents() {
  if (view !== 'deck' || document.hidden) return;
  xhr('GET', url('/agents'), null, function (s, text) {
    if (s !== 200) { $('agents').className = 'card offline'; return; }
    try { agentState = JSON.parse(text); } catch (e) { return; }
    $('agents').className = 'card';
    renderAgents();
  });
}
setInterval(loadAgents, 3000);
```

`renderAgents()`:
- Slice to `agentState.maxRows || 5` rows; in portrait cap at 3.
- Count `status === 'working'`; set `#agentCount` to `"N ÇALIŞIYOR"` or `"BOŞTA"`.
- Build rows with `document.createElement` and `textContent` (never `innerHTML` with agent data).
- Provider label mapping: `claude → Claude`, `codex → Codex`, `opencode → OpenCode`.
- Subtitle: `detail || title || ''`.
- Time: `ago(Date.now() - a.lastActivity * 1000)`.
- Empty: `<div class="aempty">Agent verisi yok</div>`.
- Tap a row: `xhr('POST', url('/focus'), 'id=' + encodeURIComponent(a.id))`.

Call `loadAgents()` at the end of `show('deck')` so the panel fills immediately.

- [ ] **Step 5: Verify in a browser**

Run the server and open `http://localhost:8045/#k=<token>` in a desktop browser with a 736×414 viewport (Chrome device toolbar / Safari responsive design). Expected:
- 8 keys fit left, 5 agent rows fit right, no scrollbars.
- Working rows are green, idle gray; count pill matches.
- Tapping a row reveals the project folder in Finder.
- Stopping the server grays the panel (`.offline`).

- [ ] **Step 6: Commit**

```bash
git add Sources/oldphonedeck/web/index.html
git commit -m "feat: add agent panel to the deck"
```

---

### Task 10: System sheet and portrait fallback

**Files:**
- Modify: `Sources/oldphonedeck/web/index.html`

**Interfaces:**
- Consumes: `lastStats` from the existing `pollStats`; `#agents` from Task 9.
- Produces: `#system` sheet, `#sysBtn`, `renderSystem()`, portrait 3-row agent panel.

- [ ] **Step 1: Add the system sheet markup**

Add a `#system` scrim next to the existing sheets:

```html
<div id="system" class="scrim">
  <div class="sheet">
    <h2>System</h2>
    <div id="sysBody"></div>
    <div class="btns"><div class="btn" id="sysClose">Close</div></div>
  </div>
</div>
```

Add a small button in `#right` before the phone battery: `<span id="sysBtn">⌄</span>`. Style it as a tappable 28×28 area.

- [ ] **Step 2: Store stats and render the sheet**

In `pollStats`, after `var d = JSON.parse(text);` add `lastStats = d;` near the existing `lastBatteries` variable. Implement `renderSystem()`:
- Internet: down/up/ping from `lastStats.speed`, or “—”.
- Batteries: each `lastStats.batteries` entry as `name — level%` (include iPhone if `phone` is set).
- If `lastStats` is null, show “Veri yok”.

Wire `tap($('sysBtn'), function () { renderSystem(); sheet('system', true); });` and `tap($('sysClose'), function () { sheet('system', false); });`.

- [ ] **Step 3: Hide net/bat cards in wide and portrait**

In `layout()`, set `$('net').style.display` and `$('bat').style.display` to `'none'` in wide and portrait, `'block'` in narrow landscape. The system sheet is the only place they appear on the phone.

- [ ] **Step 4: Portrait agent panel**

In the portrait branch, after music:
- `px($('agents'), { left: 16, top: top + 208 + 4 + 58 + 12, width: W - 32, height: 190 });`
- Keep 3 rows in portrait; `renderAgents()` uses `Math.min(agentState.maxRows || 5, portrait ? 3 : 99)`.
- Ensure `#agents` bottom stays inside `H`; if `H < 620`, reduce the height to `H - top - 350` with a minimum of 150 and show 2 rows.

- [ ] **Step 5: Verify**

- Desktop 736×414: net/bat hidden; `⌄` opens the system sheet with live values; close works.
- Desktop 414×736 portrait: keys, music, 3 agent rows fit; no overflow.
- Narrow landscape (e.g., 568×320): old net/bat cards return; `#agents` hidden.

- [ ] **Step 6: Commit**

```bash
git add Sources/oldphonedeck/web/index.html
git commit -m "feat: add system sheet and portrait agent panel"
```

---

### Task 11: launchd scripts and setup docs

**Files:**
- Create: `scripts/install-launchd.sh`
- Create: `scripts/uninstall-launchd.sh`
- Create: `docs/agent-panel-setup.md`
- Modify: `README.md` (add a short “Agent panel” section linking to the setup doc)

**Interfaces:**
- Consumes: built binary at `.build/release/oldphonedeck`.
- Produces: user LaunchAgent `com.aliihsan.oldphonedeck.plist`.

- [ ] **Step 1: Write the install script**

Requirements:
- `set -euo pipefail`.
- Resolve repo root from the script path.
- Fail if `.build/release/oldphonedeck` is missing, with the build command.
- Write the plist to `${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}/com.aliihsan.oldphonedeck.plist`.
- `ProgramArguments`: the binary path, `--port 8045`.
- `RunAtLoad=true`, `KeepAlive=true`, `StandardOutPath=$HOME/Library/Logs/oldphonedeck.log`, `StandardErrorPath` same.
- If `LAUNCHD_DRY_RUN=1`, skip `launchctl` entirely (used by tests).
- Otherwise, if `launchctl` is available, `launchctl bootout gui/$(id -u) <plist>` (ignore failure), then `launchctl bootstrap gui/$(id -u) <plist>`.
- Print the log path and the stop command.

- [ ] **Step 2: Write the uninstall script**

`launchctl bootout` (ignore failure), remove the plist, print “stopped”.

- [ ] **Step 3: Write the setup doc**

Turkish, concise:
- Requirements (macOS 14+, iPhone 8 Plus, same Wi-Fi).
- Build and first run; token URL.
- Add to Home Screen, Auto-Lock Never, Guided Access.
- Agent panel data sources and the three paths.
- `~/.oldphonedeck/agents.json` example with `redactTitles`, `maxRows`, source toggles.
- launchd install/uninstall.
- Security note: URL is a password; no port-forward.
- Troubleshooting: empty panel, macOS firewall, IP change, stale status.

- [ ] **Step 4: Verify scripts without touching the real LaunchAgents**

Run:
```bash
bash -n scripts/install-launchd.sh
bash -n scripts/uninstall-launchd.sh
TMP=$(mktemp -d)
LAUNCHD_DRY_RUN=1 LAUNCH_AGENTS_DIR="$TMP" bash scripts/install-launchd.sh
plutil -lint "$TMP/com.aliihsan.oldphonedeck.plist"
LAUNCH_AGENTS_DIR="$TMP" bash scripts/uninstall-launchd.sh
test ! -e "$TMP/com.aliihsan.oldphonedeck.plist" && echo ok
```
Expected: `plutil` says OK; `ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts docs/agent-panel-setup.md README.md
git commit -m "docs: add agent panel setup and launchd scripts"
```

---

### Task 12: End-to-end device verification

**Files:** none (fixes only if a check fails).

- [ ] **Step 1: Build and run on the Mac**

```bash
swift build -c release
.build/release/oldphonedeck
```

Open the printed URL on the iPhone 8 Plus in Safari; Add to Home Screen.

- [ ] **Step 2: Run the acceptance checklist**

- Page loads full-screen in landscape; no scrollbars; 8 keys + 5 agent rows visible.
- All 8 keys launch the expected apps; long-press opens the app picker.
- Agent rows show the expected providers; working/idle dots match `--dump-agents`.
- Tap an agent row → Finder reveals the project folder.
- Stop the server → panel grays out; restart → panel recovers within 5 s.
- Turn Wi-Fi off/on on the phone → panel recovers; deck does not freeze.
- Rotate to portrait → 3 agent rows fit; rotate back → 5 rows.
- Open `⌄` system sheet → speed/battery values appear; close works.
- 30 minutes charging with screen on: no thermal warning, no unexpected reload.
- Token-less `curl` still returns 403.

- [ ] **Step 3: Fix and commit only if a check fails**

```bash
git add -A
git commit -m "fix: address device verification issues"
```

---

## Self-Review Notes

- **Spec coverage:** intent/goals → Tasks 1–12; no-hook read-only → Tasks 2–4; iPhone layout → Tasks 9–10; config → Task 6; security/token → existing guard + Task 8; launchd → Task 11; acceptance → Task 12.
- **Type consistency:** `AgentSession` fields, `jsonObject(now:redactTitles:)`, `SourceResult.status`, `AgentStore.path(for:)`, and `AgentConfig.refreshSeconds` are used with the same names in every task.
- **Review Focus mapping:** incomplete JSONL → Tasks 2/3; OpenCode missing/legacy → Task 4; child sessions → Task 4; workspace-root labels → Task 1; stale/offline → Tasks 5/9/12.
- **Out of scope:** hook-based approvals, terminal jump, camera/mic, `.local`/QR, `+N` child badge. These stay in the spec as v2 or builder-left items.
