import XCTest
@testable import CleanerCore

final class StorageInsightsTests: XCTestCase {
    func testProjectHeadlineAndReportDoNotDoubleCountArtifactBreakdown() {
        let home = URL(fileURLWithPath: "/Users/test")
        func folder(_ path: String, _ gb: Int64) -> StorageEntry {
            StorageEntry(path: path, allocatedBytes: gb * 1_000_000_000, logicalBytes: gb * 1_000_000_000,
                fileCount: 10, isDirectory: true, advice: StorageAdvice.classify(path: path, home: home.path))
        }
        let project = home.path + "/Documents/Projects/ExampleProject"
        let directories = [folder(project, 400), folder(project + "/.artifacts", 260),
                           folder(project + "/.artifacts/Run.xcresult", 30), folder(project + "/.worktrees", 120),
                           folder(home.path + "/.mtplx/models", 35), folder("/private/var/db/powerlog", 40)]
        let report = StorageReport(rootPath: "/", directories: directories, largeFiles: [], allocatedBytes: 600_000_000_000,
            logicalBytes: 600_000_000_000, fileCount: 50, issues: [], issueCount: 2, completedAt: .now)
        let insights = StorageInsights(report: report, home: home)
        XCTAssertEqual(insights.mainContributor?.path, project)
        XCTAssertEqual(insights.findings.count, 4)
        XCTAssertEqual(insights.findings.first?.entry.path, project + "/.artifacts")
        XCTAssertFalse(insights.findings.contains { $0.entry.path.hasSuffix("Run.xcresult") })
        let markdown = insights.markdown(report: report, diskCapacity: 1_000_000_000_000)
        XCTAssertTrue(markdown.contains("ExampleProject"))
        XCTAssertTrue(markdown.contains("40 %"))
        XCTAssertTrue(markdown.contains("2 chemins inaccessibles"))
        XCTAssertTrue(markdown.contains("Ne pas additionner"))
    }
    func testSystemRuntimesAndWallpaperOwnersAreNamed() {
        let paths = ["/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime", "/Users/test/Library/Application Support/com.apple.wallpaper"]
        let entries = paths.map { path in
            StorageEntry(path: path, allocatedBytes: 14_000_000_000, logicalBytes: 14_000_000_000, fileCount: 10,
                         isDirectory: true, advice: StorageAdvice.classify(path: path, home: "/Users/test"))
        }
        let report = StorageReport(rootPath: "/", directories: entries, largeFiles: [], allocatedBytes: 28_000_000_000,
                                   logicalBytes: 28_000_000_000, fileCount: 20, issues: [], issueCount: 0, completedAt: .now)
        let findings = StorageInsights(report: report, home: URL(fileURLWithPath: "/Users/test")).findings
        XCTAssertEqual(findings.count, 2)
        XCTAssertTrue(findings.contains { $0.title == "Xcode · systèmes des simulateurs" })
        XCTAssertTrue(findings.contains { $0.title == "Apple · fonds d’écran et économiseurs" })
    }

}
