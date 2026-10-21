import XCTest
import SQLite3
@testable import CleanerCore

final class StorageIndexTests: XCTestCase {
    func testGlobalIndexIncludesSmallFilesCategoriesAndSearchAcrossFolders() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("ClairIndex-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let root = home.appendingPathComponent("Documents")
        for path in ["films/movie.mp4", "notes/Facture été.pdf", "notes/tiny.txt", "project/node_modules/lib/index.js"] {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192).write(to: url)
        }
        let indexURL = home.appendingPathComponent("Index/inventory.sqlite")
        let report = try StorageScanner(root: root, home: home, indexURL: indexURL).scan()
        let index = StorageIndex(url: indexURL)
        XCTAssertEqual(report.fileCount, 4)
        XCTAssertEqual(try index.query(InventoryQuery()).totalCount, 4)
        var query = InventoryQuery()
        query.search = "facture ete"
        XCTAssertEqual(try index.query(query).entries.map(\.name), ["Facture été.pdf"])
        query.search = ""
        query.category = .dependencies
        XCTAssertEqual(try index.query(query).entries.count, 1)
        XCTAssertEqual(report.categories.reduce(0) { $0 + $1.fileCount }, 4)
        XCTAssertEqual(report.categories.reduce(Int64(0)) { $0 + $1.bytes }, try index.query(InventoryQuery()).entries.reduce(Int64(0)) { $0 + $1.allocatedBytes })
        XCTAssertEqual(try index.restoreReport()?.fileCount, 4)
        query.category = nil
        query.limit = 2
        XCTAssertEqual(try index.query(query).entries.count, 2)
        query.offset = 2
        XCTAssertEqual(try index.query(query).entries.count, 2)
        query.offset = 0
        query.modifiedBefore = .distantPast
        XCTAssertEqual(try index.query(query).totalCount, 0)
        query.modifiedBefore = .distantFuture
        XCTAssertEqual(try index.query(query).totalCount, 4)
        query.minimumBytes = 1_000_000
        XCTAssertEqual(try index.query(query).totalCount, 0)
        query.minimumBytes = 0; query.modifiedBefore = nil; query.search = "%"
        XCTAssertEqual(try index.query(query).totalCount, 0)
        query.search = ""; query.scope = .folder(report.rootPath)
        XCTAssertEqual(try index.query(query).totalCount, 3)

    }

    func testCancelledScanPreservesPreviousCompletedIndex() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairIndexCancel-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("file.txt"))
        let indexURL = root.appendingPathComponent("ClairIndex/inventory.sqlite")
        _ = try StorageScanner(root: root, home: root, indexURL: indexURL).scan()
        XCTAssertThrowsError(try StorageScanner(root: root, home: root, indexURL: indexURL).scan(isCancelled: { true }))
        XCTAssertEqual(try StorageIndex(url: indexURL).restoreReport()?.fileCount, 1)
    }

    func testCancellationDuringFinalizationPreservesPreviousIndex() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairFinalCancel-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("old.txt"))
        let indexURL = root.appendingPathComponent("Index/inventory.sqlite")
        let scanner = StorageScanner(root: root, home: root, indexURL: indexURL)
        _ = try scanner.scan()
        try Data([2]).write(to: root.appendingPathComponent("new.txt"))
        let cancellation = CancellationFlag()
        XCTAssertThrowsError(try scanner.scan(isCancelled: { cancellation.value }, progress: {
            if $0.path.hasPrefix("Préparation du rapport") { cancellation.cancel() }
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try StorageIndex(url: indexURL).restoreReport()?.fileCount, 1)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: indexURL.deletingLastPathComponent().path), ["inventory.sqlite"])
    }

    func testHardLinkedPathsRemainSearchableWithoutDoubleCountingStorage() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairLinks-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.txt")
        try Data(repeating: 7, count: 8192).write(to: original)
        let indexURL = root.appendingPathComponent("Index/inventory.sqlite")
        let scanner = StorageScanner(root: root, home: root, indexURL: indexURL)
        let before = try scanner.scan()
        try fm.linkItem(at: original, to: root.appendingPathComponent("alias.txt"))
        let after = try scanner.scan()
        let index = StorageIndex(url: indexURL)
        let files = try index.query(InventoryQuery())
        XCTAssertEqual(Set(files.entries.map(\.name)), ["original.txt", "alias.txt"])
        XCTAssertTrue(files.entries.allSatisfy(\.sharesStorage))
        XCTAssertEqual(after.fileCount, 2)
        XCTAssertEqual(after.logicalBytes, before.logicalBytes)
        XCTAssertEqual(files.totalBytes, before.categories.reduce(0) { $0 + $1.bytes })
        XCTAssertEqual(files.entries.map(\.logicalBytes), [8192, 8192])
        var query = InventoryQuery(); query.scope = .folder(after.rootPath)
        XCTAssertEqual(try index.query(query).totalCount, 2)
        query.scope = .files; query.search = "alias.txt"
        XCTAssertEqual(try index.query(query).totalCount, 1)
    }

    func testCancellationInterruptsSQLFinalization() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairSQLCancel-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("old.txt"))
        let url = root.appendingPathComponent("Index/inventory.sqlite")
        let report = try StorageScanner(root: root, home: root, indexURL: url).scan()
        let writer = try StorageIndexWriter(destination: url, home: root.path)
        for number in 0..<3000 {
            try writer.add(path: root.path + "/file-\(number)", allocated: 4096, logical: 10, files: 1, directory: false)
        }
        let checks = CancellationChecks()
        XCTAssertThrowsError(try writer.finish(report, isCancelled: { checks.cancelOnSecondCheck() })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try StorageIndex(url: url).restoreReport()?.fileCount, 1)
    }

    func testPreviousIndexSchemaRemainsReadable() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ClairLegacyIndex-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("old.txt"))
        let url = root.appendingPathComponent("Index/inventory.sqlite")
        _ = try StorageScanner(root: root, home: root, indexURL: url).scan()
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "ALTER TABLE entries DROP COLUMN shared; PRAGMA user_version=0;", nil, nil, nil), SQLITE_OK)
        let index = StorageIndex(url: url)
        XCTAssertEqual(try index.restoreReport()?.fileCount, 1)
        XCTAssertEqual(try index.query(InventoryQuery()).entries.first?.sharesStorage, false)
    }

    func testClassificationPrioritizesUseOverExtensionAndNeverImpliesDeletable() {
        let home = "/Users/test"
        XCTAssertEqual(FileCategory.classify(path: home + "/Documents/clip.mov", home: home), .videos)
        XCTAssertEqual(FileCategory.classify(path: home + "/Library/Caches/tool/clip.mov", home: home), .caches)
        XCTAssertEqual(FileCategory.classify(path: home + "/Documents/project/node_modules/a.ts", home: home), .dependencies)
        XCTAssertEqual(FileCategory.classify(path: home + "/Documents/model.gguf", home: home), .models)
        XCTAssertEqual(FileCategory.classify(path: home + "/Library/Developer/Xcode/Archives/App.xcarchive/Products/App.app/binary", home: home), .xcodeArchives)
        XCTAssertEqual(FileCategory.classify(path: home + "/Documents/project/node_modules/electron/App.app/binary", home: home), .dependencies)
        XCTAssertEqual(FileCategory.classify(path: home + "/Pictures/photo.heic", home: home), .images)
        XCTAssertNil(CleanupPolicy.source(for: URL(fileURLWithPath: home + "/Documents/clip.mov"), home: URL(fileURLWithPath: home)))
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var value: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

private final class CancellationChecks: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func cancelOnSecondCheck() -> Bool { lock.withLock { count += 1; return count >= 2 } }
}
