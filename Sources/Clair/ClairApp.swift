import SwiftUI

@main
struct ClairApp: App {
    @State private var model = CleanerModel()

    var body: some Scene {
        Window("Clair", id: "main") {
            DashboardView(model: model)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(minWidth: 960, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Nettoyage") {
                Button("Analyser tout le Mac") { model.category = .fullDisk; model.startScan(fullDisk: true) }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isBusy)
                Button("Sélectionner les anciens caches") { model.selectQuickClean() }
                    .disabled(model.isBusy || model.items.isEmpty)
                Button("Tout désélectionner") { model.selection.removeAll() }
                    .disabled(model.isBusy)
            }
        }
    }
}
