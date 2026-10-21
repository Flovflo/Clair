import Foundation
import Darwin

public enum StorageKind: String, Sendable, Codable {
    case cache, model, installer, application, applicationData, personal, system, simulator
}

public struct StorageAdvice: Sendable, Codable {
    public let kind: StorageKind
    public let title: String
    public let explanation: String

    public static func classify(path: String, home: String) -> StorageAdvice {
        func advice(_ kind: StorageKind, _ title: String, _ text: String) -> StorageAdvice {
            StorageAdvice(kind: kind, title: title, explanation: text)
        }
        if path.contains("/CoreSimulator") || path.contains("SimulatorRuntime") {
            return advice(.simulator, "Gérer dans Xcode", "Les simulateurs et runtimes inutilisés peuvent être retirés depuis Xcode. Ne supprimez pas leurs fichiers internes manuellement.")
        }
        let inHome = path == home || path.hasPrefix(home + "/")
        if !inHome && ["/System", "/private", "/usr", "/bin", "/sbin", "/Library"].contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return advice(.system, "À conserver · système", "Fichiers gérés par macOS ou par des services installés. La taille seule ne permet pas de conclure qu’ils sont supprimables. Utilisez les réglages ou l’outil propriétaire.")
        }
        if path == "/Applications" || path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") {
            return advice(.application, "Désinstaller si inutilisée", "Retirez l’application avec son désinstalleur ou le Finder si vous ne l’utilisez plus. Ne supprimez pas des morceaux de son contenu.")
        }
        guard inHome else {
            return advice(.system, "Vérifier le propriétaire", "Ce dossier est en dehors de votre espace personnel. Conservez-le tant que son rôle et son propriétaire ne sont pas identifiés.")
        }
        if ["/.cache/huggingface", "/.lmstudio/models", "/.cache/lm-studio/models", "/.ollama/models", "/.mtplx/models"].contains(where: { path.hasPrefix(home + $0 + "/") || path == home + $0 }) || ["gguf", "safetensors"].contains((path as NSString).pathExtension.lowercased()) {
            return advice(.model, "Modèle · à votre choix", "Retirable si vous n’en avez plus besoin et disposez d’une source ou d’une sauvegarde. Préférez le gestionnaire de modèles ; les poids peuvent être partagés ou issus d’un entraînement personnel.")
        }
        if path.contains("/Xcode/Archives/") || path.hasSuffix("/Xcode/Archives") {
            return advice(.personal, "Archives · à conserver si utiles", "Ces versions compilées et leurs symboles peuvent servir à distribuer l’app ou diagnostiquer des crashs. Sauvegardez-les avant retrait.")
        }
        if path.contains("/Xcode/DerivedData") || path.split(separator: "/").contains("node_modules") || path.split(separator: "/").contains(".build") {
            return advice(.cache, "Fichiers générés · recréables", "Ces fichiers de compilation ou dépendances sont généralement recréables. Fermez les outils et vérifiez que vous avez les sources et dépendances nécessaires.")
        }
        if path.hasPrefix(home + "/Library/Caches/") || path == home + "/Library/Caches" || path.hasPrefix(home + "/.cache/") || path == home + "/.cache" {
            return advice(.cache, "Cache · vérifier le contenu", "Un cache peut être recréable, mais aussi contenir des téléchargements et sessions utiles. Utilisez le nettoyage de l’application concernée et évitez de retirer tout le dossier à l’aveugle.")
        }
        if path.hasPrefix(home + "/Library/") || path == home + "/Library" {
            return advice(.applicationData, "Données d’apps · à conserver", "Peut contenir messages, sauvegardes, bases de données et réglages. Utilisez l’app concernée pour faire le tri ; ce n’est pas un cache par défaut.")
        }
        if ["dmg", "pkg", "iso"].contains((path as NSString).pathExtension.lowercased()) {
            return advice(.installer, "Installateur · candidat au retrait", "Peut être retiré si l’installation est terminée, l’image n’est plus montée et vous n’avez plus besoin de cette copie. Vérifiez son contenu auparavant.")
        }
        return advice(.personal, "Fichier personnel · à votre choix", "Documents, projets et fichiers personnels : leur taille ne dit pas s’ils sont inutiles. Ouvrez-les et conservez une sauvegarde avant de décider.")
    }
}

