import XCTest
@testable import CleanerCore

final class StorageScannerTests: XCTestCase {
    func testFullScanIncludesHiddenAndPersonalFilesWithoutFollowingLinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairStorage-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        for path in ["Documents/work.txt", ".custom/models/weights.gguf", "Downloads/setup.dmg"] {
            let file = root.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: file)
        }
        try fm.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("Documents"))
        let report = try StorageScanner(root: root, home: root, largeFileThreshold: 1).scan()
        XCTAssertEqual(report.fileCount, 3)
        XCTAssertEqual(report.logicalBytes, 24576)
        XCTAssertEqual(report.largeFiles.count, 3)
        XCTAssertFalse(report.directories.contains { $0.path.contains("linked") })
        XCTAssertTrue(report.directories.contains { $0.path.hasSuffix("/.custom/models") && $0.logicalBytes == 8192 })
        XCTAssertEqual(report.largeFiles.first { $0.path.hasSuffix("setup.dmg") }?.advice.kind, .installer)
        XCTAssertEqual(report.largeFiles.first { $0.path.hasSuffix("work.txt") }?.advice.kind, .personal)
    }

    func testNestedFolderTotalsDoNotDoubleCountAndLargeFilesAreBounded() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairTree-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        for n in 1...5 { try Data(repeating: 1, count: n * 8192).write(to: root.appendingPathComponent("a/b/\(n)")) }
        let report = try StorageScanner(root: root, home: root, largeFileThreshold: 1, largeFileLimit: 2).scan()
        XCTAssertEqual(report.logicalBytes, 122880)
        XCTAssertEqual(report.directories.first { $0.path.hasSuffix("/a") }?.logicalBytes, 122880)
        XCTAssertEqual(report.largeFiles.map(\.logicalBytes), [40960, 32768])
    }

    func testOverlappingPhysicalRootsAreOnlyScannedOnce() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairOverlap-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let child = root.appendingPathComponent("nested")
        try fm.createDirectory(at: child, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: child.appendingPathComponent("file"))
        let report = try StorageScanner(scanRoots: [root, child], home: root).scan()
        XCTAssertEqual(report.fileCount, 1)
        XCTAssertEqual(report.logicalBytes, 8192)
        XCTAssertEqual(report.largeFiles.count, 1)
    }

    func testSystemAndApplicationDataAreNeverSuggestedAsGenericCaches() {
        let home = "/Users/example"
        XCTAssertEqual(StorageAdvice.classify(path: "/private/var/db/powerlog", home: home).kind, .system)
        XCTAssertEqual(StorageAdvice.classify(path: home + "/Library/Application Support/important.db", home: home).kind, .applicationData)
        XCTAssertEqual(StorageAdvice.classify(path: home + "/Library/Caches/tool/cache", home: home).kind, .cache)
        XCTAssertEqual(StorageAdvice.classify(path: "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime", home: home).kind, .simulator)
    }
}
