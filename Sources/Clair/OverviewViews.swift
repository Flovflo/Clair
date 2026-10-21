import SwiftUI
import AppKit
#if canImport(CleanerCore)
import CleanerCore
#endif

struct SidebarView: View {
    @Bindable var model: CleanerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Palette.mint).frame(width: 36, height: 36)
                    Image(systemName: "sparkle").font(.system(size: 23, weight: .medium)).foregroundStyle(Palette.background)
                }
                Text("clair.").font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-1.3)
            }
            .padding(.bottom, 9)
            Text("Moins de fichiers. Plus d’espace.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Text("MON ESPACE").font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(Palette.muted.opacity(0.7))
                .padding(.top, 44).padding(.bottom, 13)
            ScrollView {
                VStack(spacing: 6) {
                    navigationRow(.fullDisk, bytes: model.storageReport?.allocatedBytes)
                    navigationRow(.overview, bytes: model.totalBytes)
                    if !model.storageCategories.isEmpty {
                        Text("RÉPARTITION DU DISQUE").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20).padding(.bottom, 8)
                        ForEach(model.storageCategories) { total in
                            navigationRow(.files(total.category), bytes: total.bytes)
                        }
                    }
                    if !model.detectedGroups.isEmpty {
                        Text("NETTOYAGE À EXAMINER").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20).padding(.bottom, 8)
                        ForEach(model.detectedGroups) { group in
                            navigationRow(.source(group.source), bytes: group.bytes)
                        }
                    } else {
                        Text(model.isFullScanning || model.isScanning ? "Recherche des candidats au nettoyage…" : model.storageReport == nil ? "Les catégories apparaîtront après l’analyse." : "Relancez l’analyse pour actualiser les candidats au nettoyage.")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 16)
                    }
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 20, weight: .light)).foregroundStyle(Palette.mint)
                Text("Votre Mac, vos fichiers.").font(.system(size: 12, weight: .medium))
                Text("Tout reste en local.\nVous choisissez ce qui part.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 16) {
                Button { model.showDiskAccessSetup() } label: { Label("Accès complet au disque…", systemImage: "lock.shield") }
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(url) }
                } label: { Label("Stockage macOS", systemImage: "externaldrive") }
                Button {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                } label: { Label("Ouvrir la Corbeille", systemImage: "trash") }
            }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.muted)
            .padding(.top, 24).padding(.leading, 6)
            HStack(spacing: 6) {
                Circle().fill(Palette.mint).frame(width: 5, height: 5)
                Text("100 % local").font(.system(size: 9))
                Spacer()
                Text("v1.0").font(.system(size: 9))
            }
            .foregroundStyle(Palette.muted.opacity(0.6)).padding(.top, 30)
        }
        .padding(.horizontal, 20).padding(.top, 56).padding(.bottom, 22)
        .frame(width: 245).background(Palette.sidebar)
    }
    private func navigationRow(_ category: Category, bytes: Int64?) -> some View {
        Button { model.category = category; model.search = "" } label: {
            HStack(spacing: 10) {
                Image(systemName: category.symbol).frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    if let bytes { Text(ByteSize.string(bytes)).font(.system(size: 10)).monospacedDigit() }
                }
                Spacer(minLength: 0)
                if model.category == category { Circle().fill(Palette.mint).frame(width: 5, height: 5) }
            }
            .foregroundStyle(model.category == category ? Palette.mint : Palette.muted)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(model.category == category ? Palette.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(model.category == category ? .isSelected : [])
    }

}

struct OverviewCard: View {
    var model: CleanerModel

    var body: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Palette.mint).frame(width: 5, height: 5)
                    Text(model.isScanning ? "ANALYSE EN COURS" : "ESPACE À EXAMINER")
                        .tracking(1.6)
                }
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.mint)
                Text(model.isScanning && model.lastScan == nil ? "—" : ByteSize.string(model.totalBytes))
                    .font(.system(size: 51, weight: .light, design: .rounded)).tracking(-2).monospacedDigit()
                    .padding(.top, 10).padding(.bottom, 6)
                Text("Un Mac plus léger, l’esprit plus libre.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.82))
                HStack(spacing: 7) {
                    if model.isScanning {
                        ProgressView().controlSize(.mini)
                        Text(model.progress)
                    } else if let last = model.lastScan {
                        Image(systemName: "checkmark.circle")
                        Text("Analyse à \(last.formatted(date: .omitted, time: .shortened)) · \(model.items.count) éléments")
                    } else { Text("Lancez une analyse pour commencer") }
                }
                .font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 23)
            }
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.075), lineWidth: 10)
                    if let disk = model.disk, disk.total > 0 {
                        Circle().trim(from: 0, to: min(1, CGFloat(disk.used) / CGFloat(disk.total)))
                            .stroke(Palette.mint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 4) {
                        Image(systemName: "internaldrive").font(.system(size: 16, weight: .light)).foregroundStyle(Palette.muted).padding(.bottom, 2)
                        Text(model.disk.map { ByteSize.string($0.available) } ?? "—")
                            .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("disponibles").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 145, height: 145)
                .accessibilityElement(children: .combine)
                Text(model.disk.map { "Disque interne · \(ByteSize.string($0.total))" } ?? "Disque du Mac")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            .padding(.trailing, 12)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(red: 0.135, green: 0.18, blue: 0.15), Palette.panel], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.mint.opacity(0.13)))
    }
}

struct SummaryCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let bytes: Int64
    let color: Color
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(color).font(.system(size: 15))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 3)
                    Text(ByteSize.string(bytes)).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(subtitle).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .panel()
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(active ? color.opacity(0.6) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(ByteSize.string(bytes)), \(subtitle)")
    }
}
