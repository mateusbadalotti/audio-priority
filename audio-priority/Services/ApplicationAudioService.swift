import AppKit
import CoreAudio
import Darwin

final class ApplicationAudioService: @unchecked Sendable {
    var onSourcesChanged: (([ApplicationAudioSource]) -> Void)?

    private var processListListener: AudioObjectPropertyListenerBlock?
    private var outputStateListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var engines: [AudioObjectID: ApplicationVolumeEngine] = [:]
    private var volumes: [AudioObjectID: Float] = [:]
    private var outputDeviceID: AudioObjectID?

    private static let maximumParentProcessDepth = 8

    private static let excludedProcessNames: Set<String> = [
        "coreaudiod",
        "audiomxd",
        "AudioComponentRegistrar"
    ]

    private static let browserIdentities = [
        BrowserIdentity(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            matches: ["safari", "webkit"]
        ),
        BrowserIdentity(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            matches: ["google.chrome", "google chrome"]
        ),
        BrowserIdentity(
            name: "Microsoft Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            matches: ["microsoft.edgemac", "microsoft edge"]
        ),
        BrowserIdentity(
            name: "Firefox",
            bundleIdentifier: "org.mozilla.firefox",
            matches: ["mozilla.firefox", "firefox"]
        ),
        BrowserIdentity(
            name: "Brave",
            bundleIdentifier: "com.brave.Browser",
            matches: ["brave.browser", "brave browser"]
        ),
        BrowserIdentity(
            name: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            matches: ["thebrowser", "arc helper"]
        ),
        BrowserIdentity(
            name: "Opera",
            bundleIdentifier: "com.operasoftware.Opera",
            matches: ["operasoftware", "opera helper"]
        ),
        BrowserIdentity(
            name: "Vivaldi",
            bundleIdentifier: "com.vivaldi.Vivaldi",
            matches: ["vivaldi"]
        )
    ]

    func getSources() -> [ApplicationAudioSource] {
        let processIDs = getAudioProcessIDs()
        return processIDs
            .compactMap(makeSource)
            .sorted {
                let nameComparison = $0.name.localizedStandardCompare($1.name)
                if nameComparison == .orderedSame {
                    return $0.processIdentifier < $1.processIdentifier
                }
                return nameComparison == .orderedAscending
            }
            .map { source in
                return ApplicationAudioSource(
                    id: source.id,
                    name: source.name,
                    icon: source.icon,
                    volume: volumes[source.id] ?? 1
                )
            }
    }

    func setOutputDevice(_ deviceID: AudioObjectID?) -> String? {
        guard outputDeviceID != deviceID else { return nil }
        outputDeviceID = deviceID

        let volumesToRestore = volumes.filter { $0.value < 1 }
        stopAllEngines()
        var firstError: String?

        for (processID, volume) in volumesToRestore {
            if let error = setVolume(volume, for: processID) {
                firstError = firstError ?? error
            }
        }
        return firstError
    }

    func setVolume(_ volume: Float, for processID: AudioObjectID) -> String? {
        let clampedVolume = min(max(volume, 0), 1)
        volumes[processID] = clampedVolume

        if clampedVolume >= 1 {
            engines.removeValue(forKey: processID)?.stop()
            return nil
        }

        if let engine = engines[processID] {
            engine.volume = clampedVolume
            return nil
        }

        guard let outputDeviceID else {
            return "No output device is available."
        }

        let engine = ApplicationVolumeEngine(
            outputDeviceID: outputDeviceID,
            processObjectID: processID
        )
        engine.volume = clampedVolume
        let status = engine.start()
        guard status == noErr else {
            volumes[processID] = 1
            engine.stop()
            return Self.message(for: status)
        }

        engines[processID] = engine
        return nil
    }

    func startListening() {
        guard processListListener == nil else { return }

        var address = Self.propertyAddress(kAudioHardwarePropertyProcessObjectList)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.refreshSources()
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
        if status == noErr {
            processListListener = listener
            syncOutputStateListeners()
        }
    }