public struct StorageEntry: Identifiable, Sendable, Codable {
    public var id: String { path }
    public var name: String { path == "/" ? "Macintosh HD" : (path as NSString).lastPathComponent }
    public let path: String
    public var allocatedBytes: Int64
    public var logicalBytes: Int64
    public var fileCount: Int
    public let isDirectory: Bool
    public let advice: StorageAdvice
    public var modifiedAt: Date? = nil
    public var isMeasured: Bool = true
    public var sharesStorage: Bool = false
}

public struct StorageProgress: Sendable {
    public let path: String
    public let files: Int
    public let bytes: Int64
    public var categories: [CategoryTotal] = []
    public var updatedAt: Date = .now
}

public struct StorageReport: Sendable {
    public let rootPath: String
    public let directories: [StorageEntry]
    public let largeFiles: [StorageEntry]
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int
    public let issues: [ScanIssue]
    public let issueCount: Int
    public let completedAt: Date
    public var indexURL: URL? = nil
    public var categories: [CategoryTotal] = []

    public func children(of path: String) -> [StorageEntry] {
        directories.filter { $0.path != path && ($0.path as NSString).deletingLastPathComponent == path }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }
    }
}

/// Walks directory names with readdir and metadata with lstat. Never opens file contents,
/// follows symbolic links, or crosses mounted volumes below each explicit root.
public struct StorageScanner: Sendable {
    private let roots: [String]
    private let rootPath: String
    private let home: String
    private let largeFileThreshold: Int64
    private let largeFileLimit: Int
    private let indexURL: URL?

    public init(root: URL? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                largeFileThreshold: Int64 = 100_000_000, largeFileLimit: Int = 300, indexURL: URL? = nil) {
        self.indexURL = indexURL
        func canonical(_ url: URL) -> String {
            guard let pointer = realpath(url.path, nil) else { return url.path }
            defer { free(pointer) }
            return String(cString: pointer)
        }
        self.home = canonical(home)
        self.largeFileThreshold = largeFileThreshold
        self.largeFileLimit = max(1, largeFileLimit)
        if let root {
            let path = canonical(root)
            roots = [path]
            rootPath = path
        } else {
            roots = ["/System/Volumes/Data", "/System", "/usr", "/bin", "/sbin"]
            rootPath = "/"
        }
    }

    // Internal initializer exercises overlapping physical roots without scanning the real Mac in tests.
    init(scanRoots: [URL], home: URL) {
        indexURL = nil
        roots = scanRoots.map(\.path)
        rootPath = "/"
        self.home = home.path
        largeFileThreshold = 1
        largeFileLimit = 300
    }

    private struct Tally {
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var files: Int = 0
        mutating func add(_ other: Tally) {
            allocated += other.allocated; logical += other.logical; files += other.files
        }
    }

    private struct Inode: Hashable { let device: dev_t; let number: ino_t }

