import SwiftUI
import AppKit
#if canImport(CleanerCore)
import CleanerCore
#endif

struct ConfirmationSheet: View {
    var model: CleanerModel
    let items: [CleanItem]
    @Environment(\.dismiss) private var dismiss
    @State private var toolsStopped = false

    private var bytes: Int64 { items.reduce(0) { $0 + $1.allocatedBytes } }
    private var sources: [SourceKind] { SourceKind.allCases.filter { source in items.contains { $0.source == source } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "trash.circle").font(.system(size: 36, weight: .light)).foregroundStyle(Palette.mint)
            Text("On fait de la place ?").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("\(items.count) élément(s) · \(ByteSize.string(bytes)) seront déplacés dans la Corbeille.")
                .font(.system(size: 13))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(ByteSize.string(item.allocatedBytes)).foregroundStyle(Palette.muted)
                        }
                        .font(.system(size: 12))
                    }
                    Divider().padding(.vertical, 4)
                    ForEach(sources, id: \.self) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(source.isRegenerableCache ? Palette.mint : Palette.amber)
                            Text(source.caution).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(16)
            }
            .frame(maxHeight: 240).panel()
            Toggle("J’ai fermé les outils, serveurs et téléchargements concernés.", isOn: $toolsStopped)
                .font(.system(size: 12)).toggleStyle(.checkbox)
            Text("L’espace sera libéré après vidage de la Corbeille dans le Finder. Vous pouvez y récupérer les fichiers avant de la vider.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Déplacer dans la Corbeille") { model.clean(items); dismiss() }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!toolsStopped).opacity(toolsStopped ? 1 : 0.4)
            }
        }
        .padding(30).frame(width: 540).background(Palette.background)
    }
}

struct ItemDetailSheet: View {
    let item: CleanItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: item.source.symbol).font(.system(size: 26)).foregroundStyle(Palette.mint)
                Spacer()
                Text(item.source.title).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Text(item.name).font(.system(size: 22, weight: .semibold, design: .rounded)).textSelection(.enabled)
            HStack(spacing: 30) {
                metric("SUR LE DISQUE", ByteSize.string(item.allocatedBytes))
                metric("TAILLE LOGIQUE", ByteSize.string(item.logicalBytes))
                metric("FICHIERS", item.fileCount.formatted())
            }
            Text(item.url.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .foregroundStyle(Palette.muted).padding(14).frame(maxWidth: .infinity, alignment: .leading).panel()
            Text(item.source.caution).font(.system(size: 12)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
            Text("Dernière modification : \(item.latestModification.formatted(date: .long, time: .shortened)).")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack {
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Fermer") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }.padding(30).frame(width: 560).background(Palette.background)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded))
        }
    }
}

struct IssuesSheet: View {
    let issues: [ScanIssue]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quelques éléments à vérifier").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Les éléments ci-dessous n’ont pas été analysés ou nettoyés. Aucun accès administrateur n’est demandé.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(issue.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            Text(issue.message).font(.system(size: 12)).foregroundStyle(Palette.amber)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 300)
            HStack { Spacer(); Button("Fermer") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction) }
        }.padding(30).frame(width: 560).background(Palette.background)
    }
}


struct SetupSheet: View {
    @Bindable var model: CleanerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "internaldrive.fill.badge.checkmark").font(.system(size: 36)).foregroundStyle(Palette.mint)
                Spacer()
                Text("CONFIGURATION DE CLAIR").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted)
            }
            Text("Configurons l’accès au disque.").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("Pour mesurer les projets, caches et données d’applications, Clair a besoin de l’accès complet au disque. L’analyse reste locale et ne supprime aucun fichier.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 16) {
                Label(model.diskAccessConfirmed ? "Accès complet détecté" : "1. Autoriser Clair dans macOS", systemImage: model.diskAccessConfirmed ? "checkmark.circle.fill" : "lock.shield")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.mint)
                if !model.diskAccessConfirmed {
                    Text("Dans Confidentialité et sécurité → Accès complet au disque, activez l’interrupteur Clair. Seul macOS peut accorder cette autorisation.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir les réglages d’accès") {
                        model.openFullDiskAccess()
                    }.buttonStyle(PrimaryButtonStyle())
                    DisclosureGroup("Clair n’apparaît pas dans la liste ?") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cliquez sur + dans les réglages et ajoutez cette application :")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                            HStack {
                                Text(Bundle.main.bundleURL.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                                Spacer()
                                Button("Afficher") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                                    .buttonStyle(QuietButtonStyle())
                            }
                        }.padding(.top, 8)
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).panel()
            VStack(alignment: .leading, spacing: 12) {
                Label(model.diskAccessConfirmed ? "2. Lancer le diagnostic" : "2. Relancer pour appliquer l’accès", systemImage: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                Text(model.diskAccessConfirmed ? "L’analyse couvrira le disque de démarrage. Les catégories et le rapport seront construits à partir des fichiers trouvés." : "Une fois l’interrupteur activé, relancez Clair ici. L’app vérifiera l’accès et démarrera l’analyse automatiquement.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if model.diskAccessConfirmed {
                    HStack {
                        Button("Analyser tout le Mac") { model.completeSetup() }
                            .buttonStyle(PrimaryButtonStyle()).disabled(model.isBusy || model.isRelaunching)
                        Button(model.isRelaunching ? "Relance…" : "Relancer Clair") { model.relaunchAfterSetup() }
                            .buttonStyle(QuietButtonStyle()).disabled(model.isBusy || model.isRelaunching)
                    }
                } else {
                    HStack {
                        Button(model.isRelaunching ? "Relance…" : "Relancer Clair") { model.relaunchAfterSetup() }
                            .buttonStyle(PrimaryButtonStyle()).disabled(model.isBusy || model.isRelaunching)
                        Button("Vérifier l’accès") { model.checkDiskAccess(); if !model.diskAccessConfirmed { model.setupError = "Accès non détecté. Si vous venez de l’activer, relancez Clair." } }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
            }
            if let error = model.setupError { Text(error).font(.system(size: 11)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("Un accès global, aucun dossier à choisir.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button(model.storageReport == nil ? "Plus tard" : "Consulter le dernier rapport") { dismiss() }
                    .buttonStyle(QuietButtonStyle()).disabled(model.isRelaunching)
            }
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 600, height: 640).background(Palette.background)
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                model.checkDiskAccess()
                if model.diskAccessConfirmed { model.setupError = nil }
            }
    }
}
