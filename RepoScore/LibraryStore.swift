import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var scores: [Score] = []
    @Published private(set) var folders: [ScoreFolder] = []
    @Published private(set) var isUpdating = false
    var isBusy: Bool { isLoading || isImporting || isUpdating }
    @Published private(set) var isLoading = true
    @Published private(set) var isImporting = false
    @Published private(set) var loadError: String?
    @Published var importError: String?

    private let repository: ScoreRepository
    private var loadStarted = false

    init(repository: ScoreRepository? = nil) {
        var root = ScoreRepository.defaultRoot
        #if DEBUG
        // UI tests use a separate library; normal launches never seed user data.
        if let session = ProcessInfo.processInfo.environment["REPOSCORE_UI_TEST_SESSION"],
           let id = UUID(uuidString: session) {
            root = root.appendingPathComponent("UITests/\(id.uuidString)", isDirectory: true)
        }
        #endif
        self.repository = repository ?? ScoreRepository(root: root)
    }

    func load() async {
        // All windows share this store; only a failed load should start a retry.
        guard !loadStarted || loadError != nil else { return }
        loadStarted = true
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let restored = try await repository.snapshot()
            apply(restored)
            #if DEBUG
            await importUITestFixtureIfNeeded()
            #endif
        }
        catch { loadError = error.localizedDescription }
    }

    func importPDF(from url: URL, folderID: UUID? = nil) async {
        guard !isBusy, loadError == nil else { return }
        isImporting = true
        defer { isImporting = false }
        do { scores.append(try await repository.importPDF(from: url, folderID: folderID)) }
        catch { importError = "未能导入乐谱。\n\(error.localizedDescription)" }
    }

    func fileURL(for score: Score) -> URL { repository.fileURL(for: score) }

    func createFolder(named name: String, parentID: UUID?) async throws {
        try beginUpdate()
        defer { isUpdating = false }
        apply(try await repository.createFolder(named: name, parentID: parentID))
    }

    func renameFolder(id: UUID, to name: String) async throws {
        try beginUpdate()
        defer { isUpdating = false }
        apply(try await repository.renameFolder(id: id, to: name))
    }

    func moveScore(id: UUID, to folderID: UUID?) async throws {
        try beginUpdate()
        defer { isUpdating = false }
        apply(try await repository.moveScore(id: id, to: folderID))
    }

    private func beginUpdate() throws {
        guard !isBusy, loadError == nil else {
            throw NSError(domain: "RepoScore", code: 1, userInfo: [NSLocalizedDescriptionKey: "曲库暂时无法修改，请稍后重试。"])
        }
        isUpdating = true
    }

    private func apply(_ snapshot: LibrarySnapshot) {
        scores = snapshot.scores
        folders = snapshot.folders
    }

    #if DEBUG
    private func importUITestFixtureIfNeeded() async {
        let environment = ProcessInfo.processInfo.environment
        guard let session = environment["REPOSCORE_UI_TEST_SESSION"], UUID(uuidString: session) != nil,
              scores.isEmpty, let encoded = environment["REPOSCORE_UI_TEST_PDF"],
              let data = Data(base64Encoded: encoded) else { return }
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-UI-Test-Score.pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        do {
            try data.write(to: source)
            scores.append(try await repository.importPDF(from: source))
        } catch {
            importError = "未能导入乐谱。\n\(error.localizedDescription)"
        }
    }
    #endif
}
