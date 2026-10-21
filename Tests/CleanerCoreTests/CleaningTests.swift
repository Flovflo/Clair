import XCTest
@testable import CleanerCore

final class CleaningTests: XCTestCase {
    // Exercise validation + move as one operation without touching the real Trash.
    func testOnlyValidatedSelectedItemsAreMovedAndFailuresAreReported() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("ClairCleaning-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        for name in ["Selected", "Untouched", "Changed"] {
            let dir = cache.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 65, count: 8192).write(to: dir.appendingPathComponent("file"))
        }
        let destination = home.appendingPathComponent("TestTrash")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let scanner = DiskScanner(home: home)
        let report = try scanner.scan()
        let selection = report.items.filter { $0.name != "Untouched" }
        try Data([1, 2, 3]).write(to: cache.appendingPathComponent("Changed/file"))
        let service = TrashService(scanner: scanner, moveToTrash: { source in
            let target = destination.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: target)
            return target
        })
        let result = service.clean(selection)
        XCTAssertEqual(result.moved.map(\.item.name), ["Selected"])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("Selected/file").path))
        XCTAssertTrue(fm.fileExists(atPath: cache.appendingPathComponent("Untouched/file").path))
        XCTAssertTrue(fm.fileExists(atPath: cache.appendingPathComponent("Changed/file").path))
        XCTAssertFalse(fm.fileExists(atPath: cache.appendingPathComponent("Selected").path))
    }

    func testForgedOutsidePathIsRejected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ClairOutside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("important.txt")
        try Data([1]).write(to: file)
        let forged = CleanItem(url: file, source: .derivedData, name: "important", allocatedBytes: 1, logicalBytes: 1, latestModification: .now, fileCount: 1, fingerprint: "")
        XCTAssertThrowsError(try DiskScanner(home: home).validate(forged))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
