import Cocoa
import Combine
import ApplicationServices
import QuartzCore

final class HapticEngine: ObservableObject {
    @Published var isTracking = true {
        didSet {
            transition.reset()
            lastPoint = nil
            refreshStatus()
        }
    }
    @Published private(set) var status = "Checking Accessibility…"
    @Published private(set) var accessibility = false
    @Published private(set) var detectedRole = "None"
    @Published private(set) var detectedSubrole = ""
    @Published private(set) var detectedProfile = "None"
    @Published private(set) var detectedTitle = ""
    @Published private(set) var detectedApp = ""
    @Published private(set) var observedRole = "None"
    @Published private(set) var observedSubrole = ""
    @Published private(set) var entries = 0
    @Published private(set) var eventLog: [String] = []
    @Published private(set) var roleObservations: [RoleObservation] = []
    @Published private(set) var sets: [NamedHapticProfile] = []
    @Published private(set) var activeSetID = ""
    @Published private(set) var profiles: [ControlProfile] = []
    @Published private(set) var enhancedStatus = "Standard haptics"
    @Published var enhancedEnabled = false {
        didSet {
            if enhancedEnabled { startEnhanced() } else { stopEnhanced() }
        }
    }
    private var enhancedBridge: EnhancedHapticBridge?


    private let storeKey = "hapticNamedProfiles.v2"
    private let reader = AXScanner()
    private var timer: Timer?
    private var lastPoint: CGPoint?
    private var transition = EntryLogic()
    private var lastTick = 0.0
    private var lastProbe = 0.0
    private var lastTrustCheck = 0.0
    private var observationKey = ""

    init() {
        let state: StoredProfileSettings
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let restored = try? JSONDecoder().decode(StoredProfileSettings.self, from: data) {
            state = ProfileCatalog.normalized(restored)
        } else {
            state = ProfileCatalog.initial()
        }
        // One-time migration. Remove legacy 2/3-pulse preferences that caused crashes.
        // Preserve profile names, role identities and style settings. Silent stays Off.
        var installed = state
        if !UserDefaults.standard.bool(forKey: "singleSnapMigration.v3") {
            for i in installed.profiles.indices {
                let silent = installed.profiles[i].name.caseInsensitiveCompare("Silent") == .orderedSame
                for j in installed.profiles[i].rules.indices {
                    installed.profiles[i].rules[j].emphasis = silent ? .off : .light
                }
            }
            UserDefaults.standard.set(true, forKey: "singleSnapMigration.v3")
            if let data = try? JSONEncoder().encode(installed) {
                UserDefaults.standard.set(data, forKey: storeKey)
            }
        }
        sets = installed.profiles
        activeSetID = installed.activeID
        profiles = installed.profiles.first(where: { $0.id == installed.activeID })?.rules ?? ProfileCatalog.defaultRules
        accessibility = AXIsProcessTrusted()
        refreshStatus()
    }

    func start() {
        guard timer == nil else { return }
        let ticker = Timer(timeInterval: 1.0 / 35.0, repeats: true) { [weak self] _ in self?.poll() }
        timer = ticker
        RunLoop.main.add(ticker, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        enhancedBridge?.stop()
        enhancedBridge = nil
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermission()
    }

    func selectSet(_ id: String) {
        guard let selected = sets.first(where: { $0.id == id }) else { return }
        activeSetID = id
        profiles = selected.rules
        transition.reset()
        save()
        log("Switched to profile: \(selected.name)")
    }

    @discardableResult
    func createSet(named rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 70 else { return false }
        let fresh = NamedHapticProfile(id: UUID().uuidString, name: name, rules: profiles)
        sets.append(fresh)
        selectSet(fresh.id)
        return true
    }

    @discardableResult
    func renameSet(to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 70,
              let index = sets.firstIndex(where: { $0.id == activeSetID }) else { return false }
        sets[index].name = name
        save()
        log("Renamed profile to \(name)")
        return true
    }

    func deleteCurrentSet() {
        guard sets.count > 1, let index = sets.firstIndex(where: { $0.id == activeSetID }) else { return }
        let name = sets[index].name
        sets.remove(at: index)
        selectSet(sets[0].id)
        log("Deleted profile: \(name)")
    }

    func rule(_ id: String) -> ControlProfile? {
        profiles.first(where: { $0.id == id })
    }

    func editRule(_ id: String, style: HapticStyle? = nil, emphasis: HapticEmphasis? = nil) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let style = style { profiles[index].style = style }
        if let emphasis = emphasis { profiles[index].emphasis = emphasis }
        syncRules()
    }

    func applyToAll(style: HapticStyle, emphasis: HapticEmphasis) {
        for index in profiles.indices {
            profiles[index].style = style
            profiles[index].emphasis = emphasis
        }
        syncRules()
        log("Set ALL roles to \(style.label), \(emphasis.label)")
    }

    func silenceAll() {
        for index in profiles.indices { profiles[index].emphasis = .off }
        syncRules()
        log("All roles silenced")
    }

    func addObservedRole(_ role: String) {
        guard role.hasPrefix("AX"), !profiles.contains(where: { $0.id == role }) else { return }
        profiles.append(ProfileCatalog.make(role, role, emphasis: .light))
        syncRules()
        log("Added role: \(role) (Level 1)")
    }

    func testRule(_ id: String) {
        guard let selected = rule(id) else { return }
        play(selected)
        log("TEST \(selected.label) — \(selected.style.label), \(selected.emphasis.label)")
    }

    func test(style: HapticStyle, emphasis: HapticEmphasis) {
        play(ProfileCatalog.make("test", "Test", style: style, emphasis: emphasis))
    }

    func resetCount() {
        entries = 0
        eventLog.removeAll()
        roleObservations.removeAll()
        observationKey = ""
        log("Counters cleared")
    }

