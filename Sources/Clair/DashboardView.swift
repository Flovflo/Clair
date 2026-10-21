import SwiftUI
import AppKit
#if canImport(CleanerCore)
import CleanerCore
#endif

enum PresentedSheet: Identifiable {
    case detail(CleanItem), confirmation([CleanItem]), issues
    var id: String {
        switch self {
        case .detail(let item): "detail-" + item.id
        case .confirmation: "confirmation"
        case .issues: "issues"
        }
    }
}

struct DashboardView: View {
    @Bindable var model: CleanerModel
    @State private var sheet: PresentedSheet?

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if let notice = model.notice { noticeBanner(notice) }
                        if model.category.isStorage {
                            StorageExplorerView(model: model)
                        } else {
                            OverviewCard(model: model)
                            categoryCards
                            fileSection
                        }
                    }
                    .padding(.horizontal, 32).padding(.top, 42).padding(.bottom, 24)
                }
                if !model.category.isStorage { cleanupBar }
            }
        }
        .background(Palette.background)
        .tint(Palette.mint)
        .sheet(item: $sheet) { item in
            switch item {
            case .detail(let file): ItemDetailSheet(item: file)
            case .confirmation(let chosen): ConfirmationSheet(model: model, items: chosen)
            case .issues: IssuesSheet(issues: model.issues)
            }
        }
        .sheet(isPresented: $model.showsSetup) { SetupSheet(model: model) }
        .task { model.configureOnLaunch(); await model.restoreInventory(); model.resumeAuthorizedScan() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.resumeAuthorizedScan() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("UN PEU D’AIR POUR VOTRE MAC")
                    .font(.system(size: 10, weight: .semibold)).tracking(2.2).foregroundStyle(Palette.muted)
                Text(model.category == .fullDisk ? "Où va votre espace ?" : model.category == .overview ? "Faites de la place." : model.category.title)
                    .font(.system(size: 31, weight: .semibold, design: .rounded)).tracking(-0.7)
            }
            Spacer()
            if model.isScanning || model.isFullScanning {
                Button { model.cancelScan() } label: { Label("Annuler", systemImage: "xmark") }
                    .buttonStyle(QuietButtonStyle())
            } else {
                Button { model.startScan(fullDisk: true) } label: { Label("Analyser", systemImage: "arrow.clockwise") }
                    .buttonStyle(QuietButtonStyle()).disabled(model.isBusy)
                    .help("Relancer l’analyse · ⌘R")
            }
        }
    }

    private var categoryCards: some View {
        HStack(spacing: 12) {
            ForEach(Array(model.detectedGroups.prefix(2))) { group in
                SummaryCard(title: group.source.title, subtitle: "\(group.count) élément(s) détecté(s)", symbol: group.source.symbol,
                            bytes: group.bytes, color: group.source.isModel ? Palette.amber : Palette.blue,
                            active: model.category == .source(group.source)) { model.category = .source(group.source) }
            }
            SummaryCard(title: "Nettoyage rapide", subtitle: "Caches inactifs depuis 7 jours", symbol: "sparkles", bytes: model.quickBytes, color: Palette.mint, active: false) {
                model.category = .overview
                model.search = ""
                model.selectQuickClean()
            }
            .disabled(model.isBusy)
        }
    }

    private var fileSection: some View {
        let visible = model.visibleItems
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("À examiner").font(.system(size: 18, weight: .semibold))
                Text("\(visible.count)")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.06), in: Capsule())
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Rechercher…", text: $model.search).textFieldStyle(.plain)
                        .accessibilityLabel("Rechercher un modèle ou un cache")
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Effacer la recherche")
                    }
                }
                .font(.system(size: 12)).padding(9).frame(width: 185)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line))
            }

            VStack(spacing: 0) {
                HStack {
                    Text("ÉLÉMENT").padding(.leading, 48)
                    Spacer()
                    Text("TAILLE ↓").frame(width: 100, alignment: .trailing).padding(.trailing, 45)
                }
                .font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.muted)
                .padding(.horizontal, 18).padding(.vertical, 13)
                Rectangle().fill(Palette.line).frame(height: 1)

                if model.isScanning {
                    statusPlaceholder(symbol: "waveform.path", title: "Analyse en cours", detail: "\(model.progress) · vos fichiers restent en place.")
                } else if visible.isEmpty {
                    statusPlaceholder(symbol: model.search.isEmpty ? "checkmark.seal" : "magnifyingglass", title: model.search.isEmpty ? "Rien à nettoyer ici" : "Aucun résultat", detail: model.search.isEmpty ? "Les emplacements standards ne contiennent aucun élément accessible." : "Essayez un autre nom ou une autre catégorie.")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { item in
                            FileRow(item: item, selected: model.selection.contains(item.id), disabled: model.isBusy,
                                    toggle: { model.toggle(item) }, detail: { sheet = .detail(item) })
                            if item.id != visible.last?.id {
                                Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 65)
                            }
                        }
                    }
                }
            }
            .panel()

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                Text("Tailles estimées sur le disque. Les modèles et archives restent décochés. Explorez Tout le Mac pour examiner les autres dossiers.")
                Spacer(minLength: 0)
                if !model.issues.isEmpty {
                    Button("\(model.issues.count) avertissement(s)") { sheet = .issues }
                        .buttonStyle(.plain).foregroundStyle(Palette.amber)
                }
            }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private func statusPlaceholder(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            if model.isScanning { ProgressView().controlSize(.small) }
            else { Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Palette.mint) }
            Text(title).font(.system(size: 15, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(42)
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Palette.mint)
            Text(notice).font(.system(size: 12)).textSelection(.enabled)
            Spacer()
            Button { model.notice = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Fermer le message")
        }
        .padding(14).background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var cleanupBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(spacing: 18) {
                Image(systemName: "trash").font(.system(size: 22, weight: .light)).foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(ByteSize.string(model.selectedBytes)).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("sélectionnés").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Text(model.isCleaning ? model.progress : "\(model.selectedItems.count) élément(s) · déplacement dans la Corbeille")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                if !model.selection.isEmpty {
                    Button("Désélectionner") { model.selection.removeAll() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted).disabled(model.isBusy)
                }
                Button { sheet = .confirmation(model.selectedItems) } label: {
                    HStack(spacing: 9) {
                        if model.isCleaning { ProgressView().controlSize(.mini) }
                        Text(model.isCleaning ? "Nettoyage…" : "Nettoyer la sélection")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.selection.isEmpty || model.isBusy)
                .opacity(model.selection.isEmpty || model.isBusy ? 0.4 : 1)
            }
            .padding(.horizontal, 32).padding(.vertical, 18)
            .background(Palette.sidebar)
        }
    }
}

struct FileRow: View {
    let item: CleanItem
    let selected: Bool
    let disabled: Bool
    let toggle: () -> Void
    let detail: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Toggle("Sélectionner \(item.name)", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden().disabled(disabled)
            Image(systemName: item.source.symbol)
                .font(.system(size: 17)).foregroundStyle(item.source.isModel ? Palette.amber : Palette.blue)
                .frame(width: 34, height: 36)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(item.source.title)
                    Text("·")
                    Text(item.latestModification, style: .relative)
                }
                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if item.source.isRegenerableCache {
                Text("Recréable").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.mint.opacity(0.85))
                    .padding(.horizontal, 7).padding(.vertical, 4).background(Palette.mint.opacity(0.055), in: Capsule())
            }
            Text(ByteSize.string(item.allocatedBytes)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .frame(width: 87, alignment: .trailing)
            Button(action: detail) { Image(systemName: "ellipsis").frame(width: 26, height: 26).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
                .accessibilityLabel("Détails de \(item.name)")
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(selected ? Palette.mint.opacity(0.035) : .clear)
        .contextMenu {
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("Voir les détails", action: detail)
        }
    }
}
