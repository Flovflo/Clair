import XCTest
@testable import CleanerCore

final class StorageBrowserTests: XCTestCase {
    func testBrowserIncludesSmallHiddenFilesAndMeasuredFoldersWithoutFollowingLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairBrowser-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent(".hidden"))
        try Data(repeating: 2, count: 16384).write(to: root.appendingPathComponent("Folder/file"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("Link"), withDestinationURL: root)
        let report = try StorageScanner(root: root, home: root).scan()
        let entries = try StorageBrowser.contents(of: report.rootPath, report: report, home: root)
        XCTAssertEqual(Set(entries.map(\.name)), ["Folder", ".hidden"])
        XCTAssertEqual(entries.first?.name, "Folder")
        XCTAssertEqual(entries.first?.allocatedBytes, report.children(of: report.rootPath).first?.allocatedBytes)
        XCTAssertTrue(entries.allSatisfy { $0.modifiedAt != nil })
        XCTAssertEqual(StorageSort.name.sorted(entries).first?.name, ".hidden")
        try fm.createDirectory(at: root.appendingPathComponent("NewFolder"), withIntermediateDirectories: true)
        let refreshed = try StorageBrowser.contents(of: report.rootPath, report: report, home: root)
        XCTAssertEqual(refreshed.first(where: { $0.name == "NewFolder" })?.isMeasured, false)
    }
}
