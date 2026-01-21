import Foundation

final class PriorityManager {
    private let defaults = UserDefaults.standard

    private let inputPrioritiesKey = "inputPriorities"
    private let outputPrioritiesKey = "speakerPriorities"
    private let hiddenInputsKey = "hiddenMics"
    private let hiddenOutputsKey = "hiddenSpeakers"

    func isHidden(_ device: AudioDevice) -> Bool {
        if device.type == .input {
            let hidden = defaults.array(forKey: hiddenInputsKey) as? [String] ?? []
            return hidden.contains(device.uid)
        }
        return hiddenOutputs().contains(device.uid)
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

        return devices.sorted { a, b in
            let indexA = priorities.firstIndex(of: a.uid) ?? Int.max
            let indexB = priorities.firstIndex(of: b.uid) ?? Int.max
            return indexA < indexB
        }
    }

    func savePriorities(_ devices: [AudioDevice], type: AudioDeviceType) {
        let key = type == .input ? inputPrioritiesKey : outputPrioritiesKey
        let uids = devices.map { $0.uid }
        defaults.set(uids, forKey: key)
    }

    private func hiddenOutputs() -> Set<String> {
        let hiddenSpeakers = defaults.array(forKey: hiddenOutputsKey) as? [String] ?? []
        return Set(hiddenSpeakers)
    }

    private func priorityList(for type: AudioDeviceType) -> [String] {
        if type == .input {
            return defaults.array(forKey: inputPrioritiesKey) as? [String] ?? []
        }

        return defaults.array(forKey: outputPrioritiesKey) as? [String] ?? []
    }
}
