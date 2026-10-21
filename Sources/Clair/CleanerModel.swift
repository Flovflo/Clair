import SwiftUI
import AppKit
import Observation
import Darwin
#if canImport(CleanerCore)
import CleanerCore
#endif

enum Category: Hashable, Identifiable {
    case fullDisk, overview, source(SourceKind), files(FileCategory)
    var id: String { title }
    var title: String {
        switch self {
        case .fullDisk: "Tout le Mac"
        case .overview: "Éléments à examiner"
        case .source(let source): source.title
        case .files(let category): category.title
        }
    }
    var isStorage: Bool {
        switch self { case .fullDisk, .files: true; default: false }
    }
    var symbol: String {
        switch self {
        case .fullDisk: "internaldrive"
        case .overview: "square.grid.2x2"
        case .source(let source): source.symbol
        case .files(let category): category.symbol
        }
    }
}

struct DetectedGroup: Identifiable {
    let source: SourceKind
    let count: Int
    let bytes: Int64
    var id: String { source.rawValue }
}

@MainActor @Observable
final class CleanerModel {
    var items: [CleanItem] = []
    var issues: [ScanIssue] = []
    var disk: DiskSpace?
    var selection: Set<String> = []
    var category: Category = .fullDisk
    var search = ""
    var isScanning = false
    var isCleaning = false
    var isFullScanning = false
    var isPreparing = false
    var isRestoring = false
    var diskAccessConfirmed = false
    var showsSetup = false
    var isRelaunching = false
    var setupError: String?
    @ObservationIgnored private var didRestore = false
    var explorerPath = "/"
    var storageRoot: URL?
    var storageReport: StorageReport?
    var storageProgress: StorageProgress?
    var progress = ""
    var lastScan: Date?
    var notice: String?
    var cleanupResult: CleanupResult?
    @ObservationIgnored private var worker: Task<ScanReport, Error>?
    @ObservationIgnored private var storageWorker: Task<StorageReport, Error>?
    @ObservationIgnored private let scanner = DiskScanner()