    func stopListening() {
        if let processListListener {
            var address = Self.propertyAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                processListListener
            )
            self.processListListener = nil
        }
        removeAllOutputStateListeners()
        stopAllEngines()
    }

    private func getAudioProcessIDs() -> [AudioObjectID] {
        var address = Self.propertyAddress(kAudioHardwarePropertyProcessObjectList)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let processCount = Int(dataSize) / MemoryLayout<AudioObjectID>.stride
        var processIDs = [AudioObjectID](repeating: 0, count: processCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &processIDs
        ) == noErr else {
            return []
        }

        return processIDs
    }

    private func makeSource(for processID: AudioObjectID) -> RawAudioSource? {
        guard let pid = getPIDProperty(
            processID,
            selector: kAudioProcessPropertyPID
        ), pid != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let bundleIdentifier = getStringProperty(
            processID,
            selector: kAudioProcessPropertyBundleID
        ) ?? ""
        let runningApplication = NSRunningApplication(processIdentifier: pid)
        let processName = runningApplication?.localizedName ?? Self.processName(for: pid)
        guard !processName.isEmpty, !Self.isSystemAudioProcess(processName) else {
            return nil
        }

        let browser = Self.browserIdentity(
            bundleIdentifier: bundleIdentifier,
            processName: processName
        )
        let isProducingAudio = getBooleanProperty(
            processID,
            selector: kAudioProcessPropertyIsRunningOutput
        )
        guard bundleIdentifier != Bundle.main.bundleIdentifier,
              isProducingAudio else {
            return nil
        }

        let displayApplication = browser.flatMap { identity in
            NSRunningApplication.runningApplications(
                withBundleIdentifier: identity.bundleIdentifier
            ).first
        }

        return RawAudioSource(
            id: processID,
            processIdentifier: pid,
            name: browser?.name ?? processName,
            icon: displayApplication?.icon
                ?? runningApplication?.icon
                ?? Self.parentApplicationIcon(for: pid)
        )
    }

    private func refreshSources() {
        syncOutputStateListeners()
        removeEnginesForExitedProcesses()
        onSourcesChanged?(getSources())
    }

    private func syncOutputStateListeners() {
        let processIDs = Set(getAudioProcessIDs())

        for processID in processIDs where outputStateListeners[processID] == nil {
            var address = Self.propertyAddress(kAudioProcessPropertyIsRunningOutput)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                self.onSourcesChanged?(self.getSources())
            }
            let status = AudioObjectAddPropertyListenerBlock(
                processID,
                &address,
                DispatchQueue.main,
                listener
            )
            if status == noErr {
                outputStateListeners[processID] = listener
            }
        }

        for processID in Set(outputStateListeners.keys).subtracting(processIDs) {
            removeOutputStateListener(for: processID)
        }
    }

    private func removeOutputStateListener(for processID: AudioObjectID) {
        guard let listener = outputStateListeners.removeValue(forKey: processID) else {
            return
        }
        var address = Self.propertyAddress(kAudioProcessPropertyIsRunningOutput)
        AudioObjectRemovePropertyListenerBlock(
            processID,
            &address,
            DispatchQueue.main,
            listener
        )
    }

    private func removeAllOutputStateListeners() {
        for processID in Array(outputStateListeners.keys) {
            removeOutputStateListener(for: processID)
        }
    }

    private func getPIDProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> pid_t? {
        var address = Self.propertyAddress(selector)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.stride)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr ? value : nil
    }

    private func getBooleanProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        var address = Self.propertyAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.stride)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        return status == noErr && value != 0
    }

    private func getStringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = Self.propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.stride)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func removeEnginesForExitedProcesses() {
        let activeProcessIDs = Set(getAudioProcessIDs())
        for processID in Set(volumes.keys).subtracting(activeProcessIDs) {
            engines.removeValue(forKey: processID)?.stop()
            volumes.removeValue(forKey: processID)
        }
    }

    private func stopAllEngines() {
        engines.values.forEach { $0.stop() }
        engines.removeAll()
    }

    private static func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func processName(for pid: pid_t) -> String {
        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { nameBuffer.deallocate() }

        let length = proc_name(pid, nameBuffer, UInt32(MAXPATHLEN))
        guard length > 0 else { return "" }
        return String(cString: nameBuffer)
    }

    private static func parentApplicationIcon(for processIdentifier: pid_t) -> NSImage? {
        var currentProcessIdentifier = processIdentifier
        var visitedProcessIdentifiers: Set<pid_t> = [processIdentifier]

        for _ in 0..<maximumParentProcessDepth {
            guard let parentProcessIdentifier = parentProcessIdentifier(
                for: currentProcessIdentifier
            ), parentProcessIdentifier > 1,
               visitedProcessIdentifiers.insert(parentProcessIdentifier).inserted else {
                return nil
            }

            if let icon = NSRunningApplication(
                processIdentifier: parentProcessIdentifier
            )?.icon {
                return icon
            }
            currentProcessIdentifier = parentProcessIdentifier
        }
        return nil
    }

    private static func parentProcessIdentifier(for processIdentifier: pid_t) -> pid_t? {
        var processInfo = kinfo_proc()
        var processInfoSize = MemoryLayout<kinfo_proc>.stride
        var managementInformationBase = [
            CTL_KERN,
            KERN_PROC,
            KERN_PROC_PID,
            processIdentifier
        ]
        let status = sysctl(
            &managementInformationBase,
            UInt32(managementInformationBase.count),
            &processInfo,
            &processInfoSize,
            nil,
            0
        )
        guard status == 0, processInfoSize > 0 else { return nil }
        return processInfo.kp_eproc.e_ppid
    }

    private static func isSystemAudioProcess(_ name: String) -> Bool {
        excludedProcessNames.contains(name)
    }

    private static func browserIdentity(
        bundleIdentifier: String,
        processName: String
    ) -> BrowserIdentity? {
        let searchableValue = "\(bundleIdentifier) \(processName)".lowercased()
        return browserIdentities.first { browser in
            browser.matches.contains { searchableValue.contains($0) }
        }
    }

    private static func message(for status: OSStatus) -> String {
        let characters = [
            UInt8((UInt32(bitPattern: status) >> 24) & 0xff),
            UInt8((UInt32(bitPattern: status) >> 16) & 0xff),
            UInt8((UInt32(bitPattern: status) >> 8) & 0xff),
            UInt8(UInt32(bitPattern: status) & 0xff)
        ]
        let readableCode = characters.allSatisfy { $0 >= 32 && $0 <= 126 }
            ? String(bytes: characters, encoding: .ascii) ?? "\(status)"
            : "\(status)"
        return "Couldn’t control this source (Core Audio \(readableCode)). Check System Audio Recording access."
    }
}

private struct RawAudioSource {
    let id: AudioObjectID
    let processIdentifier: pid_t
    let name: String
    let icon: NSImage?
}

private struct BrowserIdentity {
    let name: String
    let bundleIdentifier: String
    let matches: [String]
}
