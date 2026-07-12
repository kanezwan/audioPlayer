import Foundation

struct AudioFileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioFileItem, rhs: AudioFileItem) -> Bool {
        lhs.id == rhs.id
    }
}
