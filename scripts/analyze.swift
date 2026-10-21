import Foundation

/// Developer diagnostic runner. Reads metadata, never cleans. Uses the same scanner,
/// index, queries and report generator as the app; output paths are explicit.
@main
struct AnalyzeMac {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        func option(_ name: String) -> String? {
            guard let position = arguments.firstIndex(of: name), arguments.indices.contains(position + 1) else { return nil }
            return arguments[position + 1]
        }
        let output = URL(fileURLWithPath: option("--output") ?? "build/analysis")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = option("--root").map { URL(fileURLWithPath: $0) }
        let report = try StorageScanner(root: root, indexURL: output.appendingPathComponent("inventory.sqlite")).scan(progress: { value in
            let line = "\(value.files) fichiers · \(ByteSize.string(value.bytes)) · \(value.path)\n"
            FileHandle.standardError.write(Data(line.utf8))
        })
        let insights = StorageInsights(report: report)
        let markdown = insights.markdown(report: report, diskCapacity: DiskScanner().diskSpace()?.total)
        try markdown.write(to: output.appendingPathComponent("Rapport-stockage.md"), atomically: true, encoding: .utf8)
        var query = InventoryQuery()
        query.minimumBytes = 100_000_000
        query.limit = 1000
        let files = try StorageIndex(url: report.indexURL!).query(query)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(files.entries).write(to: output.appendingPathComponent("gros-fichiers.json"))
        let restored = try StorageIndex(url: report.indexURL!).restoreReport()
        guard restored?.fileCount == report.fileCount else { fatalError("Restored index differs from the completed scan") }
        print("\(report.fileCount) fichiers, \(ByteSize.string(report.allocatedBytes)), \(report.categories.count) catégories, \(report.issueCount) chemins inaccessibles.")
        print("\(files.totalCount) fichiers ≥ 100 Mo ; index restauré et requête vérifiée.")
        print(output.appendingPathComponent("Rapport-stockage.md").path)
    }
}
