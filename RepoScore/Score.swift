import Foundation

struct Score: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let pageCount: Int
    let importedAt: Date
    var folderID: UUID? = nil
}

struct ScoreFolder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    let parentID: UUID?
}

struct LibrarySnapshot: Sendable {
    let scores: [Score]
    let folders: [ScoreFolder]
}
