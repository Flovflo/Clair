import Foundation
import Darwin

public enum StorageSort: String, CaseIterable, Sendable {
    case size = "Taille", name = "Nom", recent = "Modification"

    public func sorted(_ entries: [StorageEntry]) -> [StorageEntry] {
        entries.sorted { a, b in
            switch self {
            case .size:
                if a.allocatedBytes != b.allocatedBytes { return a.allocatedBytes > b.allocatedBytes }
            case .recent:
                if a.modifiedAt != b.modifiedAt { return (a.modifiedAt ?? .distantPast) > (b.modifiedAt ?? .distantPast) }
            case .name: break
            }
            return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
    }
}

public enum StorageBrowser {
    /// Read only this level on demand, keeping millions of individual files out of memory.
    /// Directory totals come from the completed scan; symlinks are never traversed.
    public static func contents(of path: String, report: StorageReport,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [StorageEntry] {
        let directories = Dictionary(report.children(of: path).map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
        var result: [StorageEntry] = []
        for url in urls {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { continue }
            let type = info.st_mode & S_IFMT
            guard type == S_IFREG || type == S_IFDIR else { continue }
            let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec))
            if var measured = directories[url.path] {
                measured.modifiedAt = modified
                result.append(measured)
            } else {
                result.append(StorageEntry(path: url.path, allocatedBytes: type == S_IFDIR ? 0 : Int64(info.st_blocks) * 512,
                    logicalBytes: type == S_IFDIR ? 0 : Int64(info.st_size), fileCount: type == S_IFDIR ? 0 : 1,
                    isDirectory: type == S_IFDIR, advice: StorageAdvice.classify(path: url.path, home: home.path),
                    modifiedAt: modified, isMeasured: type != S_IFDIR))
            }
        }
        return StorageSort.size.sorted(result)
    }
}
