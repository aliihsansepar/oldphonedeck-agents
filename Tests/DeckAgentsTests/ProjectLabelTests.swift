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
