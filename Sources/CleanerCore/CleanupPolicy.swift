import Foundation

/// Eligibility is narrower than storage advice: personal files, system data and
/// worktrees are inspectable but never become arbitrary deletion targets.
public enum CleanupPolicy {
    public static func source(for url: URL, home: URL) -> SourceKind? {
        let path = url.path
        guard path.hasPrefix(home.path + "/"), !url.pathComponents.contains("..") else { return nil }
        let relative = String(path.dropFirst(home.path.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard !components.contains(where: {
            [".git", ".worktrees", "Pictures"].contains($0) || $0.hasSuffix(".photoslibrary") || $0.hasSuffix(".photolibrary")
        }) else { return nil }

        for source in SourceKind.allCases where !source.isProjectOutput {
            let root = home.appendingPathComponent(source.relativeRoot).path
            var ancestor = url
            for _ in 0..<source.depth { ancestor.deleteLastPathComponent() }
            guard ancestor.path == root else { continue }
            if source == .huggingFace && !["models--", "datasets--", "spaces--"].contains(where: { url.lastPathComponent.hasPrefix($0) }) { continue }
            if source == .archives && url.pathExtension != "xcarchive" { continue }
            if source == .downloadInstaller && !["dmg", "pkg"].contains(url.pathExtension.lowercased()) { continue }
            if source == .userCache && url.lastPathComponent == "com.apple.dt.Xcode" { continue }
            if url.lastPathComponent.hasPrefix(".") { continue }
            return source
        }
        // Never classify an entire project, worktree or .artifacts tree as disposable.
        guard components.count >= 3, ["Documents", "Desktop", "Developer", "Projects"].contains(components.first ?? "") else { return nil }
        switch url.lastPathComponent {
        case ".build": return .projectBuild
        case "node_modules": return .dependencies
        default: return url.pathExtension == "xcresult" ? .testResults : nil
        }
    }
}