    public func scan(isCancelled: @escaping @Sendable () -> Bool = { false },
                     progress: @Sendable (StorageProgress) -> Void = { _ in }) throws -> StorageReport {
        let index = try indexURL.map { try StorageIndexWriter(destination: $0, home: home) }
        var indexDirectory: String?
        if let parent = indexURL?.deletingLastPathComponent(), let resolved = realpath(parent.path, nil) {
            indexDirectory = String(cString: resolved); free(resolved)
        }
        var categoryTotals: [FileCategory: CategoryTotal] = [:]
        let tree = MetadataWalker(roots: roots)
        var pending: [String: Tally] = [:]
        var directories: [String: StorageEntry] = [:]
        var largeFiles: [StorageEntry] = []
        var hardLinks: Set<Inode> = []
        var visitedDirectories: Set<Inode> = []
        var total = Tally()
        var countedFiles = 0
        var countedBytes: Int64 = 0
        var issueCount = 0
        var issues: [ScanIssue] = []
        var lastProgress = Date.distantPast

        func display(_ raw: String) -> String {
            let prefix = "/System/Volumes/Data"
            if raw == prefix { return "/" }
            return raw.hasPrefix(prefix + "/") ? String(raw.dropFirst(prefix.count)) : raw
        }
        func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
        func addIssue(_ path: String, _ message: String) {
            issueCount += 1
            if issues.count < 500 { issues.append(ScanIssue(path: display(path), message: message)) }
        }
        func storeDirectory(_ raw: String, _ tally: Tally, modified: Date? = nil) {
            let path = display(raw)
            if var existing = directories[path] {
                existing.allocatedBytes += tally.allocated
                existing.logicalBytes += tally.logical
                existing.fileCount += tally.files
                directories[path] = existing
            } else {
                directories[path] = StorageEntry(path: path, allocatedBytes: tally.allocated, logicalBytes: tally.logical,
                                                  fileCount: tally.files, isDirectory: true, advice: StorageAdvice.classify(path: path, home: home), modifiedAt: modified)
            }
        }

        while let entry = try tree.next(isCancelled: isCancelled) {
            if isCancelled() { throw CancellationError() }
            let raw = entry.path
            let info = entry.info
            if info == FTS_D {
                // APFS firmlinks can expose Data again below /System/Volumes on the
                // same device, so device boundaries alone are insufficient.
                let excludedMount = rootPath == "/" && ["/System/Volumes", "/Volumes", "/dev", "/Network"].contains(display(raw))
                let directoryStat = entry.metadata
                let identity = Inode(device: directoryStat.st_dev, number: directoryStat.st_ino)
                if raw == indexDirectory || excludedMount || !visitedDirectories.insert(identity).inserted {
                    tree.skipDescendants()
                    continue
                }
                pending[raw] = Tally(allocated: Int64(directoryStat.st_blocks) * 512)
            } else if info == FTS_DP {
                guard let tally = pending.removeValue(forKey: raw) else { continue }
                storeDirectory(raw, tally, modified: Date(timeIntervalSince1970: Double(entry.metadata.st_mtimespec.tv_sec)))
                if entry.level == 0 { total.add(tally) }
                else { pending[parent(raw), default: Tally()].add(tally) }
            } else if info == FTS_F {
                let stat = entry.metadata
                let alreadyCounted = stat.st_nlink > 1 && !hardLinks.insert(Inode(device: stat.st_dev, number: stat.st_ino)).inserted
                // Keep every path searchable while charging shared data only once.
                let bytes = alreadyCounted ? 0 : Int64(stat.st_blocks) * 512
                let tally = Tally(allocated: bytes, logical: alreadyCounted ? 0 : Int64(stat.st_size), files: 1)
                if entry.level == 0 { total.add(tally) }
                else { pending[parent(raw), default: Tally()].add(tally) }
                countedFiles += 1
                countedBytes += bytes
                let displayPath = display(raw)
                let category = FileCategory.classify(path: displayPath, home: home)
                var categoryTotal = categoryTotals[category] ?? CategoryTotal(category: category, bytes: 0, fileCount: 0)
                categoryTotal.bytes += bytes; categoryTotal.fileCount += 1
                categoryTotals[category] = categoryTotal
                let modified = Date(timeIntervalSince1970: Double(stat.st_mtimespec.tv_sec))
                try index?.add(path: displayPath, allocated: bytes, logical: Int64(stat.st_size), files: 1, directory: false, modified: modified, sharesStorage: stat.st_nlink > 1)
                if bytes >= largeFileThreshold {
                    let path = display(raw)
                    largeFiles.append(StorageEntry(path: path, allocatedBytes: bytes, logicalBytes: Int64(stat.st_size), fileCount: 1,
                                                   isDirectory: false, advice: StorageAdvice.classify(path: path, home: home), modifiedAt: modified, sharesStorage: stat.st_nlink > 1))
                    if largeFiles.count > largeFileLimit * 2 {
                        largeFiles.sort { $0.allocatedBytes > $1.allocatedBytes }
                        largeFiles.removeLast(largeFiles.count - largeFileLimit)
                    }
                }
            } else if info == FTS_DNR || info == FTS_ERR || info == FTS_NS || info == FTS_DC {
                addIssue(raw, "Non analysé : " + String(cString: strerror(entry.error == 0 ? EACCES : entry.error)))
                if let tally = pending.removeValue(forKey: raw) {
                    storeDirectory(raw, tally)
                    if entry.level == 0 { total.add(tally) }
                    else { pending[parent(raw), default: Tally()].add(tally) }
                }
            }
            if Date().timeIntervalSince(lastProgress) > 0.4 {
                lastProgress = Date()
                progress(StorageProgress(path: display(raw), files: countedFiles, bytes: countedBytes, categories: categoryTotals.values.sorted { $0.bytes > $1.bytes }))
            }
        }
        largeFiles.sort { $0.allocatedBytes == $1.allocatedBytes ? $0.path < $1.path : $0.allocatedBytes > $1.allocatedBytes }
        if largeFiles.count > largeFileLimit { largeFiles.removeLast(largeFiles.count - largeFileLimit) }
        var report = StorageReport(rootPath: rootPath, directories: Array(directories.values), largeFiles: largeFiles,
                             allocatedBytes: total.allocated, logicalBytes: total.logical, fileCount: total.files,
                             issues: issues, issueCount: issueCount, completedAt: Date(), indexURL: indexURL,
                             categories: categoryTotals.values.sorted { $0.bytes > $1.bytes })
        if let index {
            for entry in directories.values {
                if isCancelled() { throw CancellationError() }
                try index.add(path: entry.path, allocated: entry.allocatedBytes, logical: entry.logicalBytes,
                              files: entry.fileCount, directory: true, modified: entry.modifiedAt)
            }
            if isCancelled() { throw CancellationError() }
            progress(StorageProgress(path: "Préparation du rapport et de la recherche…", files: countedFiles, bytes: countedBytes, categories: report.categories))
            report.categories = try index.finish(report, isCancelled: isCancelled)
        }
        return report
    }
}

