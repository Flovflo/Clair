import XCTest
@testable import CleanerCore

final class ScannerTests: XCTestCase {
    var home: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("ClairTests-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try fm.removeItem(at: home)
    }

    @discardableResult
    func fixture(_ path: String, bytes: Int = 8192) throws -> URL {
        let url = home.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: bytes).write(to: url)
        return url
    }

    // Catches accidentally scanning source projects or only part of a model repository.
    func testDiscoversOnlyKnownTargetsAndGroupsModels() throws {
        try fixture("Library/Developer/Xcode/DerivedData/Example-abcd/Build/file")
        try fixture(".cache/huggingface/hub/models--org--model/blobs/weight")
        try fixture(".lmstudio/models/org/model/weight.gguf")
        try fixture(".ollama/models/blobs/weight")
        try fixture(".ollama/models/manifests/registry/model/tag")
        try fixture("Documents/Project/main.swift")
        let report = try DiskScanner(home: home).scan()
        XCTAssertEqual(report.items.count, 4)
        XCTAssertEqual(Set(report.items.map(\.source)), [.derivedData, .huggingFace, .lmStudio, .ollama])
        XCTAssertEqual(report.items.first { $0.source == .ollama }?.logicalBytes, 16384)
        XCTAssertTrue(report.issues.isEmpty, report.issues.map(\.message).joined(separator: "\n"))
    }

    // Catches following a symlink to a large external model or document directory.
    func testDoesNotFollowInternalSymbolicLinks() throws {
        let outside = try fixture("Documents/private.txt", bytes: 1_000_000)
        try fixture("Library/Developer/Xcode/DerivedData/Example/real", bytes: 8192)
        let link = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Example/linked")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let report = try DiskScanner(home: home).scan()
        XCTAssertEqual(report.items.count, 1)
        XCTAssertEqual(try XCTUnwrap(report.items.first).logicalBytes, 8192)
    }

    func testRejectsSymbolicLinkAtRoot() throws {
        let outside = home.appendingPathComponent("Documents")
        try fixture("Documents/project/file")
        let root = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root, withDestinationURL: outside)
        let report = try DiskScanner(home: home).scan()
        XCTAssertTrue(report.items.isEmpty)
        XCTAssertFalse(report.issues.isEmpty)
    }

    func testValidationRejectsChangedDescendant() throws {
        let file = try fixture("Library/Developer/Xcode/DerivedData/Example/file")
        let scanner = DiskScanner(home: home)
        let item = try XCTUnwrap(scanner.scan().items.first)
        try Data(repeating: 66, count: 12345).write(to: file)
        XCTAssertThrowsError(try scanner.validate(item))
    }

    func testValidationRejectsReplacedTargetSymlink() throws {
        try fixture("Library/Developer/Xcode/DerivedData/Example/file")
        try fixture("Documents/secret")
        let scanner = DiskScanner(home: home)
        let item = try XCTUnwrap(scanner.scan().items.first)
        try fm.removeItem(at: item.url)
        try fm.createSymbolicLink(at: item.url, withDestinationURL: home.appendingPathComponent("Documents"))
        XCTAssertThrowsError(try scanner.validate(item))
    }

    func testQuickSelectionRequiresOldCacheAndNeverModels() throws {
        try fixture("Library/Developer/Xcode/DerivedData/Old/file")
        try fixture("Library/Developer/Xcode/DerivedData/Recent/file")
        try fixture(".cache/huggingface/hub/models--org--model/blobs/weight")
        let old = Date(timeIntervalSinceNow: -10 * 86400)
        let root = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Old")
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: root.appendingPathComponent("file").path)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: root.path)
        let report = try DiskScanner(home: home).scan()
        XCTAssertEqual(report.items.filter { $0.isQuickCleanEligible(at: Date()) }.map(\.name), ["Old"])
    }

    func testHardLinkedFilesAreNotCountedTwiceWithinItem() throws {
        let original = try fixture("Library/Developer/Xcode/DerivedData/Example/original")
        try fm.linkItem(at: original, to: original.deletingLastPathComponent().appendingPathComponent("alias"))
        let item = try XCTUnwrap(DiskScanner(home: home).scan().items.first)
        XCTAssertEqual(item.logicalBytes, 8192)
    }

    func testCancelledScanStops() throws {
        try fixture("Library/Developer/Xcode/DerivedData/Example/file")
        XCTAssertThrowsError(try DiskScanner(home: home).scan(isCancelled: { true }))
    }

    func testUnreadableOrganizationDoesNotHideAccessibleModels() throws {
        try fixture(".lmstudio/models/readable/model/weight.gguf")
        try fixture(".lmstudio/models/blocked/model/weight.gguf")
        let blocked = home.appendingPathComponent(".lmstudio/models/blocked")
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path) }
        let report = try DiskScanner(home: home).scan()
        XCTAssertEqual(report.items.map(\.name), ["readable / model"])
        XCTAssertTrue(report.issues.contains { $0.path.hasSuffix("/blocked") })
    }
}