    func copyDiagnostics() {
        let rules = profiles.map { "\($0.id)=\($0.style.label)/\($0.emphasis.label)" }.joined(separator: ", ")
        let seen = roleObservations.map { "\($0.role) [\($0.subrole)] \($0.app) x\($0.count)" }
        let activeName = sets.first(where: { $0.id == activeSetID })?.name ?? "Unknown"
        let report = [
            "Menu Magnet Haptic Profiles v3.0.1 — diagnostics",
            "Haptic mode: \(enhancedStatus)",
            "Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Accessibility: \(AXIsProcessTrusted())",
            "Tracking: \(isTracking)",
            "Active profile: \(activeName)",
            "Saved profiles: \(sets.map(\.name).joined(separator: ", "))",
            "Raw AX role: \(observedRole) / \(observedSubrole)",
            "Matched control: \(detectedRole) / \(detectedSubrole)",
            "Control profile: \(detectedProfile)",
            "Title: \(detectedTitle)",
            "App: \(detectedApp)",
            "Haptic entries: \(entries)",
            "Status: \(status)",
            "Configured roles: \(rules)",
            "Observed roles:"
        ] + seen + ["Recent events:"] + eventLog
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.joined(separator: "\n"), forType: .string)
        log("Diagnostics copied")
    }

    private func syncRules() {
        guard let index = sets.firstIndex(where: { $0.id == activeSetID }) else { return }
        sets[index].rules = profiles
        save()
    }

    private func save() {
        let state = StoredProfileSettings(activeID: activeSetID, profiles: sets)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func refreshStatus() {
        status = !accessibility ? "Accessibility approval needed" : (isTracking ? "Tracking accessible controls" : "Paused")
    }

    private func refreshPermission() {
        let granted = AXIsProcessTrusted()
        if granted != accessibility {
            accessibility = granted
            transition.reset()
            lastPoint = nil
        }
        refreshStatus()
    }

    // AX hit-testing can re-enter this app's SwiftUI views. On macOS 27.3, doing
    // this from a background DispatchQueue causes MainActor isolation traps.
    // Keep the entire hit-test on the main thread, where the timer also runs.
    private func poll() {
        guard Thread.isMainThread else { return }
        let now = CACurrentMediaTime()
        if now - lastTrustCheck >= 1.0 { lastTrustCheck = now; refreshPermission() }
        guard isTracking, accessibility, now - lastProbe >= 0.05,
              let event = CGEvent(source: nil) else { return }
        let point = event.location
        if let previous = lastPoint, hypot(point.x - previous.x, point.y - previous.y) < 0.8 { return }
        lastPoint = point
        lastProbe = now
        let sample = reader.probe(at: point, ignoringPID: getpid(),
                                  supportedRoles: Set(profiles.map(\.id)))
        guard isTracking, accessibility else { return }
        apply(sample)
    }

    private func apply(_ sample: AXProbe) {
        observedRole = sample.observedRole
        observedSubrole = sample.observedSubrole
        let fingerprint = "\(sample.observedRole)|\(sample.observedSubrole)|\(sample.observedApp)"
        if fingerprint != observationKey,
           sample.observedRole != "Unavailable", sample.observedRole != "Unknown" {
            observationKey = fingerprint
            if let index = roleObservations.firstIndex(where: {
                $0.role == sample.observedRole && $0.subrole == sample.observedSubrole
            }) {
                roleObservations[index].count += 1
                roleObservations[index].app = sample.observedApp
            } else if roleObservations.count < 160 {
                roleObservations.append(RoleObservation(role: sample.observedRole,
                    subrole: sample.observedSubrole, count: 1, app: sample.observedApp))
            }
        }
        detectedRole = sample.hit?.role ?? "None"
        detectedSubrole = sample.hit?.subrole ?? ""
        detectedProfile = sample.hit?.profileKey ?? "None"
        detectedTitle = sample.hit?.title ?? ""
        detectedApp = sample.hit?.app ?? sample.observedApp
        let entered = transition.update(sample.hit?.key)
        if entered, let hit = sample.hit, let chosen = rule(hit.profileKey), chosen.emphasis != .off {
            let now = CACurrentMediaTime()
            if now - lastTick >= 0.105 {
                lastTick = now
                entries += 1
                play(chosen)
                log("ENTER \(hit.profileKey) / \(hit.role) / \(hit.title)")
            }
        }
    }

    private func startEnhanced() {
        enhancedBridge?.stop()
        let worker = EnhancedHapticBridge()
        enhancedBridge = worker
        enhancedStatus = "Starting experimental actuator…"
        worker.start { [weak self, weak worker] ready in
            guard let self = self, self.enhancedBridge === worker else { return }
            if ready {
                self.enhancedStatus = "Enhanced: hardware snap levels"
                self.log("Enhanced actuator ready")
            } else {
                self.enhancedStatus = "Enhanced unavailable — standard fallback"
                self.log("Enhanced helper unavailable or stopped; standard haptics remain available")
                // Do not automatically restart a failing private helper.
                self.enhancedBridge?.stop()
                self.enhancedBridge = nil
            }
        }
    }

    private func stopEnhanced() {
        enhancedBridge?.stop()
        enhancedBridge = nil
        enhancedStatus = "Standard haptics"
    }

    private func play(_ profile: ControlProfile) {
        guard profile.emphasis != .off else { return }
        // Exactly one request per boundary entry. Never schedule repeat ticks.
        if enhancedEnabled, enhancedBridge?.send(level: profile.emphasis.rawValue) == true {
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(profile.style.pattern, performanceTime: .now)
    }

    private func log(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        eventLog.insert("[\(time)] \(message)", at: 0)
        if eventLog.count > 36 { eventLog.removeLast() }
    }
}
