import Foundation

/// Mutually exclusive file classifications. These describe storage, never deletion eligibility.
public enum FileCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case models, builds, xcodeArchives, dependencies, caches, simulators, applications, appData
    case videos, images, audio, documents, archives, sourceCode, system, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .models: "Modèles IA"
        case .builds: "Compilations et tests"
        case .xcodeArchives: "Archives Xcode"
        case .dependencies: "Dépendances de projets"
        case .caches: "Caches"
        case .simulators: "Simulateurs"
        case .applications: "Applications"
        case .appData: "Données d’applications"
        case .videos: "Vidéos"
        case .images: "Images et photos"
        case .audio: "Audio"
        case .documents: "Documents"
        case .archives: "Archives et installateurs"
        case .sourceCode: "Code et projets"
        case .system: "Système et services"
        case .other: "Autres fichiers"
        }
    }
    public var symbol: String {
        switch self {
        case .models: "cpu"
        case .builds, .xcodeArchives: "hammer"
        case .dependencies: "shippingbox"
        case .caches: "arrow.triangle.2.circlepath"
        case .simulators: "iphone"
        case .applications: "app"
        case .appData: "externaldrive"
        case .videos: "film"
        case .images: "photo"
        case .audio: "waveform"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .sourceCode: "curlybraces"
        case .system: "gearshape"
        case .other: "doc"
        }
    }
    public static func classify(path: String, home: String) -> FileCategory {
        let parts = path.split(separator: "/")
        let ext = (path as NSString).pathExtension.lowercased()
        if path.contains("/CoreSimulator/") || path.contains("SimulatorRuntime") { return .simulators }
        if parts.contains(where: { $0.hasSuffix(".xcarchive") }) { return .xcodeArchives }
        if parts.contains(where: { ["node_modules", ".venv", "venv", "site-packages", "Pods", "Carthage"].contains(String($0)) }) { return .dependencies }
        if parts.contains(where: { $0 == ".build" || $0 == "DerivedData" || $0 == "__pycache__" || $0.hasSuffix(".xcresult") }) { return .builds }
        if parts.contains(where: { $0.hasSuffix(".app") }) { return .applications }
        if ["gguf", "safetensors", "ggml", "onnx", "pt", "pth", "ckpt"].contains(ext) ||
            ["/.ollama/models/", "/.mtplx/models/", "/.lmstudio/models/", "/.cache/huggingface/", "/.cache/lm-studio/models/"].contains(where: path.contains) { return .models }
        if path.hasPrefix(home + "/Library/Caches/") || path.hasPrefix(home + "/.cache/") || path.hasPrefix("/Library/Caches/") { return .caches }
        if parts.contains(".git") { return .sourceCode }
        if path.hasPrefix(home + "/Library/") { return .appData }
        if ["/System/", "/private/", "/usr/", "/bin/", "/sbin/", "/Library/"].contains(where: path.hasPrefix) { return .system }
        if ["mp4", "mov", "mkv", "avi", "m4v", "webm", "mts", "m2ts", "mpg", "mpeg"].contains(ext) { return .videos }
        if ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif", "raw", "cr2", "cr3", "nef", "dng", "psd", "ai", "svg"].contains(ext) { return .images }
        if ["mp3", "wav", "m4a", "flac", "aac", "aiff", "ogg", "opus", "aif"].contains(ext) { return .audio }
        if ["pdf", "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "txt", "rtf", "epub", "odt", "csv"].contains(ext) { return .documents }
        if ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "iso", "ipsw"].contains(ext) { return .archives }
        if ["swift", "py", "js", "ts", "tsx", "jsx", "c", "cpp", "h", "rs", "go", "java", "kt", "sh", "json", "yml", "yaml", "toml", "md", "html", "css", "sql"].contains(ext) { return .sourceCode }
        return .other
    }
}

public struct CategoryTotal: Identifiable, Codable, Sendable {
    public var id: String { category.rawValue }
    public let category: FileCategory
    public var bytes: Int64
    public var fileCount: Int
}
