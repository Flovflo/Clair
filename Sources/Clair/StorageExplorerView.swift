import SwiftUI
import AppKit
#if canImport(CleanerCore)
import CleanerCore
#endif

private enum StorageTab: String, CaseIterable {
    case report = "Rapport", files = "Fichiers", largestFolders = "Dossiers lourds", folders = "Explorer", advice = "Pistes de tri"
}

struct StorageExplorerView: View {
    @Bindable var model: CleanerModel
    @State private var tab: StorageTab = .report
    @State private var entries: [StorageEntry] = []
    @State private var totalCount = 0
    @State private var totalBytes: Int64 = 0
    @State private var queryError: String?
    @State private var loading = false
    @State private var sort: StorageSort = .size
    @State private var search = ""
    @State private var minimumBytes: Int64 = 100_000_000
    @State private var ageDays = 0
    @State private var page = 0
    @State private var detail: StorageEntry?
    @State private var showsIssues = false
    private let pageSize = 100
    private var report: StorageReport? { model.storageReport }
    private var queryKey: String {
        "\(report?.completedAt.timeIntervalSince1970 ?? 0)|\(tab)|\(model.explorerPath)|\(model.fileCategory?.rawValue ?? "")|\(search)|\(sort)|\(minimumBytes)|\(ageDays)|\(page)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            summary
            if model.isFullScanning || model.isRestoring { progress }
            if let report, !model.isFullScanning {
                coverage(report)
                HStack {
                    Picker("Vue du stockage", selection: $tab) {
                        ForEach(StorageTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Button { model.exportReport() } label: { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(QuietButtonStyle()).help("Exporter le rapport Markdown")
                }
                if tab != .advice {
                    HStack {
                        TextField(tab == .folders ? "Filtrer ce dossier…" : "Rechercher dans tous les chemins…", text: $search)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("Rechercher dans l’inventaire")
                        if tab != .report {
                            Picker("Tri", selection: $sort) {
                                ForEach(StorageSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.frame(width: 170)
                        }
                    }
                }
                if tab == .report {
                    StorageReportView(model: model, inspect: { detail = $0 }, explore: { openFolder($0.path) })
                } else if tab == .advice {
                    findings
                } else {
                    browser
                }
            } else if !model.isFullScanning && !model.isRestoring {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Un diagnostic de tout votre Mac.").font(.system(size: 20, weight: .semibold))
                    Text("Fichiers cachés, projets, applications, modèles, médias et données système : le scan mesure les fichiers accessibles et prépare un rapport des principaux responsables.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    Button("Analyser tout le Mac") { model.startScan(fullDisk: true) }.buttonStyle(PrimaryButtonStyle()).disabled(model.isBusy)
                    Text(model.diskAccessConfirmed ? "Accès complet confirmé pour Clair. Aucun dossier à sélectionner. Aucun fichier n’est supprimé par l’analyse." : "Accès complet non confirmé : Clair vous accompagne pour activer l’autorisation et relancer l’app avant le scan.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading).panel()
            }
        }
        .sheet(item: $detail) { StorageDetailSheet(entry: $0, model: model) }
        .sheet(isPresented: $showsIssues) { IssuesSheet(issues: report?.issues ?? []) }
        .task(id: queryKey) { await loadResults() }
        .onChange(of: model.category) { _, category in
            search = ""; page = 0
            if case .files = category { tab = .files; minimumBytes = 0 }
            else if category == .fullDisk { tab = .report }
        }
        .onChange(of: report?.completedAt) { _, _ in page = 0 }
        .onChange(of: search) { _, value in page = 0; if tab == .report && !value.isEmpty { tab = .files; minimumBytes = 0 } }
        .onChange(of: tab) { _, _ in page = 0 }
        .onChange(of: minimumBytes) { _, _ in page = 0 }
        .onChange(of: ageDays) { _, _ in page = 0 }
        .onChange(of: sort) { _, _ in page = 0 }
        .onAppear { if model.fileCategory != nil { tab = .files; minimumBytes = 0 } }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                Text("VOTRE DISQUE, EN CLAIR").font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(Palette.mint)
                Text(ByteSize.string(model.isFullScanning ? model.storageProgress?.bytes ?? 0 : report?.allocatedBytes ?? 0))
                    .font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                Text("\((model.isFullScanning ? model.storageProgress?.files ?? 0 : report?.fileCount ?? 0).formatted()) fichiers parcourus")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                if let report, !model.isFullScanning {
                    Text("Analyse du \(report.completedAt.formatted(date: .abbreviated, time: .shortened)) · \(report.rootPath == "/" ? "tout le Mac" : report.rootPath)")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 9) {
                Image(systemName: "internaldrive").font(.system(size: 24)).foregroundStyle(Palette.mint)
                Text(model.disk.map { ByteSize.string($0.available) } ?? "—").font(.system(size: 26, weight: .medium, design: .rounded))
                Text("disponibles sur le disque").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Text("\(model.storageCategories.count) catégories détectées").font(.system(size: 11)).foregroundStyle(Palette.mint)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private var progress: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.isRestoring ? "Ouverture du dernier rapport…" : "Analyse approfondie de tout le Mac…").font(.system(size: 13, weight: .medium))
                Text(model.storageProgress?.path ?? "Préparation de l’inventaire local…").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                Text("Les catégories se mettent à jour pendant le scan. Les résultats restent sur ce Mac.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                if !model.isRestoring, let lastUpdate = model.storageProgress?.updatedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if context.date.timeIntervalSince(lastUpdate) > 15 {
                            Text("Cet emplacement répond lentement. Le scan attend macOS ; l’annulation peut aussi prendre un moment.")
                                .font(.system(size: 11)).foregroundStyle(Palette.amber)
                        }
                    }
                }
            }
            Spacer()
        }.padding(18).panel()
    }

    private func coverage(_ report: StorageReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.issueCount > 0 ? "lock.shield" : "checkmark.shield").foregroundStyle(Palette.amber)
            VStack(alignment: .leading, spacing: 6) {
                Text(report.issueCount > 0 ? "Analyse partielle · \(report.issueCount.formatted()) chemins inaccessibles" : "Analyse terminée sur les fichiers accessibles")
                    .font(.system(size: 12, weight: .medium))
                Text("Estimations de blocs alloués. Les clones APFS peuvent partager de l’espace. Volumes externes et instantanés exclus.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                if report.issueCount > 0 {
                    HStack {
                        Button("Voir les chemins") { showsIssues = true }
                        Button("Vérifier l’accès disque") { model.showDiskAccessSetup() }
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.mint)
                }
            }
            Spacer()
        }.padding(15).background(Palette.amber.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 14) {
            if tab != .folders {
                HStack {
                    Picker("Taille", selection: $minimumBytes) {
                        Text("Toutes").tag(Int64(0)); Text("≥ 100 Mo").tag(Int64(100_000_000))
                        Text("≥ 1 Go").tag(Int64(1_000_000_000)); Text("≥ 10 Go").tag(Int64(10_000_000_000))
                    }.frame(width: 190)
                    Picker("Modification", selection: $ageDays) {
                        Text("Toute date").tag(0); Text("Il y a + de 3 mois").tag(90)
                        Text("Il y a + de 6 mois").tag(180); Text("Il y a + d’un an").tag(365)
                    }.frame(width: 240)
                    Spacer()
                    if let category = model.fileCategory, tab == .files {
                        Text(category.title).font(.system(size: 11)).foregroundStyle(Palette.mint)
                    }
                }.font(.system(size: 11))
            } else {
                HStack(spacing: 10) {
                    Button {
                        let root = report?.rootPath ?? "/"
                        model.explorerPath = model.explorerPath == root ? root : (model.explorerPath as NSString).deletingLastPathComponent
                        page = 0
                    } label: { Image(systemName: "arrow.up") }.disabled(model.explorerPath == report?.rootPath)
                    Button("Racine") { openFolder(report?.rootPath ?? "/") }
                    Text(model.explorerPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                }.buttonStyle(QuietButtonStyle()).font(.system(size: 11))
            }
            HStack {
                Text("\(totalCount.formatted()) résultats\(tab == .files ? " · " + ByteSize.string(totalBytes) : "")")
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
            if tab == .largestFolders { Text("Les dossiers sont imbriqués : leurs tailles ne s’additionnent pas. Ouvrez un dossier pour comprendre sa répartition.").font(.system(size: 11)).foregroundStyle(Palette.amber) }
            if ageDays > 0 && tab != .folders { Text("Une ancienne modification ne prouve pas qu’un fichier n’est plus utilisé.").font(.system(size: 10)).foregroundStyle(Palette.muted) }
            if let queryError { Text(queryError).font(.system(size: 12)).foregroundStyle(Palette.amber) }
            LazyVStack(spacing: 0) {
                if entries.isEmpty && !loading { Text("Aucun résultat pour ces filtres.").font(.system(size: 13)).foregroundStyle(Palette.muted).padding(30) }
                ForEach(entries) { entry in
                    StorageRow(entry: entry, proportion: min(1, Double(entry.allocatedBytes) / Double(max(1, entries.map(\.allocatedBytes).max() ?? 1))), showsPath: tab != .folders,
                        open: { if entry.isDirectory { openFolder(entry.path) } else { detail = entry } }, detail: { detail = entry })
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
            }.panel()
            HStack {
                Button("Précédents") { page -= 1 }.disabled(page == 0 || loading)
                Spacer()
                Text("Page \(page + 1) sur \(max(1, (totalCount + pageSize - 1) / pageSize))").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Suivants") { page += 1 }.disabled((page + 1) * pageSize >= totalCount || loading)
            }.buttonStyle(QuietButtonStyle())
        }
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Des pistes fondées sur l’emplacement et le type de fichiers. Chaque suppression reste à vérifier.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            ForEach(model.insights?.findings ?? []) { finding in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(finding.title).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text(ByteSize.string(finding.entry.allocatedBytes)).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Palette.mint)
                    }
                    Text(finding.explanation).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(finding.action).font(.system(size: 12))
                    HStack {
                        Button("Explorer") { openFolder(finding.id) }
                        Button("Détails et nettoyage") { detail = finding.entry }
                    }.buttonStyle(QuietButtonStyle())
                }.padding(18).panel()
            }
        }
    }

    private func openFolder(_ path: String) {
        model.explorerPath = path; tab = .folders; page = 0; search = ""
    }

    @MainActor private func loadResults() async {
        guard let report, tab != .report, tab != .advice else { return }
        let key = queryKey
        loading = true; queryError = nil
        do {
            try await Task.sleep(for: .milliseconds(180))
            var request = InventoryQuery()
            request.sort = sort; request.search = search; request.limit = pageSize; request.offset = page * pageSize
            switch tab {
            case .files: request.category = model.fileCategory; request.minimumBytes = minimumBytes
            case .largestFolders: request.scope = .directories; request.minimumBytes = minimumBytes
            case .folders: request.scope = .folder(model.explorerPath)
            default: return
            }
            if ageDays > 0 && tab != .folders { request.modifiedBefore = Date().addingTimeInterval(-Double(ageDays) * 86400) }
            guard let url = report.indexURL else { throw NSError(domain: "Clair", code: 1, userInfo: [NSLocalizedDescriptionKey: "Relancez l’analyse pour créer l’inventaire complet."]) }
            let query = request
            let result = try await Task.detached(priority: .userInitiated) { try StorageIndex(url: url).query(query) }.value
            guard !Task.isCancelled, key == queryKey else { return }
            entries = result.entries; totalCount = result.totalCount; totalBytes = result.totalBytes
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, key == queryKey else { return }
            entries = []; totalCount = 0; queryError = error.localizedDescription
        }
        loading = false
    }
}
private struct StorageRow: View {
    let entry: StorageEntry
    let proportion: Double
    let showsPath: Bool
    let open: () -> Void
    let detail: () -> Void

