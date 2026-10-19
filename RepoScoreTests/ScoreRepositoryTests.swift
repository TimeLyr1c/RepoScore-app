import XCTest
import UIKit
import PDFKit
@testable import RepoScore

@MainActor
final class ScoreRepositoryTests: XCTestCase {
    private var workspace: URL!
    private var root: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = workspace.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: workspace)
    }

    private func makePDF(name: String = "练习乐谱.pdf", pages: Int = 2, directory: String = "Sources") throws -> URL {
        let folder = workspace.appendingPathComponent(directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        try renderer.writePDF(to: url) { context in
            for page in 1...pages {
                context.beginPage()
                ("RepoScore Test — Page \(page)" as NSString).draw(at: CGPoint(x: 50, y: 50))
            }
        }
        return url
    }

    private func assertNoImportedFiles() throws {
        for folder in ["PDFs", "Staging"] {
            let contents = try FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil
            )
            XCTAssertTrue(contents.isEmpty, "Unexpected files in \(folder)")
        }
    }

    func testImportKeepsIndependentReadableCopyAfterSourceDeletionAndRestart() async throws {
        let source = try makePDF()
        let bytes = try Data(contentsOf: source)
        let repository = ScoreRepository(root: root)
        let score = try await repository.importPDF(from: source)
        XCTAssertEqual(score.title, "练习乐谱")
        XCTAssertEqual(score.pageCount, 2)
        XCTAssertEqual(try Data(contentsOf: repository.fileURL(for: score)), bytes)
        try FileManager.default.removeItem(at: source)

        let restarted = ScoreRepository(root: root)
        let records = try await restarted.load()
        XCTAssertEqual(records, [score])
        let pdf = try XCTUnwrap(PDFDocument(url: restarted.fileURL(for: records[0])))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertNotNil(pdf.page(at: 1))
    }

    func testSameNamedImportsDoNotOverwriteEachOther() async throws {
        let first = try makePDF(pages: 1, directory: "First")
        let second = try makePDF(pages: 3, directory: "Second")
        let repository = ScoreRepository(root: root)
        let a = try await repository.importPDF(from: first)
        let b = try await repository.importPDF(from: second)
        XCTAssertEqual(a.title, b.title)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(PDFDocument(url: repository.fileURL(for: a))?.pageCount, 1)
        XCTAssertEqual(PDFDocument(url: repository.fileURL(for: b))?.pageCount, 3)
        let restored = try await ScoreRepository(root: root).load()
        XCTAssertEqual(restored.count, 2)
    }

    func testInvalidPDFLeavesNoRecordOrTemporaryCopy() async throws {
        let source = workspace.appendingPathComponent("invalid.pdf")
        try Data("This is not a PDF".utf8).write(to: source)
        let repository = ScoreRepository(root: root)
        do {
            _ = try await repository.importPDF(from: source)
            XCTFail("Invalid PDF should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, ScoreRepository.LibraryError.invalidPDF.localizedDescription)
        }
        let records = try await repository.load()
        XCTAssertTrue(records.isEmpty)
        try assertNoImportedFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
    }

    func testLockedPDFIsRejectedWithoutSavingACopy() async throws {
        let source = try makePDF()
        let encrypted = workspace.appendingPathComponent("locked.pdf")
        let document = try XCTUnwrap(PDFDocument(url: source))
        XCTAssertTrue(document.write(to: encrypted, withOptions: [
            .ownerPasswordOption: "test-owner", .userPasswordOption: "test-reader"
        ]))
        XCTAssertTrue(try XCTUnwrap(PDFDocument(url: encrypted)).isLocked)
        let repository = ScoreRepository(root: root)
        do {
            _ = try await repository.importPDF(from: encrypted)
            XCTFail("Locked PDF should fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, ScoreRepository.LibraryError.lockedPDF.localizedDescription)
        }
        let records = try await repository.load()
        XCTAssertTrue(records.isEmpty)
        try assertNoImportedFiles()
    }

    func testInvalidImportDoesNotDamageExistingIndexOrCopy() async throws {
        let source = try makePDF()
        let repository = ScoreRepository(root: root)
        let score = try await repository.importPDF(from: source)
        let indexURL = root.appendingPathComponent("index.json")
        let before = try Data(contentsOf: indexURL)
        let invalid = workspace.appendingPathComponent("invalid.pdf")
        try Data("invalid".utf8).write(to: invalid)
        do {
            _ = try await repository.importPDF(from: invalid)
            XCTFail("Invalid PDF should fail")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: indexURL), before)
        let records = try await ScoreRepository(root: root).load()
        XCTAssertEqual(records, [score])
        XCTAssertNotNil(PDFDocument(url: repository.fileURL(for: score)))
    }

    func testMissingSourceLeavesLibraryUnchanged() async throws {
        let source = try makePDF()
        let repository = ScoreRepository(root: root)
        let existing = try await repository.importPDF(from: source)
        do {
            _ = try await repository.importPDF(from: workspace.appendingPathComponent("missing.pdf"))
            XCTFail("Missing source should fail")
        } catch {}
        let restored = try await ScoreRepository(root: root).load()
        XCTAssertEqual(restored, [existing])
        XCTAssertNotNil(PDFDocument(url: repository.fileURL(for: existing)))
        let temporary = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Staging").path)
        XCTAssertTrue(temporary.isEmpty)
    }

    func testIndexWriteFailureRollsBackCopyAndAllowsRetry() async throws {
        let source = try makePDF()
        let repository = ScoreRepository(root: root)
        _ = try await repository.load()
        let indexURL = root.appendingPathComponent("index.json")
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)
        do {
            _ = try await repository.importPDF(from: source)
            XCTFail("Index write should fail")
        } catch {}
        let records = try await repository.load()
        XCTAssertTrue(records.isEmpty)
        try assertNoImportedFiles()
        try FileManager.default.removeItem(at: indexURL)
        _ = try await repository.importPDF(from: source)
        let retried = try await ScoreRepository(root: root).load()
        XCTAssertEqual(retried.count, 1)
    }

    func testCorruptedIndexCannotBeOverwrittenByImport() async throws {
        let source = try makePDF()
        let initial = ScoreRepository(root: root)
        let score = try await initial.importPDF(from: source)
        let indexURL = root.appendingPathComponent("index.json")
        let corrupt = Data("broken index".utf8)
        try corrupt.write(to: indexURL)
        let reopened = ScoreRepository(root: root)
        do {
            _ = try await reopened.importPDF(from: source)
            XCTFail("Corrupted index should block import")
        } catch {
            XCTAssertEqual(error.localizedDescription, ScoreRepository.LibraryError.invalidIndex.localizedDescription)
        }
        XCTAssertEqual(try Data(contentsOf: indexURL), corrupt)
        XCTAssertNotNil(PDFDocument(url: initial.fileURL(for: score)))
        let saved = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("PDFs").path)
        XCTAssertEqual(saved.count, 1)
    }

    func testLoadRemovesAbandonedStagingButPreservesSavedFiles() async throws {
        let repository = ScoreRepository(root: root)
        let source = try makePDF()
        let score = try await repository.importPDF(from: source)
        let abandoned = root.appendingPathComponent("Staging/abandoned.pdf")
        try Data("partial".utf8).write(to: abandoned)
        let reopened = ScoreRepository(root: root)
        let records = try await reopened.load()
        XCTAssertEqual(records, [score])
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertNotNil(PDFDocument(url: reopened.fileURL(for: score)))
    }

    func testConcurrentImportsBothSurviveRestart() async throws {
        let a = try makePDF(pages: 1, directory: "First")
        let b = try makePDF(pages: 2, directory: "Second")
        let repository = ScoreRepository(root: root)
        async let first = repository.importPDF(from: a)
        async let second = repository.importPDF(from: b)
        let imported = try await [first, second]
        let restored = try await ScoreRepository(root: root).load()
        XCTAssertEqual(Set(restored.map(\.id)), Set(imported.map(\.id)))
    }

    func testMissingSavedPDFDoesNotSilentlyEraseRecord() async throws {
        let source = try makePDF()
        let repository = ScoreRepository(root: root)
        let score = try await repository.importPDF(from: source)
        try FileManager.default.removeItem(at: repository.fileURL(for: score))
        let records = try await ScoreRepository(root: root).load()
        XCTAssertEqual(records, [score])
        XCTAssertNil(PDFDocument(url: repository.fileURL(for: score)))
    }

    func testStoreBlocksImportOnLoadFailureAndCanRetryAfterRepair() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let indexURL = root.appendingPathComponent("index.json")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: indexURL)
        let source = try makePDF()
        let store = LibraryStore(repository: ScoreRepository(root: root))
        await store.load()
        XCTAssertNotNil(store.loadError)
        XCTAssertFalse(store.isLoading)
        await store.importPDF(from: source)
        XCTAssertTrue(store.scores.isEmpty)
        XCTAssertEqual(try Data(contentsOf: indexURL), corrupt)

        try Data(#"{"version":1,"scores":[]}"#.utf8).write(to: indexURL)
        await store.load()
        XCTAssertNil(store.loadError)
        await store.importPDF(from: source)
        XCTAssertEqual(store.scores.count, 1)
        await store.load() // Another window must not clear a successfully loaded store.
        XCTAssertEqual(store.scores.count, 1)
    }
    func testVersionOneMigrationPreservesCopiesAndBacksUpOriginalIndex() async throws {
        let repository = ScoreRepository(root: root)
        let source = try makePDF()
        let score = try await repository.importPDF(from: source)
        let copyBytes = try Data(contentsOf: repository.fileURL(for: score))
        struct LegacyIndex: Encodable { let version = 1; let scores: [Score] }
        let legacy = try JSONEncoder().encode(LegacyIndex(scores: [score]))
        let indexURL = root.appendingPathComponent("index.json")
        try legacy.write(to: indexURL)
        let restarted = ScoreRepository(root: root)
        let restored = try await restarted.snapshot()
        XCTAssertEqual(restored.scores, [score])
        XCTAssertTrue(restored.folders.isEmpty)
        XCTAssertNil(restored.scores[0].folderID)
        XCTAssertEqual(try Data(contentsOf: restarted.fileURL(for: score)), copyBytes)
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("index-v1-backup-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), legacy)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        _ = try await ScoreRepository(root: root).load()
        let after = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("index-v1-backup-") }
        XCTAssertEqual(after.count, 1)
    }

    func testNestedFoldersRenameAndScoreMovePersistWithoutMovingPDF() async throws {
        let repository = ScoreRepository(root: root)
        let source = try makePDF()
        let score = try await repository.importPDF(from: source)
        let saved = repository.fileURL(for: score)
        let before = try Data(contentsOf: saved)
        let first = try await repository.createFolder(named: "  练习  ", parentID: nil)
        let parent = try XCTUnwrap(first.folders.first)
        XCTAssertEqual(parent.name, "练习")
        let second = try await repository.createFolder(named: "钢琴", parentID: parent.id)
        let child = try XCTUnwrap(second.folders.first { $0.parentID == parent.id })
        _ = try await repository.renameFolder(id: parent.id, to: "个人练习")
        _ = try await repository.moveScore(id: score.id, to: child.id)
        let reopened = try await ScoreRepository(root: root).snapshot()
        XCTAssertEqual(reopened.folders.first { $0.id == parent.id }?.name, "个人练习")
        XCTAssertEqual(reopened.folders.first { $0.id == child.id }?.parentID, parent.id)
        XCTAssertEqual(reopened.scores[0].folderID, child.id)
        XCTAssertEqual(try Data(contentsOf: saved), before)
        _ = try await repository.moveScore(id: score.id, to: nil)
        let returned = try await ScoreRepository(root: root).snapshot()
        XCTAssertNil(returned.scores[0].folderID)
    }

    func testImportDirectlyIntoFolderPersistsDestination() async throws {
        let repository = ScoreRepository(root: root)
        let snapshot = try await repository.createFolder(named: "排练", parentID: nil)
        let folder = snapshot.folders[0]
        let source = try makePDF()
        let score = try await repository.importPDF(from: source, folderID: folder.id)
        let reopened = try await ScoreRepository(root: root).snapshot()
        XCTAssertEqual(reopened.scores, [score])
        XCTAssertEqual(score.folderID, folder.id)
    }

    func testFolderNameRulesAndSiblingUniqueness() async throws {
        let repository = ScoreRepository(root: root)
        let first = try await repository.createFolder(named: "Practice", parentID: nil)
        let parent = first.folders[0]
        do {
            _ = try await repository.createFolder(named: " practice ", parentID: nil)
            XCTFail("Case-insensitive sibling duplicate should fail")
        } catch {}
        let nested = try await repository.createFolder(named: "Practice", parentID: parent.id)
        XCTAssertEqual(nested.folders.count, 2)
        _ = try await repository.renameFolder(id: parent.id, to: "PRACTICE")
        for name in ["", "  ", ".", "..", "a/b"] {
            do {
                _ = try await repository.createFolder(named: name, parentID: nil)
                XCTFail("Invalid name should fail: \(name)")
            } catch {}
        }
        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.folders.count, 2)
    }

    func testMissingDestinationsCannotCreateOrMoveRecords() async throws {
        let repository = ScoreRepository(root: root)
        let source = try makePDF()
        let existing = try await repository.importPDF(from: source)
        let absent = UUID()
        do { _ = try await repository.createFolder(named: "Test", parentID: absent); XCTFail() } catch {}
        do { _ = try await repository.importPDF(from: source, folderID: absent); XCTFail() } catch {}
        do { _ = try await repository.moveScore(id: existing.id, to: absent); XCTFail() } catch {}
        do { _ = try await repository.moveScore(id: absent, to: nil); XCTFail() } catch {}
        let snapshot = try await ScoreRepository(root: root).snapshot()
        XCTAssertEqual(snapshot.scores, [existing])
        XCTAssertTrue(snapshot.folders.isEmpty)
    }

    func testFailedFolderChangesLeaveInMemoryAndPDFStateUnchanged() async throws {
        let repository = ScoreRepository(root: root)
        let source = try makePDF()
        let score = try await repository.importPDF(from: source)
        let initial = try await repository.createFolder(named: "练习", parentID: nil)
        let folder = initial.folders[0]
        let indexURL = root.appendingPathComponent("index.json")
        let original = try Data(contentsOf: indexURL)
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)
        do { _ = try await repository.renameFolder(id: folder.id, to: "排练"); XCTFail() } catch {}
        do { _ = try await repository.moveScore(id: score.id, to: folder.id); XCTFail() } catch {}
        do { _ = try await repository.createFolder(named: "新建", parentID: nil); XCTFail() } catch {}
        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.folders, initial.folders)
        XCTAssertEqual(snapshot.scores, [score])
        XCTAssertNotNil(PDFDocument(url: repository.fileURL(for: score)))
        try FileManager.default.removeItem(at: indexURL)
        try original.write(to: indexURL)
        let repaired = try await repository.snapshot()
        XCTAssertEqual(repaired.folders, initial.folders)
    }

    func testInvalidFolderGraphAndUnknownVersionArePreservedAndRejected() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let a = UUID(), b = UUID()
        let graphs = [
            [ScoreFolder(id: a, name: "A", parentID: b), ScoreFolder(id: b, name: "B", parentID: a)],
            [ScoreFolder(id: a, name: "A", parentID: b)],
            [ScoreFolder(id: a, name: "A", parentID: nil), ScoreFolder(id: b, name: "a", parentID: nil)]
        ]
        struct TestIndex: Encodable { let version: Int; let scores: [Score]; let folders: [ScoreFolder] }
        let indexURL = root.appendingPathComponent("index.json")
        for graph in graphs {
            let data = try JSONEncoder().encode(TestIndex(version: 2, scores: [], folders: graph))
            try data.write(to: indexURL)
            do { _ = try await ScoreRepository(root: root).load(); XCTFail("Invalid graph must fail") } catch {}
            XCTAssertEqual(try Data(contentsOf: indexURL), data)
        }
        let future = try JSONEncoder().encode(TestIndex(version: 999, scores: [], folders: []))
        try future.write(to: indexURL)
        do { _ = try await ScoreRepository(root: root).load(); XCTFail("Future version must fail") } catch {}
        XCTAssertEqual(try Data(contentsOf: indexURL), future)
    }

}
