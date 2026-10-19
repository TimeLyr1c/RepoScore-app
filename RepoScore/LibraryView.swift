import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @State private var showsImporter = false
    @State private var importFolderID: UUID?
    @State private var showsImportError = false
    @State private var showsFolderEditor = false
    @State private var editedFolder: ScoreFolder?
    @State private var editorParentID: UUID?
    @State private var folderName = ""
    @State private var operationError: String?
    @State private var movedScore: Score?

    var body: some View {
        NavigationStack {
            FolderContentsView(store: store, folderID: nil,
                               onImport: beginImport, onCreate: beginCreate,
                               onRename: beginRename, onMove: { movedScore = $0 })
        }
        .task { await store.load() }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                let destination = importFolderID
                Task { await store.importPDF(from: url, folderID: destination) }
            case .failure(let error):
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError {
                    store.importError = "未能选择文件。\n\(error.localizedDescription)"
                }
            }
        }
        .onChange(of: store.importError) { _, error in
            if error != nil { showsImportError = true }
        }
        .alert("导入失败", isPresented: $showsImportError) {
            Button("好", role: .cancel) {}
        } message: { Text(store.importError ?? "") }
        .alert(editedFolder == nil ? "新建文件夹" : "重命名文件夹", isPresented: $showsFolderEditor) {
            TextField("文件夹名称", text: $folderName)
                .accessibilityIdentifier("folderName")
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = folderName
                let folder = editedFolder
                let parentID = editorParentID
                Task {
                    do {
                        if let folder { try await store.renameFolder(id: folder.id, to: name) }
                        else { try await store.createFolder(named: name, parentID: parentID) }
                    } catch { operationError = error.localizedDescription }
                }
            }
        }
        .alert("无法修改曲库", isPresented: Binding(
            get: { operationError != nil }, set: { if !$0 { operationError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: { Text(operationError ?? "") }
        .sheet(item: $movedScore) { score in MoveScoreSheet(store: store, score: score) }
    }

    private func beginImport(_ folderID: UUID?) {
        store.importError = nil
        importFolderID = folderID
        showsImporter = true
    }

    private func beginCreate(_ parentID: UUID?) {
        editedFolder = nil
        editorParentID = parentID
        folderName = ""
        showsFolderEditor = true
    }

    private func beginRename(_ folder: ScoreFolder) {
        editedFolder = folder
        editorParentID = folder.parentID
        folderName = folder.name
        showsFolderEditor = true
    }
}

private struct FolderContentsView: View {
    @ObservedObject var store: LibraryStore
    let folderID: UUID?
    let onImport: (UUID?) -> Void
    let onCreate: (UUID?) -> Void
    let onRename: (ScoreFolder) -> Void
    let onMove: (Score) -> Void

    private var folders: [ScoreFolder] { store.folders.filter { $0.parentID == folderID } }
    private var scores: [Score] { store.scores.filter { $0.folderID == folderID } }
    private var title: String { store.folders.first { $0.id == folderID }?.name ?? "RepoScore" }

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("正在读取曲库…")
            } else if let error = store.loadError {
                ContentUnavailableView {
                    Label("曲库暂时无法读取", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("重试") { Task { await store.load() } }
                }
            } else if folders.isEmpty && scores.isEmpty {
                ContentUnavailableView {
                    Label(folderID == nil ? "曲库为空" : "文件夹为空", systemImage: "music.note.list")
                } description: { Text("导入 PDF 乐谱，随时离线阅读。") } actions: {
                    Button("导入乐谱", systemImage: "plus") { onImport(folderID) }
                        .buttonStyle(.borderedProminent).disabled(store.isBusy)
                }
            } else {
                List {
                    ForEach(folders) { folder in
                        NavigationLink {
                            FolderContentsView(store: store, folderID: folder.id,
                                               onImport: onImport, onCreate: onCreate,
                                               onRename: onRename, onMove: onMove)
                        } label: { Label(folder.name, systemImage: "folder") }
                        .accessibilityIdentifier("folder-\(folder.id.uuidString)")
                        .contextMenu {
                            Button("重命名", systemImage: "pencil") { onRename(folder) }
                                .disabled(store.isBusy)
                        }
                        .swipeActions {
                            Button("重命名") { onRename(folder) }.tint(.blue).disabled(store.isBusy)
                        }
                    }
                    ForEach(scores) { score in
                        NavigationLink { ScoreReaderView(score: score, url: store.fileURL(for: score)) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(score.title)
                                    Text("\(score.pageCount) 页").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "doc.richtext") }
                        }
                        .accessibilityIdentifier("score-\(score.id.uuidString)")
                        .contextMenu {
                            Button("移动", systemImage: "folder") { onMove(score) }.disabled(store.isBusy)
                        }
                        .swipeActions {
                            Button("移动") { onMove(score) }.tint(.blue).disabled(store.isBusy)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("新建文件夹", systemImage: "folder.badge.plus") { onCreate(folderID) }
                    .accessibilityIdentifier("createFolder")
                    .disabled(store.isBusy || store.loadError != nil)
                Button("导入乐谱", systemImage: "plus") { onImport(folderID) }
                    .accessibilityIdentifier("importScore")
                    .disabled(store.isBusy || store.loadError != nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.isBusy && !store.isLoading {
                ProgressView(store.isImporting ? "正在保存乐谱…" : "正在保存曲库…")
                    .padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
    }
}

private struct MoveScoreSheet: View {
    @ObservedObject var store: LibraryStore
    let score: Score
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            FolderDestinationView(store: store, folderID: nil) { destination in
                Task {
                    do {
                        try await store.moveScore(id: score.id, to: destination)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
        .alert("无法移动乐谱", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
}

private struct FolderDestinationView: View {
    @ObservedObject var store: LibraryStore
    let folderID: UUID?
    let onSelect: (UUID?) -> Void

    var body: some View {
        List {
            Button("移动到此文件夹", systemImage: "folder") { onSelect(folderID) }
                .accessibilityIdentifier("confirmMove").disabled(store.isBusy)
            ForEach(store.folders.filter { $0.parentID == folderID }) { folder in
                NavigationLink {
                    FolderDestinationView(store: store, folderID: folder.id, onSelect: onSelect)
                } label: { Label(folder.name, systemImage: "folder") }
                .accessibilityIdentifier("destination-\(folder.id.uuidString)")
            }
        }
        .navigationTitle(store.folders.first { $0.id == folderID }?.name ?? "曲库根目录")
        .navigationBarTitleDisplayMode(.inline)
    }
}
