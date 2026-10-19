import Foundation
import PDFKit

/// Owns copies and their index; serialized operations keep imports from losing records.
actor ScoreRepository {
    private struct Index: Codable {
        let version: Int
        let scores: [Score]
        let folders: [ScoreFolder]?
    }

    enum LibraryError: LocalizedError {
        case invalidPDF
        case lockedPDF
        case invalidIndex
        case invalidFolderName
        case duplicateFolderName
        case folderNotFound
        case scoreNotFound

        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "这个文件不是可读取的 PDF，或没有可阅读的页面。"
            case .lockedPDF: return "暂不支持需要密码才能打开的 PDF。请先解锁文件再导入。"
            case .invalidIndex: return "曲库索引无法读取。已有文件已保留，请重试。"
            case .invalidFolderName: return "请输入文件夹名称；名称不能是 .、.. 或包含 /。"
            case .duplicateFolderName: return "这个位置已有同名文件夹，请使用另一个名称。"
            case .folderNotFound: return "找不到目标文件夹，请返回曲库重试。"
            case .scoreNotFound: return "找不到这份乐谱，请返回曲库重试。"
            }
        }
    }

    let root: URL
    private var scores: [Score] = []
    private var folders: [ScoreFolder] = []
    private var isLoaded = false
    private var pdfDirectory: URL { root.appendingPathComponent("PDFs", isDirectory: true) }
    private var stagingDirectory: URL { root.appendingPathComponent("Staging", isDirectory: true) }
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    init(root: URL) {
        self.root = root
    }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RepoScore", isDirectory: true)
    }

    nonisolated func fileURL(for score: Score) -> URL {
        root.appendingPathComponent("PDFs", isDirectory: true)
            .appendingPathComponent(score.id.uuidString).appendingPathExtension("pdf")
    }

    func load() throws -> [Score] {
        if isLoaded { return scores }
        let manager = FileManager.default
        try manager.createDirectory(at: pdfDirectory, withIntermediateDirectories: true)

        let restored: [Score]
        let restoredFolders: [ScoreFolder]
        if manager.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            guard let index = try? JSONDecoder().decode(Index.self, from: data),
                  index.version == 1 || index.version == 2,
                  index.version != 2 || index.folders != nil,
                  index.version != 1 || (index.folders ?? []).isEmpty,
                  Self.isValid(scores: index.scores, folders: index.folders ?? []) else {
                throw LibraryError.invalidIndex
            }
            restored = index.scores
            restoredFolders = index.folders ?? []
            if index.version == 1 {
                // Preserve the exact old index before committing a version 2 replacement.
                let backup = root.appendingPathComponent("index-v1-backup-\(UUID().uuidString).json")
                try data.write(to: backup, options: .withoutOverwriting)
                try persist(scores: restored, folders: restoredFolders)
            }
        } else {
            restored = []
            restoredFolders = []
        }

        // Only temporary imports are removed. Never delete saved PDFs on index failure.
        if manager.fileExists(atPath: stagingDirectory.path) {
            try manager.removeItem(at: stagingDirectory)
        }
        try manager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        scores = restored
        folders = restoredFolders
        isLoaded = true
        return scores
    }

    func importPDF(from source: URL, folderID: UUID? = nil) throws -> Score {
        if !isLoaded { _ = try load() }
        try requireFolder(folderID)
        let manager = FileManager.default
        let id = UUID()
        let staged = stagingDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("pdf")
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed { source.stopAccessingSecurityScopedResource() }
            try? manager.removeItem(at: staged)
        }

        // Coordinate reads from Files providers, including downloaded cloud documents.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do { try manager.copyItem(at: url, to: staged) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }

        guard let document = PDFDocument(url: staged) else { throw LibraryError.invalidPDF }
        guard !document.isLocked else { throw LibraryError.lockedPDF }
        guard document.pageCount > 0, document.page(at: 0) != nil else { throw LibraryError.invalidPDF }

        let name = source.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let score = Score(id: id, title: name.isEmpty ? "未命名乐谱" : name,
                          pageCount: document.pageCount, importedAt: Date(), folderID: folderID)
        let destination = fileURL(for: score)
        try manager.moveItem(at: staged, to: destination)
        let updated = scores + [score]
        do {
            try persist(scores: updated, folders: folders)
        } catch {
            // A failed index write must not create a successful import record.
            try? manager.removeItem(at: destination)
            throw error
        }
        scores = updated
        return score
    }
    func snapshot() throws -> LibrarySnapshot {
        _ = try load()
        return LibrarySnapshot(scores: scores, folders: folders)
    }

    func createFolder(named name: String, parentID: UUID?) throws -> LibrarySnapshot {
        _ = try load()
        try requireFolder(parentID)
        let cleaned = try validatedName(name, parentID: parentID)
        let updated = folders + [ScoreFolder(id: UUID(), name: cleaned, parentID: parentID)]
        try persist(scores: scores, folders: updated)
        folders = updated
        return LibrarySnapshot(scores: scores, folders: folders)
    }

    func renameFolder(id: UUID, to name: String) throws -> LibrarySnapshot {
        _ = try load()
        guard let index = folders.firstIndex(where: { $0.id == id }) else { throw LibraryError.folderNotFound }
        let cleaned = try validatedName(name, parentID: folders[index].parentID, excluding: id)
        var updated = folders
        updated[index].name = cleaned
        try persist(scores: scores, folders: updated)
        folders = updated
        return LibrarySnapshot(scores: scores, folders: folders)
    }

    func moveScore(id: UUID, to folderID: UUID?) throws -> LibrarySnapshot {
        _ = try load()
        try requireFolder(folderID)
        guard let index = scores.firstIndex(where: { $0.id == id }) else { throw LibraryError.scoreNotFound }
        var updated = scores
        updated[index].folderID = folderID
        try persist(scores: updated, folders: folders)
        scores = updated
        return LibrarySnapshot(scores: scores, folders: folders)
    }

    private func persist(scores: [Score], folders: [ScoreFolder]) throws {
        let data = try JSONEncoder().encode(Index(version: 2, scores: scores, folders: folders))
        try data.write(to: indexURL, options: .atomic)
    }

    private func requireFolder(_ id: UUID?) throws {
        if let id, !folders.contains(where: { $0.id == id }) { throw LibraryError.folderNotFound }
    }

    private func validatedName(_ name: String, parentID: UUID?, excluding id: UUID? = nil) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidName(cleaned) else { throw LibraryError.invalidFolderName }
        if folders.contains(where: { $0.parentID == parentID && $0.id != id && Self.nameKey($0.name) == Self.nameKey(cleaned) }) {
            throw LibraryError.duplicateFolderName
        }
        return cleaned
    }

    private static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
            && name == name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nameKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isValid(scores: [Score], folders: [ScoreFolder]) -> Bool {
        let ids = Set(folders.map(\.id))
        guard ids.count == folders.count, Set(scores.map(\.id)).count == scores.count,
              scores.allSatisfy({ !$0.title.isEmpty && $0.pageCount > 0 && ($0.folderID == nil || ids.contains($0.folderID!)) }) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var siblingNames: [UUID?: Set<String>] = [:]
        for folder in folders {
            guard isValidName(folder.name), folder.parentID == nil || ids.contains(folder.parentID!) else { return false }
            if !siblingNames[folder.parentID, default: []].insert(nameKey(folder.name)).inserted { return false }
            var visited = Set<UUID>()
            var current: UUID? = folder.id
            while let id = current {
                guard visited.insert(id).inserted else { return false }
                current = byID[id]?.parentID
            }
        }
        return true
    }

}
