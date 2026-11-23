import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum HapticStyle: String, CaseIterable, Identifiable, Codable {
    case alignment, generic, levelChange
    var id: String { rawValue }
    var label: String {
        switch self {
        case .alignment: return "Alignment"
        case .generic: return "Generic"
        case .levelChange: return "Level Change"
        }
    }
    #if canImport(AppKit)
    var pattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .alignment: return .alignment
        case .generic: return .generic
        case .levelChange: return .levelChange
        }
    }
    #endif
}

// Each nonzero level triggers ONE hardware actuation, never repeated pulses.
// Enhanced mode selects empirical hardware waveforms (not calibrated force units).
// Public AppKit fallback always performs a single fixed-pattern tick.
enum HapticEmphasis: Int, CaseIterable, Identifiable, Codable {
    case off = 0, light = 1, medium = 2, firm = 3, hard = 4
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .light: return "Level 1 · Soft"
        case .medium: return "Level 2 · Medium"
        case .firm: return "Level 3 · Firm"
        case .hard: return "Level 4 · Hard"
        }
    }
    var shortLabel: String {
        switch self {
        case .off: return "Off"
        case .light: return "Level 1"
        case .medium: return "Level 2"
        case .firm: return "Level 3"
        case .hard: return "Level 4"
        }
    }
    // Empirical MultitouchSupport waveforms: light/medium/strong tap, hard click.
    var hardwareWaveform: Int32 {
        switch self {
        case .off: return 0
        case .light: return 4
        case .medium: return 5
        case .firm: return 6
        case .hard: return 2
        }
    }
}

struct ControlProfile: Codable, Equatable, Identifiable {
    var id: String                // AX role or the special logical key FinderItem
    var label: String
    var style: HapticStyle
    var emphasis: HapticEmphasis
}

struct NamedHapticProfile: Identifiable, Codable {
    var id: String
    var name: String
    var rules: [ControlProfile]
}

struct StoredProfileSettings: Codable {
    var activeID: String
    var profiles: [NamedHapticProfile]
}

struct RoleObservation: Identifiable {
    let role: String
    let subrole: String
    var count: Int
    var app: String
    var id: String { role + "|" + subrole }
}

enum ProfileCatalog {
    static let defaultRules: [ControlProfile] = [
        make("AXButton", "Buttons"),
        make("AXToolbarButton", "Toolbar buttons"),
        make("AXCheckBox", "Checkboxes"),
        make("AXSwitch", "Switches"),
        make("AXRadioButton", "Radio buttons"),
        make("AXPopUpButton", "Dropdown buttons"),
        make("AXComboBox", "Combo boxes"),
        make("AXTextField", "Text fields"),
        make("AXTextArea", "Text areas"),
        make("AXSearchField", "Search fields"),
        make("AXSlider", "Sliders"),
        make("AXIncrementor", "Steppers"),
        make("AXScrollBar", "Scrollbar track", style: .levelChange),
        make("AXValueIndicator", "Scrollbar thumb / indicator"),
        make("AXDockItem", "Dock icons"),
        make("FinderItem", "Finder files and folders"),
        make("AXRow", "List / table rows"),
        make("AXCell", "List / table cells"),
        make("AXImage", "Images and icons"),
        make("AXMenuItem", "Menu items"),
        make("AXMenuBarItem", "Menu-bar items"),
        make("AXMenuButton", "Menu buttons"),
        make("AXTab", "Tabs"),
        make("AXLink", "Links"),
        make("AXDisclosureTriangle", "Disclosure triangles"),
        make("AXStaticText", "Static text / labels"),
        make("AXScrollArea", "Whole scroll areas"),
        make("AXList", "Whole lists"),
        make("AXOutline", "Whole outlines"),
        make("AXTable", "Whole tables"),
        make("AXGroup", "Whole groups"),
        make("AXSplitGroup", "Split groups"),
        make("AXWindow", "Whole windows")
    ]

    static func make(_ id: String, _ label: String, style: HapticStyle = .alignment,
                     emphasis: HapticEmphasis = .light) -> ControlProfile {
        ControlProfile(id: id, label: label, style: style, emphasis: emphasis)
    }

    static func initial() -> StoredProfileSettings {
        let standard = NamedHapticProfile(id: UUID().uuidString, name: "Default", rules: defaultRules)
        let silent = NamedHapticProfile(id: UUID().uuidString, name: "Silent", rules: defaultRules.map {
            var item = $0
            item.emphasis = .off
            return item
        })
        return StoredProfileSettings(activeID: standard.id, profiles: [standard, silent])
    }

    static func normalized(_ stored: StoredProfileSettings) -> StoredProfileSettings {
        guard !stored.profiles.isEmpty else { return initial() }
        var result = stored
        let defaults = defaultRules
        for index in result.profiles.indices {
            let seen = Set(result.profiles[index].rules.map(\.id))
            result.profiles[index].rules.append(contentsOf: defaults.filter { !seen.contains($0.id) })
        }
        if !result.profiles.contains(where: { $0.id == result.activeID }) {
            result.activeID = result.profiles[0].id
        }
        return result
    }
}