    private var color: Color {
        switch entry.advice.kind {
        case .cache, .installer: Palette.mint
        case .model, .simulator, .application: Palette.amber
        default: Palette.blue
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            Button(action: open) {
                HStack(spacing: 13) {
                    Image(systemName: entry.isDirectory ? "folder" : "doc").font(.system(size: 20, weight: .light)).foregroundStyle(color).frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(showsPath ? entry.path : entry.advice.title).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 7) {
                        Text(entry.isMeasured ? (entry.sharesStorage && entry.allocatedBytes == 0 ? "Partagé" : ByteSize.string(entry.allocatedBytes)) : "À analyser").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.05))
                            Capsule().fill(color.opacity(0.7)).frame(width: max(2, 85 * proportion))
                        }.frame(width: 85, height: 3)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(entry.name), \(ByteSize.string(entry.allocatedBytes)), \(entry.advice.title)")
            Button(action: detail) { Image(systemName: "info.circle").frame(width: 24, height: 30) }
                .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Conseil pour \(entry.name)")
        }.padding(.horizontal, 17).padding(.vertical, 14)
        .contextMenu {
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
            Button("Voir les détails", action: detail)
        }
    }
}

private struct StorageDetailSheet: View {
    let entry: StorageEntry
    var model: CleanerModel
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?