    var isBusy: Bool { isScanning || isCleaning || isFullScanning || isPreparing || isRestoring }
    var selectedItems: [CleanItem] { CleanupSelection.topLevel(items.filter { selection.contains($0.id) }) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.allocatedBytes } }
    var totalBytes: Int64 { CleanupSelection.topLevel(items).reduce(0) { $0 + $1.allocatedBytes } }
    var modelBytes: Int64 { items.filter(\.source.isModel).reduce(0) { $0 + $1.allocatedBytes } }
    var xcodeBytes: Int64 { items.filter(\.source.isXcode).reduce(0) { $0 + $1.allocatedBytes } }
    var quickItems: [CleanItem] { items.filter { $0.isQuickCleanEligible(at: .now) } }
    var quickBytes: Int64 { quickItems.reduce(0) { $0 + $1.allocatedBytes } }

    var storageCategories: [CategoryTotal] { isFullScanning ? storageProgress?.categories ?? [] : storageReport?.categories ?? [] }
    var fileCategory: FileCategory? {
        if case .files(let value) = category { return value }
        return nil
    }
    private(set) var insights: StorageInsights?

    func restoreInventory() async {
        guard !didRestore else { return }
        didRestore = true
        refreshDiskSpace()
        isRestoring = true
        defer { isRestoring = false }
        do {
            let report = try await Task.detached(priority: .utility) { try StorageIndex(url: StorageIndex.defaultURL).restoreReport() }.value
            if let report {
                let insights = await Task.detached(priority: .utility) { StorageInsights(report: report) }.value
                storageReport = report
                self.insights = insights
                explorerPath = report.rootPath
                storageRoot = report.rootPath == "/" ? nil : URL(fileURLWithPath: report.rootPath)
            }
        } catch { notice = "Le précédent index ne peut pas être ouvert. Relancez l’analyse pour le reconstruire." }
    }

    func exportReport() {
        guard let report = storageReport, let insights else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Rapport-stockage-Clair.md"
        panel.message = "Enregistrer le diagnostic et les chemins concernés sur ce Mac."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try insights.markdown(report: report, diskCapacity: self.disk?.total).write(to: url, atomically: true, encoding: .utf8) }
            catch { self.notice = "Export impossible : " + error.localizedDescription }
        }
    }

    var detectedGroups: [DetectedGroup] {
        Dictionary(grouping: CleanupSelection.topLevel(items), by: \.source).map { source, values in
            DetectedGroup(source: source, count: values.count, bytes: values.reduce(0) { $0 + $1.allocatedBytes })
        }.sorted { $0.bytes > $1.bytes }
    }

    var visibleItems: [CleanItem] {
        items.filter { item in
            let inCategory = category == .overview || category == .source(item.source)
            return inCategory && (search.isEmpty || (item.name + item.source.title + item.url.path).localizedStandardContains(search))
        }
    }

    func showDiskAccessSetup() {
        checkDiskAccess()
        setupError = nil
        showsSetup = true
    }

    func configureOnLaunch() {
        checkDiskAccess()
        if !diskAccessConfirmed { showsSetup = true }
    }

    func completeSetup() {
        checkDiskAccess()
        guard diskAccessConfirmed else {
            setupError = "L’autorisation n’est pas encore détectée. Activez Clair dans les réglages, puis utilisez Relancer Clair."
            return
        }
        showsSetup = false
        setupError = nil
        startScan(fullDisk: true)
    }

    func relaunchAfterSetup() {
        guard !isBusy, !isRelaunching else { return }
        UserDefaults.standard.set(true, forKey: "resumeFullScanAfterAccess")
        isRelaunching = true
        setupError = nil
        // Relaunch only after this process exits. Launching a second instance first
        // can leave Launch Services waiting forever for the original application.
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", #"attempt=0; while /bin/kill -0 "$1" 2>/dev/null; do attempt=$((attempt + 1)); [ "$attempt" -ge 100 ] && exit 1; /bin/sleep 0.1; done; exec /usr/bin/open "$2""#, "clair-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
            UserDefaults.standard.synchronize()
            showsSetup = false
            // Close the setup sheet before asking AppKit to terminate. SwiftUI's
            // modal session can otherwise keep the application alive indefinitely.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
                // This explicit restart is allowed only while no scan or cleanup
                // is running; all persistent inventory writes are already committed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Darwin.exit(EXIT_SUCCESS) }
            }
        } catch {
            isRelaunching = false
            setupError = "La relance a échoué : " + error.localizedDescription
        }
    }

    func openFullDiskAccess() {
        notice = "Dans Accès complet au disque, activez Clair, puis quittez et rouvrez l’app. Si Clair est absent, ajoutez-le avec + depuis \(Bundle.main.bundleURL.path)."
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshDiskSpace() {
        disk = scanner.diskSpace()
        checkDiskAccess()
    }

    func checkDiskAccess() {
        // macOS has no public FDA status API. Probe opening a protected resource
        // without reading its contents, changing TCC, or requesting per-folder grants.
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY | O_CLOEXEC)
        diskAccessConfirmed = descriptor >= 0
        if descriptor >= 0 { close(descriptor) }
    }

    func resumeAuthorizedScan() {
        checkDiskAccess()
        guard didRestore, !isRestoring else { return }
        if diskAccessConfirmed && !isBusy && UserDefaults.standard.bool(forKey: "resumeFullScanAfterAccess") {
            showsSetup = false
            startScan(fullDisk: true)
        }
    }

    func startScan(fullDisk: Bool = false) {
        guard !isBusy else { return }
        if fullDisk {
            category = .fullDisk
            startStorageScan()
            return
        }
        isScanning = true
        progress = "Préparation de l’analyse…"
        notice = nil
        selection.removeAll()
        let scanner = scanner
        let task = Task.detached(priority: .userInitiated) { [self] in
            try scanner.scan(isCancelled: { Task.isCancelled }, progress: { label in
                Task { @MainActor in self.progress = label }
            })
        }
        worker = task
        Task {
            defer { isScanning = false; worker = nil }
            do {
                let report = try await task.value
                items = report.items
                issues = report.issues
                disk = report.disk
                lastScan = report.completedAt
            } catch is CancellationError {
                notice = "Analyse annulée. Aucun fichier n’a été modifié."
            } catch { notice = error.localizedDescription }
        }
    }

    func cancelScan() { worker?.cancel(); storageWorker?.cancel(); progress = "Annulation…" }

    func startStorageScan(root: URL? = nil) {
        guard !isBusy else { return }
        if root == nil {
            checkDiskAccess()
            guard diskAccessConfirmed else {
                UserDefaults.standard.set(true, forKey: "resumeFullScanAfterAccess")
                showDiskAccessSetup()
                notice = "Terminez la configuration de Clair pour lancer l’analyse de tout le Mac."
                return
            }
            UserDefaults.standard.set(false, forKey: "resumeFullScanAfterAccess")
        }
        notice = nil
        isFullScanning = true
        storageProgress = nil
        storageRoot = root
        let task = Task.detached(priority: .userInitiated) { [self] in
            try StorageScanner(root: root, indexURL: StorageIndex.defaultURL).scan(isCancelled: { Task.isCancelled }, progress: { value in
                Task { @MainActor in self.storageProgress = value }
            })
        }
        storageWorker = task
        Task {
            defer { isFullScanning = false; storageWorker = nil }
            do {
                let report = try await task.value
                let analysis = await Task.detached(priority: .utility) { StorageInsights(report: report) }.value
                storageReport = report
                insights = analysis
                explorerPath = storageReport?.rootPath ?? "/"
                disk = scanner.diskSpace()
                isFullScanning = false
                startScan()
            } catch is CancellationError {
                notice = "Analyse complète annulée. Aucun fichier n’a été modifié."
            } catch { notice = error.localizedDescription }
        }
    }
    func selectQuickClean() { selection = Set(quickItems.map(\.id)) }

    func prepareForCleanup(_ entry: StorageEntry) async -> Bool {
        guard !isBusy else { return false }
        checkDiskAccess()
        guard diskAccessConfirmed else { openFullDiskAccess(); return false }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let scanner = scanner
            let candidate = try await Task.detached(priority: .userInitiated) {
                try scanner.inspect(URL(fileURLWithPath: entry.path))
            }.value
            items.removeAll { $0.id == candidate.id }
            items.append(candidate)
            items.sort { $0.allocatedBytes > $1.allocatedBytes }
            selection.insert(candidate.id)
            notice = "\(candidate.name) ajouté à la sélection. Vérifiez-la avant de confirmer le nettoyage."
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func toggle(_ item: CleanItem) {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
    }

    func blockingApps(for chosen: [CleanItem]) -> [String] {
        let needsXcode = chosen.contains { $0.source.isXcode || $0.source == .projectBuild }
        let needsLM = chosen.contains { $0.source == .lmStudio || $0.source == .legacyLMStudio }
        let needsOllama = chosen.contains { $0.source == .ollama }
        return NSWorkspace.shared.runningApplications.compactMap { app in
            let id = (app.bundleIdentifier ?? "").lowercased()
            let name = app.localizedName ?? ""
            if (needsXcode && id == "com.apple.dt.xcode") || (needsLM && (id.contains("lmstudio") || name.lowercased().contains("lm studio"))) || (needsOllama && (id.contains("ollama") || name.lowercased().contains("ollama"))) { return name }
            return nil
        }
    }

    func clean(_ chosen: [CleanItem]) {
        guard !isBusy, !chosen.isEmpty else { return }
        checkDiskAccess()
        guard diskAccessConfirmed else { openFullDiskAccess(); return }
        let blockers = blockingApps(for: chosen)
        guard blockers.isEmpty else {
            notice = "Fermez \(blockers.joined(separator: ", ")) puis réessayez."
            return
        }
        isCleaning = true
        progress = "Vérification de la sélection…"
        notice = nil
        let service = TrashService(scanner: scanner)
        Task {
            let result = await Task.detached(priority: .userInitiated) { [self] in
                service.clean(chosen, progress: { label in
                    Task { @MainActor in self.progress = label }
                })
            }.value
            let moved = Set(result.moved.map(\.item.id))
            items.removeAll { item in moved.contains(where: { item.id == $0 || item.id.hasPrefix($0 + "/") }) }
            selection.formIntersection(Set(items.map(\.id)))
            issues.append(contentsOf: result.failures)
            disk = scanner.diskSpace()
            cleanupResult = result
            if !result.moved.isEmpty {
                storageReport = nil; insights = nil
                try? FileManager.default.removeItem(at: StorageIndex.defaultURL)
            }
            isCleaning = false
            if result.moved.isEmpty {
                notice = "Aucun élément déplacé. Consultez les détails des erreurs, puis relancez l’analyse."
            } else {
                notice = "\(ByteSize.string(result.bytes)) dans la Corbeille. Videz-la dans le Finder pour libérer l’espace."
            }
        }
    }
}
