import Foundation
import SQLite3
import Darwin

public struct InventoryQuery: Sendable {
    public enum Scope: Sendable { case files, directories, folder(String) }
    public var scope: Scope = .files
    public var category: FileCategory?
    public var search = ""
    public var minimumBytes: Int64 = 0
    public var modifiedBefore: Date?
    public var sort: StorageSort = .size
    public var limit = 100
    public var offset = 0
    public init() {}
}

public struct InventoryPage: Sendable {
    public let entries: [StorageEntry]
    public let totalCount: Int
    public let totalBytes: Int64
}

private struct SavedScan: Codable {
    let root: String
    let home: String
    let allocated: Int64
    let logical: Int64
    let files: Int
    let issues: [ScanIssue]
    let issueCount: Int
    let date: Date
}

private final class Database {
    var handle: OpaquePointer?
    init(_ url: URL, writable: Bool) throws {
        let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Ouverture impossible"
            sqlite3_close(handle); handle = nil
            throw IndexError.failure(message)
        }
        sqlite3_busy_timeout(handle, 3000)
    }
    deinit { sqlite3_close(handle) }
    func exec(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        if status == SQLITE_INTERRUPT { throw CancellationError() }
        guard status == SQLITE_OK else { throw error }
    }
    var error: IndexError { .failure(String(cString: sqlite3_errmsg(handle))) }
    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error }
        return statement
    }
}

private enum IndexError: LocalizedError {
    case failure(String)
    var errorDescription: String? {
        switch self { case .failure(let detail): "Index local : " + detail }
    }
}

