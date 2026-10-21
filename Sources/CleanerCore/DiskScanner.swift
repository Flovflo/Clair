import Foundation
import CryptoKit
import Darwin

public struct DiskScanner: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        // POSIX realpath avoids Foundation's /private/var → /var URL rewriting.
        if let resolved = realpath(home.path, nil) {
            self.home = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            free(resolved)
        } else {
            self.home = home.standardizedFileURL
        }
    }

    public func scan(
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (String) -> Void = { _ in }
    ) throws -> ScanReport {
        var items: [CleanItem] = []
        var issues: [ScanIssue] = []
        for source in SourceKind.allCases where !source.isProjectOutput {
            if isCancelled() { throw CancellationError() }
            progress(source.title)
            let root = home.appendingPathComponent(source.relativeRoot)
            do {
                guard try exists(root) else { continue }
                try checkPath(root)
                let targets = try discover(root, depth: source.depth, source: source, issues: &issues)
                for url in targets {
                    if isCancelled() { throw CancellationError() }
                    do {
                        try checkPath(url)
                        let snapshot = try measure(url, isCancelled: isCancelled)
                        guard snapshot.fileCount > 0 else { continue }
                        items.append(CleanItem(url: url, source: source, name: displayName(url, source),
                                               allocatedBytes: snapshot.allocated, logicalBytes: snapshot.logical,
                                               latestModification: snapshot.latest, fileCount: snapshot.fileCount,
                                               fingerprint: snapshot.fingerprint))
                    } catch is CancellationError { throw CancellationError() }
                    catch { issues.append(ScanIssue(path: url.path, message: error.localizedDescription)) }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(ScanIssue(path: root.path, message: error.localizedDescription)) }
        }
        return ScanReport(items: items.sorted {
            $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes
        }, issues: issues, disk: diskSpace(), completedAt: Date())
    }

    public func validate(_ item: CleanItem) throws {
        try validateAllowed(item.url, source: item.source)
        let snapshot = try measure(item.url)
        guard snapshot.fingerprint == item.fingerprint else { throw CleanerError.changed }
        try checkPath(item.url)
    }

    public func inspect(_ url: URL) throws -> CleanItem {
        // Use the canonical home prefix even for /var fixture and user-selected paths.
        guard let resolved = realpath(url.path, nil) else { throw CleanerError.unreadable(url.path) }
        let resolvedPath = String(cString: resolved)
        free(resolved)
        // Only normalize Apple's /var alias; do not silently accept user symlinks.
        let target = URL(fileURLWithPath: resolvedPath)
        let original = url.path.hasPrefix("/var/") ? "/private" + url.path : url.path
        guard original == resolvedPath else { throw CleanerError.unsafePath }
        guard let source = CleanupPolicy.source(for: target, home: home) else { throw CleanerError.unsafePath }
        try validateAllowed(target, source: source)
        let snapshot = try measure(target)
        return CleanItem(url: target, source: source, name: displayName(target, source), allocatedBytes: snapshot.allocated,
                         logicalBytes: snapshot.logical, latestModification: snapshot.latest, fileCount: snapshot.fileCount,
                         fingerprint: snapshot.fingerprint)
    }

    private func validateAllowed(_ target: URL, source: SourceKind) throws {
        try checkPath(target)
        guard CleanupPolicy.source(for: target, home: home) == source else { throw CleanerError.unsafePath }
        if source.isProjectOutput {
            guard try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CleanerError.unsafePath }
            if source == .projectBuild || source == .dependencies {
                let manifest = target.deletingLastPathComponent().appendingPathComponent(source == .projectBuild ? "Package.swift" : "package.json")
                try checkPath(manifest)
                guard try manifest.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CleanerError.unsafePath }
            }
            return
        }
        let root = home.appendingPathComponent(source.relativeRoot)
        var ancestor = target
        for _ in 0..<source.depth { ancestor.deleteLastPathComponent() }
        guard ancestor.path == root.path, accepts(target, source: source) else {
            throw CleanerError.unsafePath
        }
    }

    public func diskSpace() -> DiskSpace? {
        guard let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else { return nil }
        return DiskSpace(total: Int64(total), available: Int64(available))
    }

    private func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw CleanerError.unreadable(url.path)
    }

    // Check every component, including ancestors of the known root. Never traverse an alias.
    private func checkPath(_ url: URL) throws {
        guard url.path.hasPrefix(home.path + "/"), !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else { throw CleanerError.unsafePath }
        var part = home
        let suffix = url.pathComponents.dropFirst(home.pathComponents.count)
        for component in suffix {
            part.appendPathComponent(component)
            var info = stat()
            guard lstat(part.path, &info) == 0 else { throw CleanerError.unreadable(part.path) }
            guard info.st_mode & S_IFMT != S_IFLNK else { throw CleanerError.unsafePath }
        }
    }

    private func discover(_ root: URL, depth: Int, source: SourceKind, issues: inout [ScanIssue]) throws -> [URL] {
        if depth == 0 { return [root] }
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var result: [URL] = []
        for child in children.sorted(by: { $0.path < $1.path }) {
            do {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { continue }
                if depth > 1 {
                    guard values.isDirectory == true else { continue }
                    result += try discover(child, depth: depth - 1, source: source, issues: &issues)
                } else if accepts(child, source: source) { result.append(child) }
            } catch { issues.append(ScanIssue(path: child.path, message: error.localizedDescription)) }
        }
        return result
    }

    private func accepts(_ url: URL, source: SourceKind) -> Bool {
        switch source {
        case .huggingFace: return ["models--", "datasets--", "spaces--"].contains { url.lastPathComponent.hasPrefix($0) }
        case .archives: return url.pathExtension == "xcarchive"
        case .downloadInstaller: return ["dmg", "pkg"].contains(url.pathExtension.lowercased())
        case .userCache: return !url.lastPathComponent.hasPrefix(".") && url.lastPathComponent != "com.apple.dt.Xcode"
        default: return !url.lastPathComponent.hasPrefix(".")
        }
    }

    private func displayName(_ url: URL, _ source: SourceKind) -> String {
        switch source {
        case .ollama: "Bibliothèque Ollama complète"
        case .mtplx: "Bibliothèque MTPLX complète"
        case .projectBuild, .dependencies: "\(url.deletingLastPathComponent().lastPathComponent) / \(url.lastPathComponent)"
        case .huggingFace: url.lastPathComponent.components(separatedBy: "--").dropFirst().joined(separator: " / ")
        case .lmStudio, .legacyLMStudio: "\(url.deletingLastPathComponent().lastPathComponent) / \(url.lastPathComponent)"
        default: url.deletingPathExtension().lastPathComponent
        }
    }

    private struct Snapshot {
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var latest = Date.distantPast
        var fileCount = 0
        var fingerprint = ""
    }

    private func measure(_ root: URL, isCancelled: @Sendable () -> Bool = { false }) throws -> Snapshot {
        var snapshot = Snapshot()
        var records: [String] = []
        var inodes: Set<String> = []
        func record(_ url: URL) throws {
            if isCancelled() { throw CancellationError() }
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw CleanerError.unreadable(url.path) }
            let type = info.st_mode & S_IFMT
            let relative = String(url.path.dropFirst(root.path.count))
            records.append("\(relative)|\(info.st_dev)|\(info.st_ino)|\(info.st_mode)|\(info.st_size)|\(info.st_blocks)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec)|\(info.st_ctimespec.tv_nsec)")
            let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
            snapshot.latest = max(snapshot.latest, modified)
            guard type == S_IFREG else { return }
            snapshot.fileCount += 1
            guard inodes.insert("\(info.st_dev):\(info.st_ino)").inserted else { return }
            snapshot.allocated += Int64(info.st_blocks) * 512
            snapshot.logical += Int64(info.st_size)
        }
        try record(root)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            var readFailure: String?
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { url, _ in
                readFailure = url.path
                return false
            }) else { throw CleanerError.unreadable(root.path) }
            for case let url as URL in enumerator {
                if isCancelled() { throw CancellationError() }
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values.isSymbolicLink == true { enumerator.skipDescendants() }
                try record(url)
            }
            if let readFailure { throw CleanerError.unreadable(readFailure) }
        }
        var hasher = SHA256()
        for record in records.sorted() {
            hasher.update(data: Data(record.utf8))
            hasher.update(data: Data([0]))
        }
        snapshot.fingerprint = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return snapshot
    }
}
