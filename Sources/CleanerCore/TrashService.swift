import Foundation

public struct MovedItem: Sendable {
    public let item: CleanItem
    public let trashURL: URL
}

public struct CleanupResult: Sendable {
    public var moved: [MovedItem] = []
    public var failures: [ScanIssue] = []
    public var bytes: Int64 { moved.reduce(0) { $0 + $1.item.allocatedBytes } }
}

public enum CleanupSelection {
    /// An ancestor already contains its descendants; count and move it only once.
    public static func topLevel(_ items: [CleanItem]) -> [CleanItem] {
        var result: [CleanItem] = []
        for item in items.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            if !result.contains(where: { item.id == $0.id || item.url.path.hasPrefix($0.url.path + "/") }) {
                result.append(item)
            }
        }
        return result.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }
}

public struct TrashService: Sendable {
    private let scanner: DiskScanner
    private let moveToTrash: @Sendable (URL) throws -> URL

    public init(scanner: DiskScanner = DiskScanner(), moveToTrash: @escaping @Sendable (URL) throws -> URL = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL? ?? url
    }) {
        self.scanner = scanner
        self.moveToTrash = moveToTrash
    }

    public func clean(_ items: [CleanItem], progress: @Sendable (String) -> Void = { _ in }) -> CleanupResult {
        var result = CleanupResult()
        for item in CleanupSelection.topLevel(items) {
            progress(item.name)
            do {
                try scanner.validate(item)
                let destination = try moveToTrash(item.url)
                result.moved.append(MovedItem(item: item, trashURL: destination))
            } catch {
                result.failures.append(ScanIssue(path: item.url.path, message: error.localizedDescription))
            }
        }
        return result
    }
}
