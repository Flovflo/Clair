import Foundation

public struct StorageFinding: Identifiable, Sendable {
    public var id: String { entry.path }
    public let entry: StorageEntry
    public let title: String
    public let explanation: String
    public let action: String
}

public struct StorageInsights: Sendable {
    public let mainContributor: StorageEntry?
    public let findings: [StorageFinding]

    public init(report: StorageReport, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let byPath = Dictionary(report.directories.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var projects: [String: StorageEntry] = [:]
        var candidates: [StorageFinding] = []
        func add(_ entry: StorageEntry, _ title: String, _ explanation: String, _ action: String) {
            candidates.append(StorageFinding(entry: entry, title: title, explanation: explanation, action: action))
        }
        for entry in report.directories where entry.allocatedBytes >= 100_000_000 {
            let name = entry.name
            let parent = (entry.path as NSString).deletingLastPathComponent
            let owner = (parent as NSString).lastPathComponent
            if name == ".artifacts" || name == ".worktrees" {
                if let project = byPath[parent] { projects[parent] = project }
                if name == ".artifacts" {
                    add(entry, "\(owner) · artefacts", "Sorties de builds, tests et archives possibles. Ce dossier peut aussi contenir des fichiers de signature ou de distribution.", "Ouvrir les sous-dossiers et retirer seulement les sorties identifiées.")
                } else {
                    add(entry, "\(owner) · worktrees Git", "Copies de travail du projet, avec des modifications potentiellement non enregistrées.", "Vérifier chaque worktree avec Git avant de le retirer.")
                }
            } else if name == "DerivedData" {
                add(entry, "Xcode · fichiers de compilation", "Résultats de compilation et index de Xcode, généralement recréables.", "Fermer les compilations, puis choisir les projets à nettoyer.")
            } else if name == "CoreSimulator" {
                add(entry, "Xcode · simulateurs", "Appareils simulés, leurs données et systèmes installés.", "Retirer les appareils et runtimes inutilisés depuis Xcode.")
            } else if parent == "/System/Library/AssetsV2" && name.contains("SimulatorRuntime") {
                add(entry, "Xcode · systèmes des simulateurs", "Systèmes iOS, tvOS ou autres téléchargés pour les simulateurs.", "Retirer les runtimes inutilisés depuis les réglages de Xcode.")
            } else if name == "powerlog" && entry.path.hasPrefix("/private/var/") {
                add(entry, "macOS · journaux powerlog", "Journaux de performance d’un service système ; leur volume ne prouve pas qu’ils sont supprimables.", "Examiner la croissance et le service concerné ; ne pas effacer la base active.")
            } else if name == "Downloads" && entry.path == home.path + "/Downloads" {
                add(entry, "Téléchargements", "Installateurs, archives et fichiers téléchargés. Leur utilité dépend de leur contenu.", "Trier par taille ou ancienneté, puis examiner les copies inutiles.")
            } else if [".build", "node_modules"].contains(name) {
                if let project = byPath[parent] { projects[parent] = project }
                add(entry, "\(owner) · \(name == ".build" ? "compilation Swift" : "dépendances JavaScript")", "Fichiers générés ou dépendances, à distinguer du code source voisin.", "Vérifier les sources et le manifeste avant nettoyage.")
            } else if entry.path == home.path + "/Library/Developer/Xcode/Archives" {
                add(entry, "Xcode · archives distribuables", "Versions compilées et symboles utiles pour distribuer et diagnostiquer les applications.", "Conserver les versions encore utilisées et leurs symboles.")
            } else if ["/.mtplx/models", "/.ollama/models", "/.lmstudio/models", "/.cache/huggingface/hub"].contains(where: { entry.path == home.path + $0 }) {
                add(entry, "\(owner == ".mtplx" ? "MTPLX" : owner == ".ollama" ? "Ollama" : owner == ".lmstudio" ? "LM Studio" : "Hugging Face") · modèles IA", "Bibliothèque locale de modèles ; certains fichiers peuvent être partagés ou entraînés personnellement.", "Conserver les modèles utilisés et retirer les autres via leur gestionnaire.")
            } else if ["com.apple.wallpaper", "com.apple.idleassetsd"].contains(name) &&
                        [home.path + "/Library/Application Support", "/Library/Application Support"].contains(parent) {
                add(entry, "Apple · fonds d’écran et économiseurs", "Ressources graphiques téléchargées par macOS.", "Gérer les fonds d’écran dans les réglages système.")
            } else if parent == home.path + "/Library/Application Support" {
                add(entry, name, "Données de l’application : contenus téléchargés, bases et réglages possibles. Ce n’est pas un cache par défaut.", "Examiner les sous-dossiers et utiliser le gestionnaire de stockage de l’application.")
            } else if parent == home.path + "/Library/Caches" || parent == home.path + "/.cache" {
                add(entry, "Cache · \(name)", "Données temporaires possibles ; des téléchargements utiles peuvent aussi être présents.", "Fermer l’application et vérifier le contenu avant de sélectionner ce cache.")
            } else if name.localizedCaseInsensitiveContains("DesktopPicture") || name.localizedCaseInsensitiveContains("IdleScreenSaver") {
                add(entry, "Apple · fonds d’écran et économiseurs", "Ressources graphiques téléchargées par macOS.", "Gérer les fonds d’écran dans les réglages système.")
            } else if name.hasSuffix(".app") && (parent == "/Applications" || parent == home.path + "/Applications") {
                add(entry, (name as NSString).deletingPathExtension, "Application installée, avec ses ressources internes.", "Désinstaller l’application entière si elle n’est plus utilisée.")
            }
        }
        // Prefer named, actionable roots over their nested implementation folders.
        var selected: [StorageFinding] = []
        func priority(_ finding: StorageFinding) -> Int {
            if [".artifacts", ".worktrees"].contains(finding.entry.name) { return 0 }
            if ["models", "hub", "DerivedData", "CoreSimulator", "powerlog", "Downloads", "Archives"].contains(finding.entry.name) { return 1 }
            if [".build", "node_modules"].contains(finding.entry.name) { return 3 }
            return 2
        }
        for candidate in candidates.sorted(by: { priority($0) == priority($1) ? $0.entry.allocatedBytes > $1.entry.allocatedBytes : priority($0) < priority($1) }) {
            if !selected.contains(where: { candidate.id == $0.id || candidate.id.hasPrefix($0.id + "/") || $0.id.hasPrefix(candidate.id + "/") }) {
                selected.append(candidate)
            }
        }
        // Unknown large folders deserve a place in the report too; do not hide them behind known rules.
        let generic = Set(["Users", "Library", "Documents", "Desktop", "Projet", "Projects", "Application Support", "Caches", "System", "private", "var"])
        for entry in report.directories.sorted(by: { $0.allocatedBytes > $1.allocatedBytes }) where entry.allocatedBytes >= 5_000_000_000 {
            guard entry.path.hasPrefix(home.path + "/"), entry.path.split(separator: "/").count >= 4,
                  !generic.contains(entry.name),
                  !selected.contains(where: { entry.path == $0.id || entry.path.hasPrefix($0.id + "/") || $0.id.hasPrefix(entry.path + "/") }) else { continue }
            selected.append(StorageFinding(entry: entry, title: entry.name,
                explanation: "Dossier volumineux détecté indépendamment des règles de nettoyage.",
                action: "Explorer les sous-dossiers et les gros fichiers pour identifier leur rôle."))
        }
        findings = selected.sorted { $0.entry.allocatedBytes > $1.entry.allocatedBytes }
        mainContributor = (Array(projects.values) + findings.map(\.entry)).max { $0.allocatedBytes < $1.allocatedBytes }
    }

    public static func capacityShare(_ bytes: Int64, capacity: Int64) -> String {
        guard capacity > 0 else { return "—" }
        let percentage = Double(bytes) / Double(capacity) * 100
        return percentage < 1 ? "moins de 1 %" : "environ \(Int(percentage)) %"
    }

    public func markdown(report: StorageReport, diskCapacity: Int64? = nil) -> String {
        func escaped(_ text: String) -> String { text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        var lines = ["# Rapport de stockage — Clair", "", "Analyse du \(report.completedAt.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(Locale(identifier: "fr_FR")))).", ""]
        if let main = mainContributor {
            let share = diskCapacity.flatMap { $0 > 0 ? " (\(Self.capacityShare(main.allocatedBytes, capacity: $0)) de la capacité du disque)" : nil } ?? ""
            lines.append("**Le principal dossier repéré est \(escaped(main.name)) : \(ByteSize.string(main.allocatedBytes))\(share).**")
            lines.append("")
        }
        lines += ["| Ce qui prend de la place | Taille | Piste de tri |", "| --- | ---: | --- |"]
        for finding in findings.prefix(30) {
            lines.append("| \(escaped(finding.title)) | **\(ByteSize.string(finding.entry.allocatedBytes))** | \(escaped(finding.action)) |")
        }
        lines += ["", "## Répartition des fichiers", "", "| Catégorie | Taille | Fichiers |", "| --- | ---: | ---: |"]
        for total in report.categories { lines.append("| \(total.category.title) | \(ByteSize.string(total.bytes)) | \(total.fileCount) |") }
        lines += ["", "## Détails des responsables", ""]
        for finding in findings.prefix(30) { lines += ["- **\(escaped(finding.title))** — `\(finding.id)`", "  \(finding.explanation)"] }
        lines += ["", "## Couverture et limites", "", "\(report.fileCount) fichiers parcourus ; \(report.issueCount) chemins inaccessibles. Périmètre : `\(report.rootPath)`.",
                  "Tailles estimées de blocs alloués, pas une promesse d’espace récupérable. Clones APFS et compression peuvent modifier le gain réel. Ne pas additionner un projet avec ses sous-dossiers. La date de modification n’est pas une preuve d’inutilisation. Aucun fichier supprimé par ce rapport."]
        return lines.joined(separator: "\n") + "\n"
    }
}
