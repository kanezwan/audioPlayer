import Foundation

struct AudioSegment: Identifiable, Hashable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval { endTime - startTime }

    func timecodeString() -> String {
        String(format: "%02d:%02d-%02d:%02d",
               Int(startTime) / 60, Int(startTime) % 60,
               Int(endTime) / 60, Int(endTime) % 60)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AudioSegment, rhs: AudioSegment) -> Bool {
        lhs.id == rhs.id
    }
}
