import Foundation

@main
struct ProfileSettingsTests {
    static func main() throws {
        let initial = ProfileCatalog.initial()
        precondition(initial.profiles.count == 2)
        precondition(initial.profiles[0].name == "Default")
        precondition(initial.profiles[1].name == "Silent")
        precondition(initial.profiles[0].rules.count > 25)
        let allIDs = initial.profiles[0].rules.map(\.id)
        precondition(Set(allIDs).count == allIDs.count, "Roles must be unique")
        precondition(initial.profiles[1].rules.allSatisfy { $0.emphasis == .off })
        precondition(initial.profiles[0].rules.allSatisfy { $0.emphasis == .light }, "Every default role must start Level 1")
        precondition(HapticEmphasis.allCases.count == 5)
        precondition(HapticEmphasis.light.hardwareWaveform == 4)
        precondition(HapticEmphasis.medium.hardwareWaveform == 5)
        precondition(HapticEmphasis.firm.hardwareWaveform == 6)
        precondition(HapticEmphasis.hard.hardwareWaveform == 2)
        precondition(initial.profiles[0].rules.contains { $0.id == "AXDockItem" })
        precondition(initial.profiles[0].rules.contains { $0.id == "AXScrollBar" })
        precondition(initial.profiles[0].rules.contains { $0.id == "FinderItem" })
        let serialized = try JSONEncoder().encode(initial)
        let restored = try JSONDecoder().decode(StoredProfileSettings.self, from: serialized)
        precondition(restored.profiles.count == 2)
        precondition(restored.profiles[0].rules.count == initial.profiles[0].rules.count)
        let legacy = StoredProfileSettings(activeID: "missing", profiles: [NamedHapticProfile(
            id: "some", name: "Minimal", rules: [ProfileCatalog.make("AXButton", "Buttons")]
        )])
        let repaired = ProfileCatalog.normalized(legacy)
        precondition(repaired.activeID == "some")
        precondition(repaired.profiles[0].rules.contains { $0.id == "AXDockItem" })
        print("PASS: profile defaults, Silent, core roles, uniqueness, save/restore, normalization")
    }
}
