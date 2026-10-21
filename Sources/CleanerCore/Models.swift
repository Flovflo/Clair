import Foundation

public enum SourceKind: String, CaseIterable, Sendable, Codable {
    case derivedData, xcodeCache, deviceSupport, archives, huggingFace, lmStudio, legacyLMStudio, ollama
    case mtplx, userCache, downloadInstaller, projectBuild, dependencies, testResults

    public var title: String {
        switch self {
        case .derivedData: "Derived Data"
        case .xcodeCache: "Caches Xcode"
        case .deviceSupport: "Support des appareils"
        case .archives: "Archives Xcode"
        case .huggingFace: "Hugging Face"
        case .lmStudio: "LM Studio"
        case .legacyLMStudio: "LM Studio · ancien cache"
        case .ollama: "Ollama"
        case .mtplx: "MTPLX"
        case .userCache: "Caches d’applications"
        case .downloadInstaller: "Installateurs téléchargés"
        case .projectBuild: "Builds Swift"
        case .dependencies: "Dépendances JavaScript"
        case .testResults: "Résultats de tests Xcode"
        }
    }

    public var isModel: Bool { [.huggingFace, .lmStudio, .legacyLMStudio, .ollama, .mtplx].contains(self) }
    public var isXcode: Bool { [.derivedData, .xcodeCache, .deviceSupport, .archives, .testResults].contains(self) }
    var isProjectOutput: Bool { [.projectBuild, .dependencies, .testResults].contains(self) }
    public var isRegenerableCache: Bool { self == .derivedData || self == .xcodeCache }
    public var symbol: String { isModel ? "cpu" : "hammer" }
    public var caution: String {
        switch self {
        case .derivedData: "Xcode reconstruira ces fichiers à la prochaine compilation. Fermez Xcode et les compilations en cours."
        case .xcodeCache: "Ces caches seront recréés par Xcode. Fermez Xcode avant de les nettoyer."
        case .deviceSupport: "Le débogage sur ces appareils peut nécessiter de retélécharger les fichiers de support."
        case .archives: "Ces archives peuvent contenir vos versions distribuées et leurs symboles de débogage. Conservez-les si vous en avez besoin."
        case .huggingFace: "Toutes les versions locales de ce dépôt seront déplacées. Il faudra les retélécharger. Arrêtez les scripts Python, téléchargements et serveurs qui l’utilisent."
        case .lmStudio, .legacyLMStudio: "Tous les fichiers de ce modèle seront déplacés. Il faudra les retélécharger. Quittez LM Studio et son serveur."
        case .ollama: "Toute la bibliothèque Ollama sera déplacée, car les modèles partagent leurs fichiers. Quittez Ollama et arrêtez son serveur."
        case .mtplx: "Toute la bibliothèque de modèles MTPLX sera déplacée. Arrêtez MTPLX et sauvegardez vos éventuels modèles entraînés avant de confirmer."
        case .userCache: "Ce cache peut contenir des sessions ou téléchargements utiles. Quittez l’application concernée et vérifiez son contenu avant de confirmer."
        case .downloadInstaller: "Vérifiez que l’installation est terminée et que l’image disque est éjectée. L’installateur sera déplacé, pas l’application installée."
        case .projectBuild: "Les sorties Swift seront recompilées et les dépendances retéléchargées. Fermez Xcode et les compilations. Les sources voisines restent en place."
        case .dependencies: "Les dépendances seront à réinstaller avec le gestionnaire du projet. Conservez toute modification manuelle faite dans node_modules et arrêtez les serveurs."
        case .testResults: "Ces rapports de tests et leurs pièces jointes seront retirés. Les sources du projet restent en place ; sauvegardez les rapports encore utiles."
        }
    }

    var relativeRoot: String {
        switch self {
        case .derivedData: "Library/Developer/Xcode/DerivedData"
        case .xcodeCache: "Library/Caches/com.apple.dt.Xcode"
        case .deviceSupport: "Library/Developer/Xcode/iOS DeviceSupport"
        case .archives: "Library/Developer/Xcode/Archives"
        case .huggingFace: ".cache/huggingface/hub"
        case .lmStudio: ".lmstudio/models"
        case .legacyLMStudio: ".cache/lm-studio/models"
        case .ollama: ".ollama/models"
        case .mtplx: ".mtplx/models"
        case .userCache: "Library/Caches"
        case .downloadInstaller: "Downloads"
        case .projectBuild, .dependencies, .testResults: ""
        }
    }

    var depth: Int {
        switch self {
        case .ollama, .mtplx: 0
        case .lmStudio, .legacyLMStudio, .archives: 2
        default: 1
        }
    }
}

public struct CleanItem: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let source: SourceKind
    public let name: String
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let latestModification: Date
    public let fileCount: Int
    let fingerprint: String

    public func isQuickCleanEligible(at date: Date) -> Bool {
        source.isRegenerableCache && date.timeIntervalSince(latestModification) > 7 * 86400
    }
}

public struct ScanIssue: Identifiable, Sendable, Codable {
    public var id: String { path + message }
    public let path: String
    public let message: String
}

public struct DiskSpace: Sendable {
    public let total: Int64
    public let available: Int64
    public var used: Int64 { max(0, total - available) }
}

public struct ScanReport: Sendable {
    public let items: [CleanItem]
    public let issues: [ScanIssue]
    public let disk: DiskSpace?
    public let completedAt: Date
}

public enum CleanerError: LocalizedError {
    case unsafePath, changed, unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .unsafePath: "Chemin non autorisé ou lien symbolique : cet élément ne peut pas être nettoyé."
        case .changed: "Cet élément a changé depuis l’analyse. Relancez l’analyse avant de le nettoyer."
        case .unreadable(let path): "Lecture impossible : \(path). Vérifiez les autorisations du dossier."
        }
    }
}

public enum ByteSize {
    public static func string(_ bytes: Int64) -> String {
        let value = max(0, Double(bytes))
        let units = ["o", "Ko", "Mo", "Go", "To"]
        var index = 0
        var amount = value
        while amount >= 1000 && index < units.count - 1 { amount /= 1000; index += 1 }
        let number = amount.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(index > 0 && amount < 100 ? 1 : 0)))
        return "\(number) \(units[index])"
    }
}
