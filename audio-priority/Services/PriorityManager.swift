import Foundation

final class PriorityManager {
    private let defaults = UserDefaults.standard

    private let inputPrioritiesKey = "inputPriorities"
    private let outputPrioritiesKey = "speakerPriorities"
    private let hiddenInputsKey = "hiddenMics"
    private let hiddenOutputsKey = "hiddenSpeakers"
    private let customNamesKey = "customDeviceNames"
    private let lockedInputVolumesKey = "lockedMicVolumes"
    private let lockedOutputVolumesKey = "lockedSpeakerVolumes"

    func customName(for device: AudioDevice) -> String? {
        customNames()[device.uid]
    }

    func setCustomName(_ name: String, for device: AudioDevice) {
        var names = customNames()
        names[device.uid] = name
        defaults.set(names, forKey: customNamesKey)
    }

    func restoreOriginalName(for device: AudioDevice) {
        var names = customNames()
        names.removeValue(forKey: device.uid)
        defaults.set(names, forKey: customNamesKey)
    }

    func lockedVolumes(for type: AudioDeviceType) -> [String: Float] {
        let key = type == .input ? lockedInputVolumesKey : lockedOutputVolumesKey
        let values = defaults.dictionary(forKey: key) ?? [:]

        return values.reduce(into: [:]) { result, item in
            if let number = item.value as? NSNumber {
                result[item.key] = number.floatValue
            }
        }
    }

    func setLockedVolume(_ volume: Float?, for device: AudioDevice) {
        let key = device.type == .input ? lockedInputVolumesKey : lockedOutputVolumesKey
        var values = lockedVolumes(for: device.type)
        values[device.uid] = volume
        defaults.set(values, forKey: key)
    }

    private func customNames() -> [String: String] {
        let values = defaults.dictionary(forKey: customNamesKey) ?? [:]

        return values.reduce(into: [:]) { result, item in
            if let name = item.value as? String {
                result[item.key] = name
            }
        }
    }

    func hiddenUIDs(for type: AudioDeviceType) -> Set<String> {
        let key = type == .input ? hiddenInputsKey : hiddenOutputsKey
        let hidden = defaults.array(forKey: key) as? [String] ?? []
        return Set(hidden)
    }

    func hideDevice(_ device: AudioDevice) {
        if device.type == .input {
            var hidden = defaults.array(forKey: hiddenInputsKey) as? [String] ?? []
            if !hidden.contains(device.uid) {
                hidden.append(device.uid)
                defaults.set(hidden, forKey: hiddenInputsKey)
            }
            return
        }

        var hidden = defaults.array(forKey: hiddenOutputsKey) as? [String] ?? []
        if !hidden.contains(device.uid) {
            hidden.append(device.uid)
            defaults.set(hidden, forKey: hiddenOutputsKey)
        }
    }

    func unhideDevice(_ device: AudioDevice) {
        if device.type == .input {
            var hidden = defaults.array(forKey: hiddenInputsKey) as? [String] ?? []
            hidden.removeAll { $0 == device.uid }
            defaults.set(hidden, forKey: hiddenInputsKey)
            return
        }

        var hiddenOutputs = defaults.array(forKey: hiddenOutputsKey) as? [String] ?? []
        hiddenOutputs.removeAll { $0 == device.uid }
        defaults.set(hiddenOutputs, forKey: hiddenOutputsKey)
    }

    func sortByPriority(_ devices: [AudioDevice], type: AudioDeviceType) -> [AudioDevice] {
        let priorities = priorityList(for: type)
        let indexByUid = Dictionary(uniqueKeysWithValues: priorities.enumerated().map { ($0.element, $0.offset) })

        return devices.sorted { a, b in
            let indexA = indexByUid[a.uid] ?? Int.max
            let indexB = indexByUid[b.uid] ?? Int.max
            return indexA < indexB
        }
    }

    func savePriorities(_ devices: [AudioDevice], type: AudioDeviceType) {
        let key = type == .input ? inputPrioritiesKey : outputPrioritiesKey
        let uids = devices.map { $0.uid }
        defaults.set(uids, forKey: key)
    }

    private func priorityList(for type: AudioDeviceType) -> [String] {
        if type == .input {
            return defaults.array(forKey: inputPrioritiesKey) as? [String] ?? []
        }

        return defaults.array(forKey: outputPrioritiesKey) as? [String] ?? []
    }
}