private func bind(_ value: String, to statement: OpaquePointer, at position: Int32) {
    _ = value.withCString { sqlite3_bind_text(statement, position, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
}
private func string(_ statement: OpaquePointer, _ column: Int32) -> String {
    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
}
private func folded(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
}

/// Each query opens its own read-only connection. Replacing a completed index is atomic.
public struct StorageIndex: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Clair/inventory.sqlite")
    }
    public func query(_ request: InventoryQuery) throws -> InventoryPage {
        let db = try Database(url, writable: false)
        let saved = try metadata(db)
        var predicates: [String] = []
        var texts: [String] = []
        switch request.scope {
        case .files: predicates.append("is_dir = 0")
        case .directories: predicates.append("is_dir = 1")
        case .folder(let parent): predicates.append("parent = ? AND path <> ?"); texts += [parent, parent]
        }
        if let category = request.category { predicates.append("category = ?"); texts.append(category.rawValue) }
        if !request.search.isEmpty {
            predicates.append("search LIKE ? ESCAPE '\\'")
            let value = folded(request.search).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            texts.append("%" + value + "%")
        }
        predicates.append("allocated >= \(max(0, request.minimumBytes))")
        if let before = request.modifiedBefore { predicates.append("modified > 0 AND modified < \(before.timeIntervalSince1970)") }
        let clause = predicates.joined(separator: " AND ")
        func prepare(_ sql: String) throws -> OpaquePointer {
            let statement = try db.prepare(sql)
            for (n, value) in texts.enumerated() { bind(value, to: statement, at: Int32(n + 1)) }
            return statement
        }
        let count = try prepare("SELECT count(*), coalesce(sum(allocated),0) FROM entries WHERE \(clause)")
        defer { sqlite3_finalize(count) }
        guard sqlite3_step(count) == SQLITE_ROW else { throw db.error }
        let total = Int(sqlite3_column_int64(count, 0))
        let bytes = sqlite3_column_int64(count, 1)
        let ordering: String
        switch request.sort { case .size: ordering = "allocated DESC, path"; case .name: ordering = "name COLLATE NOCASE, path"; case .recent: ordering = "modified DESC, path" }
        let statement = try prepare("SELECT path,allocated,logical,file_count,is_dir,modified,\(try sharedColumn(db)) FROM entries WHERE \(clause) ORDER BY \(ordering) LIMIT \(max(1,min(request.limit,10000))) OFFSET \(max(0,request.offset))")
        defer { sqlite3_finalize(statement) }
        var entries: [StorageEntry] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            entries.append(entry(statement, home: saved.home))
            status = sqlite3_step(statement)
        }
        if status == SQLITE_INTERRUPT { throw CancellationError() }
        guard status == SQLITE_DONE else { throw db.error }
        return InventoryPage(entries: entries, totalCount: total, totalBytes: bytes)
    }
    public func restoreReport() throws -> StorageReport? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let db = try Database(url, writable: false)
        let saved = try metadata(db)
        let statement = try db.prepare("SELECT path,allocated,logical,file_count,is_dir,modified,\(try sharedColumn(db)) FROM entries WHERE is_dir = 1")
        defer { sqlite3_finalize(statement) }
        var directories: [StorageEntry] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { directories.append(entry(statement, home: saved.home)); status = sqlite3_step(statement) }
        if status == SQLITE_INTERRUPT { throw CancellationError() }
        guard status == SQLITE_DONE else { throw db.error }
        var query = InventoryQuery(); query.minimumBytes = 100_000_000; query.limit = 300
        let large = try self.query(query).entries
        return StorageReport(rootPath: saved.root, directories: directories, largeFiles: large, allocatedBytes: saved.allocated,
                             logicalBytes: saved.logical, fileCount: saved.files, issues: saved.issues, issueCount: saved.issueCount,
                             completedAt: saved.date, indexURL: url, categories: try categories(db))
    }
    private func entry(_ statement: OpaquePointer, home: String) -> StorageEntry {
        let path = string(statement, 0)
        let timestamp = sqlite3_column_double(statement, 5)
        return StorageEntry(path: path, allocatedBytes: sqlite3_column_int64(statement, 1), logicalBytes: sqlite3_column_int64(statement, 2),
            fileCount: Int(sqlite3_column_int64(statement, 3)), isDirectory: sqlite3_column_int(statement, 4) != 0,
            advice: StorageAdvice.classify(path: path, home: home), modifiedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil, sharesStorage: sqlite3_column_int(statement, 6) != 0)
    }
    private func sharedColumn(_ db: Database) throws -> String {
        // Earlier inventories remain readable until the next scan replaces them.
        let statement = try db.prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw db.error }
        return sqlite3_column_int(statement, 0) >= 2 ? "shared" : "0"
    }
    private func metadata(_ db: Database) throws -> SavedScan {
        let statement = try db.prepare("SELECT value FROM metadata WHERE key = 'scan'")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let data = string(statement, 0).data(using: .utf8) else { throw IndexError.failure("Analyse incomplète") }
        return try JSONDecoder().decode(SavedScan.self, from: data)
    }
    fileprivate func categories(_ db: Database) throws -> [CategoryTotal] {
        let statement = try db.prepare("SELECT category,sum(allocated),count(*) FROM entries WHERE is_dir = 0 GROUP BY category ORDER BY sum(allocated) DESC")
        defer { sqlite3_finalize(statement) }
        var result: [CategoryTotal] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let category = FileCategory(rawValue: string(statement, 0)) {
                result.append(CategoryTotal(category: category, bytes: sqlite3_column_int64(statement, 1), fileCount: Int(sqlite3_column_int64(statement, 2))))
            }
            status = sqlite3_step(statement)
        }
        if status == SQLITE_INTERRUPT { throw CancellationError() }
        guard status == SQLITE_DONE else { throw db.error }
        return result
    }
}

