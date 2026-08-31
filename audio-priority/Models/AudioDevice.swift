import Foundation
import CoreAudio

enum AudioDeviceType: String, Codable {
    case input
    case output
}

struct AudioDevice: Identifiable, Equatable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let originalName: String
    let type: AudioDeviceType

    var hasCustomName: Bool {
        name != originalName
    }

    init(
        id: AudioObjectID,
        uid: String,
        name: String,
        originalName: String? = nil,
        type: AudioDeviceType
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.originalName = originalName ?? name
        self.type = type
    }

    func renamed(to displayName: String) -> AudioDevice {
        AudioDevice(
            id: id,
            uid: uid,
            name: displayName,
            originalName: originalName,
            type: type
        )
    }
}
