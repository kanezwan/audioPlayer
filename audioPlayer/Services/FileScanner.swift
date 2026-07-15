import Foundation

struct FileScanner {
    static let supportedExtensions = ["wav", "mp3", "aac", "m4a"]

    func scanFolder(at url: URL) throws -> [AudioFileItem] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { url in
                let ext = url.pathExtension.lowercased()
                return Self.supportedExtensions.contains(ext)
            }
            .map { AudioFileItem(url: $0, name: $0.lastPathComponent) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