/// Single-thread writer owned only by a scan task. A failed/cancelled scan never replaces the previous index.
final class StorageIndexWriter {
    private let destination: URL
    private let staging: URL
    private var db: Database?
    private var insert: OpaquePointer?
    private let home: String
    init(destination: URL, home: String) throws {
        self.destination = destination; self.home = home
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        staging = destination.deletingLastPathComponent().appendingPathComponent("scan-\(UUID().uuidString).sqlite")
        let database = try Database(staging, writable: true); db = database
        chmod(staging.path, 0o600)
        try database.exec("PRAGMA journal_mode=DELETE; PRAGMA synchronous=NORMAL; PRAGMA user_version=2; CREATE TABLE entries(path TEXT PRIMARY KEY,parent TEXT,name TEXT,search TEXT,allocated INTEGER,logical INTEGER,file_count INTEGER,is_dir INTEGER,category TEXT,modified REAL,shared INTEGER); CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT); BEGIN IMMEDIATE;")
        insert = try database.prepare("INSERT OR REPLACE INTO entries VALUES(?,?,?,?,?,?,?,?,?,?,?)")
    }
    deinit {
        if let insert { sqlite3_finalize(insert) }
        db = nil
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.removeItem(atPath: staging.path + "-journal")
    }
    func add(path: String, allocated: Int64, logical: Int64, files: Int, directory: Bool, modified: Date? = nil, sharesStorage: Bool = false) throws {
        guard let db, let insert else { throw IndexError.failure("Index fermé") }
        sqlite3_reset(insert); sqlite3_clear_bindings(insert)
        bind(path, to: insert, at: 1)
        bind((path as NSString).deletingLastPathComponent, to: insert, at: 2)
        bind((path as NSString).lastPathComponent, to: insert, at: 3)
        bind(folded(path), to: insert, at: 4)
        sqlite3_bind_int64(insert, 5, allocated); sqlite3_bind_int64(insert, 6, logical)
        sqlite3_bind_int64(insert, 7, Int64(files)); sqlite3_bind_int(insert, 8, directory ? 1 : 0)
        bind(FileCategory.classify(path: path, home: home).rawValue, to: insert, at: 9)
        sqlite3_bind_double(insert, 10, modified?.timeIntervalSince1970 ?? 0)
        sqlite3_bind_int(insert, 11, sharesStorage ? 1 : 0)
        guard sqlite3_step(insert) == SQLITE_DONE else { throw db.error }
    }
    func finish(_ report: StorageReport, isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> [CategoryTotal] {
        guard let db else { throw IndexError.failure("Index fermé") }
        if isCancelled() { throw CancellationError() }
        let cancellation = IndexCancellation(check: isCancelled)
        sqlite3_progress_handler(db.handle, 1000, { context in
            guard let context else { return 0 }
            return Unmanaged<IndexCancellation>.fromOpaque(context).takeUnretainedValue().check() ? 1 : 0
        }, Unmanaged.passUnretained(cancellation).toOpaque())
        defer {
            sqlite3_progress_handler(db.handle, 0, nil, nil)
            withExtendedLifetime(cancellation) {}
        }
        let saved = SavedScan(root: report.rootPath, home: home, allocated: report.allocatedBytes, logical: report.logicalBytes,
            files: report.fileCount, issues: report.issues, issueCount: report.issueCount, date: report.completedAt)
        let value = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        let metadata = try db.prepare("INSERT INTO metadata VALUES('scan',?)")
        bind(value, to: metadata, at: 1)
        let status = sqlite3_step(metadata); sqlite3_finalize(metadata)
        if status == SQLITE_INTERRUPT { throw CancellationError() }
        guard status == SQLITE_DONE else { throw db.error }
        try db.exec("COMMIT; CREATE INDEX by_parent ON entries(parent); CREATE INDEX by_size ON entries(is_dir,allocated DESC); CREATE INDEX by_category ON entries(category,is_dir,allocated DESC); CREATE INDEX by_date ON entries(is_dir,modified DESC);")
        if isCancelled() { throw CancellationError() }
        let totals = try StorageIndex(url: staging).categories(db)
        if let insert { sqlite3_finalize(insert); self.insert = nil }
        // All writes are committed before rename; existing readers keep their snapshot.
        self.db = nil
        if isCancelled() { throw CancellationError() }
        guard rename(staging.path, destination.path) == 0 else { throw IndexError.failure(String(cString: strerror(errno))) }
        return totals
    }
}

private final class IndexCancellation {
    let check: @Sendable () -> Bool
    init(check: @escaping @Sendable () -> Bool) { self.check = check }
}