    private var eligible: Bool {
        CleanupPolicy.source(for: URL(fileURLWithPath: entry.path), home: FileManager.default.homeDirectoryForCurrentUser) != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: entry.isDirectory ? "folder" : "doc").font(.system(size: 27)).foregroundStyle(Palette.mint)
                Spacer()
                Text(ByteSize.string(entry.allocatedBytes)).font(.system(size: 25, weight: .medium, design: .rounded))
            }
            Text(entry.name).font(.system(size: 22, weight: .semibold, design: .rounded)).textSelection(.enabled)
            Text(entry.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).panel()
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.advice.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.amber)
                Text(entry.advice.explanation).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            if !entry.isDirectory {
                Text(FileCategory.classify(path: entry.path, home: FileManager.default.homeDirectoryForCurrentUser.path).title)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.mint)
            }
            if entry.sharesStorage {
                Text("Lien physique : plusieurs chemins partagent ces données. Leur taille est comptée une seule fois dans l’inventaire. Retirer une seule copie ne libère pas les blocs encore utilisés par les autres liens.")
                    .font(.system(size: 12)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
            }
            if let modified = entry.modifiedAt {
                Text("Dernière modification : \(modified.formatted(date: .long, time: .shortened)).")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Text("\(entry.fileCount.formatted()) fichier(s) · taille logique \(ByteSize.string(entry.logicalBytes)).")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(Palette.amber) }
            if eligible {
                Button {
                    Task {
                        if await model.prepareForCleanup(entry) {
                            model.category = .overview
                            dismiss()
                        } else { failure = model.notice ?? "Impossible de préparer cet élément." }
                    }
                } label: {
                    HStack {
                        if model.isPreparing { ProgressView().controlSize(.small) }
                        Label(model.isPreparing ? "Vérification…" : "Ajouter au nettoyage", systemImage: "trash")
                    }
                }.buttonStyle(PrimaryButtonStyle()).disabled(model.isBusy)
                Text("Le dossier sera revérifié. Rien ne sera déplacé avant votre confirmation dans Éléments à examiner.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else {
                Text("Nettoyage direct protégé pour cet élément. Ouvrez son contenu ou utilisez l’application qui le gère.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            HStack {
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Fermer") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }.padding(30).frame(width: 560).background(Palette.background)
    }
}
