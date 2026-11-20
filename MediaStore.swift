import Foundation

/// One entry in the offline library. The file lives in Documents/Media and the
/// record lives in Documents/library.json, so the library survives app updates
/// and works with no network at all.
struct MediaItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var fileName: String
    var isHLS: Bool
    var addedAt: Date
    var byteSize: Int64
    var sourceURL: String

    var fileURL: URL {
        MediaStore.mediaDirectory.appendingPathComponent(fileName)
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

enum MediaStore {
    /// Documents/Media — included in device backups and reachable by AVPlayer.
    static var mediaDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static var indexURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("library.json")
    }

    static func load() -> [MediaItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MediaItem].self, from: data)) ?? []
    }

    static func save(_ items: [MediaItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Removes the file and, for HLS, the directory bundle the system created.
    static func delete(_ item: MediaItem) {
        let url = item.fileURL
        try? FileManager.default.removeItem(at: url)
        // AVAssetDownloadTask writes a sidecar .movpkg bundle next to the name.
        let bundle = url.deletingPathExtension().appendingPathExtension("movpkg")
        try? FileManager.default.removeItem(at: bundle)
    }

    static func totalBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }
}
