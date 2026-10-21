import SwiftUI
#if canImport(CleanerCore)
import CleanerCore
#endif

struct StorageReportView: View {
    @Bindable var model: CleanerModel
    let inspect: (StorageEntry) -> Void
    let explore: (StorageEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let main = model.insights?.mainContributor {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LE PRINCIPAL RESPONSABLE REPÉRÉ").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.mint)
                    Text("\(main.name) occupe \(ByteSize.string(main.allocatedBytes)).")
                        .font(.system(size: 25, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    if let disk = model.disk, disk.total > 0 {
                        Text("Soit \(StorageInsights.capacityShare(main.allocatedBytes, capacity: disk.total)) de la capacité du disque, d’après les blocs alloués.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Text(main.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    Button("Comprendre ce dossier") { explore(main) }.buttonStyle(PrimaryButtonStyle())
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Ce qui prend de la place").font(.system(size: 19, weight: .semibold))
                Text("Projets, applications et données repérés automatiquement. Les lignes ci-dessous ne se recouvrent pas ; le dossier principal ci-dessus peut les contenir.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                VStack(spacing: 0) {
                    HStack {
                        Text("RESPONSABLE")
                        Spacer()
                        Text("SUR LE DISQUE")
                    }.font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.muted).padding(16)
                    ForEach(Array((model.insights?.findings ?? []).prefix(20))) { finding in
                        Rectangle().fill(Palette.line).frame(height: 1)
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Button(finding.title) { explore(finding.entry) }
                                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                Text(finding.action).font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 10)
                            Text(ByteSize.string(finding.entry.allocatedBytes)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.mint)
                            Button { inspect(finding.entry) } label: { Image(systemName: "info.circle") }
                                .buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Détails de \(finding.title)")
                        }.padding(16)
                    }
                    if model.insights?.findings.isEmpty != false {
                        Text("Aucun responsable majeur identifié parmi les fichiers accessibles. Explorez les catégories et vérifiez la couverture du scan.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).padding(20)
                    }
                }.panel()
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Répartition des fichiers").font(.system(size: 19, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.storageCategories) { total in
                        Button { model.category = .files(total.category) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: total.category.symbol).font(.system(size: 20)).foregroundStyle(Palette.mint).frame(width: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(total.category.title).font(.system(size: 12, weight: .medium))
                                    Text("\(total.fileCount.formatted()) fichiers").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Text(ByteSize.string(total.bytes)).font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                            }.padding(16).panel()
                        }.buttonStyle(.plain)
                    }
                }
                Text("Classement par type et emplacement. Chaque fichier appartient à une seule catégorie ; cela ne détermine pas s’il est supprimable.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
    }
}
