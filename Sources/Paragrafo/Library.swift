import Foundation

/// What is kept between sessions for one PDF, keyed by the file's fingerprint.
struct SavedDocument: Codable, Sendable {
    var name: String
    var path: String
    var pages: Int
    var source: String
    var target: String
    var translations: [String]
    /// Hash of the extracted paragraphs the translations belong to.
    var contentKey: String?
    var summary: String?
    var summarySources: [SavedSource]?
    /// Identifies what the saved vectors were computed from: model, chunker version and the chunk texts.
    var indexKey: String?
    var dimension: Int?
    var opened = Date()
}

/// A passage a saved synthesis points to.
struct SavedSource: Codable, Sendable {
    var page: Int
    var paragraph: Int
    var text: String
}

struct RecentDocument: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var name: String
    var path: String
    var pages: Int
    var paragraphs: Int
    var completed: Int
    var opened: Date
}

/// Plain files in Application Support. Translations as JSON, embeddings as raw Float32.
enum Library {
    static let directory: URL = {
        // Checks point this at a temporary folder so they never touch real saved work.
        let override = ProcessInfo.processInfo.environment["PARAGRAFO_LIBRARY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = override ?? base.appendingPathComponent("Paragrafo", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }()

    private static func file(_ fingerprint: String, _ ext: String) -> URL? {
        guard !fingerprint.isEmpty, fingerprint.utf8.count <= 128,
              fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let url = directory.appendingPathComponent("\(fingerprint).\(ext)")
        guard url.resolvingSymlinksInPath().deletingLastPathComponent() == directory.resolvingSymlinksInPath() else { return nil }
        return url
    }

    private static func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private static var recentsFile: URL { directory.appendingPathComponent("recentes.json") }

    static func load(_ fingerprint: String) -> SavedDocument? {
        guard let url = file(fingerprint, "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedDocument.self, from: data)
    }

    static func save(_ document: SavedDocument, fingerprint: String) {
        guard let url = file(fingerprint, "json"), let data = try? JSONEncoder().encode(document) else { return }
        write(data, to: url)
        var list = recents().filter { $0.id != fingerprint }
        list.insert(RecentDocument(id: fingerprint, name: document.name, path: document.path, pages: document.pages,
                                   paragraphs: document.translations.count,
                                   completed: document.translations.lazy.filter { !$0.isEmpty }.count, opened: document.opened), at: 0)
        // The list is trimmed; saved work is never deleted behind the user's back.
        if let encoded = try? JSONEncoder().encode(Array(list.prefix(50))) { write(encoded, to: recentsFile) }
    }

    /// Read-modify-write for callers that own only part of the record.
    static func update(_ fingerprint: String, _ change: (inout SavedDocument) -> Void) {
        guard var document = load(fingerprint) else { return }
        change(&document)
        save(document, fingerprint: fingerprint)
    }

    static func recents() -> [RecentDocument] {
        guard let data = try? Data(contentsOf: recentsFile) else { return [] }
        return (try? JSONDecoder().decode([RecentDocument].self, from: data)) ?? []
    }

    static func remove(_ fingerprint: String) {
        guard let json = file(fingerprint, "json"), let vectors = file(fingerprint, "vec") else { return }
        try? FileManager.default.removeItem(at: json)
        try? FileManager.default.removeItem(at: vectors)
        let list = recents().filter { $0.id != fingerprint }
        if let encoded = try? JSONEncoder().encode(list) { write(encoded, to: recentsFile) }
    }

    static func saveVectors(_ vectors: [[Float]], fingerprint: String) {
        guard let url = file(fingerprint, "vec") else { return }
        let data = Array(vectors.joined()).withUnsafeBufferPointer { Data(buffer: $0) }
        write(data, to: url)
    }

    static func loadVectors(fingerprint: String, count: Int, dimension: Int) -> [[Float]]? {
        let stride = MemoryLayout<Float>.size
        guard count > 0, count <= 100_000, dimension > 0, dimension <= 8192,
              count <= 128 * 1024 * 1024 / stride / dimension,
              let url = file(fingerprint, "vec"), let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count == count * dimension * stride else { return nil }
        return (0..<count).map { row in
            [Float](unsafeUninitializedCapacity: dimension) { buffer, initialized in
                data.copyBytes(to: buffer, from: (row * dimension * stride)..<((row + 1) * dimension * stride))
                initialized = dimension
            }
        }
    }
}
