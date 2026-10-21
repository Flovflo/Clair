import XCTest
@testable import CleanerCore

final class ExplorerCleanupTests: XCTestCase {
    func testNestedSelectionIsMeasuredAndMovedOnlyOnce() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("ClairNested-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let project = home.appendingPathComponent("Documents/Project")
        let build = project.appendingPathComponent(".build")
        let result = build.appendingPathComponent("Run.xcresult")
        try fm.createDirectory(at: result, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: result.appendingPathComponent("result.bin"))
        try Data("// package".utf8).write(to: project.appendingPathComponent("Package.swift"))
        let scanner = DiskScanner(home: home)
        let parent = try scanner.inspect(build)
        let child = try scanner.inspect(result)
        let normalized = CleanupSelection.topLevel([child, parent, child])
        XCTAssertEqual(normalized.map(\.id), [parent.id])
        let trash = home.appendingPathComponent("TestTrash")
        let service = TrashService(scanner: scanner, moveToTrash: { source in
            try FileManager.default.moveItem(at: source, to: trash)
            return trash
        })
        let outcome = service.clean([child, parent])
        XCTAssertEqual(outcome.moved.count, 1)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(outcome.bytes, parent.allocatedBytes)
        XCTAssertTrue(fm.fileExists(atPath: trash.appendingPathComponent("Run.xcresult/result.bin").path))
    }

    func testProjectBuildRequiresManifestAndProtectsSourceAndWorktrees() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("ClairPolicy-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let project = home.appendingPathComponent("Documents/Projet/Example")
        let build = project.appendingPathComponent(".build")
        try fm.createDirectory(at: build, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: build.appendingPathComponent("generated.o"))
        let scanner = DiskScanner(home: home)
        XCTAssertThrowsError(try scanner.inspect(build))
        try Data("// swift package".utf8).write(to: project.appendingPathComponent("Package.swift"))
        XCTAssertEqual(try scanner.inspect(build).source, .projectBuild)
        XCTAssertThrowsError(try scanner.inspect(project))
        XCTAssertThrowsError(try scanner.inspect(project.appendingPathComponent("Package.swift")))
        XCTAssertNil(CleanupPolicy.source(for: project.appendingPathComponent(".worktrees/task/.build"), home: home))
        XCTAssertNil(CleanupPolicy.source(for: project.appendingPathComponent(".artifacts"), home: home))
        XCTAssertNil(CleanupPolicy.source(for: home.appendingPathComponent("Pictures/Album.photoslibrary/.build"), home: home))
        XCTAssertNil(CleanupPolicy.source(for: home.appendingPathComponent("Documents/report.pdf"), home: home))
    }

    func testInstallerAndModelsRemainExplicitAndSystemFilesAreRejected() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("ClairExplicit-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads")
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        let installer = downloads.appendingPathComponent("Xcode.dmg")
        try Data(repeating: 1, count: 8192).write(to: installer)
        let item = try DiskScanner(home: home).inspect(installer)
        XCTAssertEqual(item.source, .downloadInstaller)
        XCTAssertFalse(item.isQuickCleanEligible(at: Date.distantFuture))
        XCTAssertNil(CleanupPolicy.source(for: downloads.appendingPathComponent("family.zip"), home: home))
        XCTAssertNil(CleanupPolicy.source(for: URL(fileURLWithPath: "/private/var/db/powerlog"), home: home))
        XCTAssertEqual(CleanupPolicy.source(for: home.appendingPathComponent(".mtplx/models"), home: home), .mtplx)
    }

    func testExplorerInspectionRejectsSymlinkAndValidationRechecksManifest() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("ClairManifest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let project = home.appendingPathComponent("Documents/Project")
        let modules = project.appendingPathComponent("node_modules")
        try fm.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data([1]).write(to: modules.appendingPathComponent("dependency.js"))
        let manifest = project.appendingPathComponent("package.json")
        try Data("{}".utf8).write(to: manifest)
        let scanner = DiskScanner(home: home)
        let item = try scanner.inspect(modules)
        XCTAssertEqual(item.source, .dependencies)
        try fm.removeItem(at: manifest)
        XCTAssertThrowsError(try scanner.validate(item))
        try fm.removeItem(at: modules)
        try fm.createSymbolicLink(at: modules, withDestinationURL: project)
        XCTAssertThrowsError(try scanner.inspect(modules))
    }
}
