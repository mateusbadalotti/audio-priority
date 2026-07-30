import AppKit
import CoreAudio

struct ApplicationAudioSource: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let icon: NSImage?
    var volume: Float = 1

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.icon === rhs.icon
            && lhs.volume == rhs.volume
    }
}