/// Reading names separately avoids getattrlistbulk calls that can hang on iCloud packages.
/// A stack keeps traversal iterative, and no directory descriptor stays open between events.
private final class MetadataWalker {
    struct Entry {
        let path: String
        let level: Int
        let info: Int32
        let metadata: stat
        var error: Int32 = 0
    }
    private enum Step {
        case visit(String, Int, dev_t?)
        case children(Entry, dev_t)
        case finish(Entry)
    }
    private var stack: [Step]
    init(roots: [String]) { stack = roots.reversed().map { .visit($0, 0, nil) } }

    func skipDescendants() {
        if case .children = stack.last { stack.removeLast() }
    }

    func next(isCancelled: @Sendable () -> Bool) throws -> Entry? {
        while let step = stack.popLast() {
            if isCancelled() { throw CancellationError() }
            switch step {
            case .visit(let path, let level, let rootDevice):
                var metadata = stat()
                guard lstat(path, &metadata) == 0 else {
                    return Entry(path: path, level: level, info: FTS_NS, metadata: metadata, error: errno)
                }
                let kind = metadata.st_mode & S_IFMT
                if kind == S_IFDIR {
                    if let rootDevice, rootDevice != metadata.st_dev { continue }
                    let entry = Entry(path: path, level: level, info: FTS_D, metadata: metadata)
                    stack.append(.children(entry, rootDevice ?? metadata.st_dev))
                    return entry
                }
                if kind == S_IFREG { return Entry(path: path, level: level, info: FTS_F, metadata: metadata) }
                // Symlinks, sockets, devices and FIFOs are never followed or opened.
            case .children(let entry, let device):
                let descriptor = open(entry.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard descriptor >= 0 else {
                    return Entry(path: entry.path, level: entry.level, info: FTS_DNR, metadata: entry.metadata, error: errno)
                }
                guard let directory = fdopendir(descriptor) else {
                    let failure = errno; close(descriptor)
                    return Entry(path: entry.path, level: entry.level, info: FTS_DNR, metadata: entry.metadata, error: failure)
                }
                var names: [String] = []
                var failure: Int32 = 0
                do {
                    defer { closedir(directory) }
                    while true {
                        if isCancelled() { throw CancellationError() }
                        errno = 0
                        guard let item = readdir(directory) else { failure = errno; break }
                        let name = withUnsafePointer(to: &item.pointee.d_name) {
                            $0.withMemoryRebound(to: CChar.self, capacity: Int(item.pointee.d_namlen) + 1) { String(cString: $0) }
                        }
                        if name != "." && name != ".." { names.append(name) }
                    }
                }
                if failure != 0 {
                    return Entry(path: entry.path, level: entry.level, info: FTS_DNR, metadata: entry.metadata, error: failure)
                }
                stack.append(.finish(entry))
                for name in names.reversed() {
                    let path = entry.path == "/" ? "/" + name : entry.path + "/" + name
                    stack.append(.visit(path, entry.level + 1, device))
                }
            case .finish(let entry):
                return Entry(path: entry.path, level: entry.level, info: FTS_DP, metadata: entry.metadata)
            }
        }
        return nil
    }
}
