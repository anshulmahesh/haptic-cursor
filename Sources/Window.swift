import Cocoa
import SwiftUI

private enum EditorTab: String, CaseIterable, Identifiable {
    case profiles = "Profiles"
    case inspector = "Live inspector"
    var id: String { rawValue }
}

// Keep view-local editing controls in an ObservableObject rather than SwiftUI
// @State. Xcode 27's @State macro is absent from some Command Line Tools installs.
private final class EditorControls: ObservableObject {
    @Published var tab: EditorTab = .profiles
    @Published var profileName = ""
    @Published var filter = ""
    @Published var bulkPattern: HapticStyle = .alignment
    @Published var bulkEmphasis: HapticEmphasis = .light
    @Published var showDeleteConfirmation = false
}

struct HapticProfilerView: View {
    @ObservedObject var engine: HapticEngine
    @ObservedObject private var editor: EditorControls

    init(engine: HapticEngine) {
        self.engine = engine
        self.editor = EditorControls()
    }

    private var filteredRules: [ControlProfile] {
        let needle = editor.filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return engine.profiles }
        return engine.profiles.filter {
            $0.label.localizedCaseInsensitiveContains(needle) || $0.id.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 29))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Menu Magnet Haptic Profiles 3.0").font(.system(size: 22, weight: .semibold))
                    Text("Invisible Accessibility boundaries · Haptics only · No clicks or cursor changes")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(engine.accessibility && engine.isTracking ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(engine.status).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 15)

            HStack(spacing: 16) {
                Toggle("Track controls", isOn: $engine.isTracking)
                    .toggleStyle(.switch)
                if !engine.accessibility {
                    Button("Grant Accessibility") { engine.requestPermission() }
                }
                Spacer()
                Text("One snap per entry · no pointer changes")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    Toggle("Enhanced snap strength (experimental)", isOn: $engine.enhancedEnabled)
                        .toggleStyle(.switch)
                    Spacer()
                    Text(engine.enhancedStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Enabled only for this session. Uses a private trackpad API in a separate helper. If unsupported, standard haptics continue. Levels are distinct hardware waveforms, not calibrated force values.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 12)

            Picker("View", selection: $editor.tab) {
                ForEach(EditorTab.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if editor.tab == .profiles { profileEditor } else { inspector }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().padding(.top, 8).padding(.bottom, 10)
            HStack(spacing: 10) {
                Button("Copy diagnostics") { engine.copyDiagnostics() }
                Button("Reset event count") { engine.resetCount() }
                Spacer()
                Text("Settings save automatically")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(minWidth: 740, minHeight: 520)
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Saved profiles") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Picker("Active profile", selection: Binding(
                            get: { engine.activeSetID },
                            set: { engine.selectSet($0) }
                        )) {
                            ForEach(engine.sets) { item in Text(item.name).tag(item.id) }
                        }
                        .frame(maxWidth: 330)
                        Spacer()
                        Text("\(engine.sets.count) saved")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        TextField("New or renamed profile", text: $editor.profileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 185)
                        Button("New (copy current)") {
                            if engine.createSet(named: editor.profileName) { editor.profileName = "" }
                        }
                        .disabled(editor.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Rename current") {
                            if engine.renameSet(to: editor.profileName) { editor.profileName = "" }
                        }
                        .disabled(editor.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Delete current") { editor.showDeleteConfirmation = true }
                            .disabled(engine.sets.count <= 1)
                    }
                    Text("Create a named copy of the current configuration, then adjust its individual roles. Switch profiles instantly using the selector.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
            }
            .alert("Delete this profile?", isPresented: $editor.showDeleteConfirmation) {
                Button("Delete", role: .destructive) { engine.deleteCurrentSet() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The current saved profile will be deleted. Other profiles will be kept.")
            }

            GroupBox("Apply one setting to every control") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Picker("Pattern", selection: $editor.bulkPattern) {
                            ForEach(HapticStyle.allCases) { item in Text(item.label).tag(item) }
                        }
                        .frame(maxWidth: 230)
                        Picker("Strength", selection: $editor.bulkEmphasis) {
                            ForEach(HapticEmphasis.allCases) { item in Text(item.label).tag(item) }
                        }
                        .frame(maxWidth: 260)
                        Button("Preview") { engine.test(style: editor.bulkPattern, emphasis: editor.bulkEmphasis) }
                        Button("Apply to all") { engine.applyToAll(style: editor.bulkPattern, emphasis: editor.bulkEmphasis) }
                        Button("Set all Off") { engine.silenceAll() }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("One snap per entry. Enhanced mode uses different actuator waveforms for Levels 1–4. In standard mode, intensity cannot be changed; the selected Apple pattern is used.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            GroupBox("Individual UI elements") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Search AX role or control type", text: $editor.filter)
                            .textFieldStyle(.roundedBorder)
                        Text("\(filteredRules.count) roles")
                            .foregroundStyle(.secondary).font(.system(size: 12))
                    }
                    HStack {
                        Text("Element / Accessibility tag").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Pattern").frame(width: 142, alignment: .leading)
                        Text("Strength").frame(width: 140, alignment: .leading)
                        Text("Preview").frame(width: 62, alignment: .center)
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Divider()
                    ForEach(filteredRules) { rule in
                        roleRow(rule)
                        Divider().opacity(0.3)
                    }
                }
                .padding(8)
            }
        }
    }

    private func roleRow(_ rule: ControlProfile) -> some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.label).font(.system(size: 13, weight: .medium))
                Text(rule.id).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: Binding(
                get: { engine.rule(rule.id)?.style ?? rule.style },
                set: { engine.editRule(rule.id, style: $0) }
            )) {
                ForEach(HapticStyle.allCases) { style in Text(style.label).tag(style) }
            }
            .labelsHidden().frame(width: 142)
            Picker("", selection: Binding(
                get: { engine.rule(rule.id)?.emphasis ?? rule.emphasis },
                set: { engine.editRule(rule.id, emphasis: $0) }
            )) {
                ForEach(HapticEmphasis.allCases) { emphasis in Text(emphasis.shortLabel).tag(emphasis) }
            }
            .labelsHidden().frame(width: 140)
            Button("Test") { engine.testRule(rule.id) }
                .frame(width: 62)
        }
        .padding(.vertical, 2)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Live Accessibility inspector") {
                VStack(alignment: .leading, spacing: 10) {
                    detail("Raw role", engine.observedRole)
                    detail("Raw subrole", engine.observedSubrole)
                    detail("Matched role", engine.detectedRole)
                    detail("Configured group", engine.detectedProfile)
                    detail("Title", engine.detectedTitle)
                    detail("Application", engine.detectedApp)
                    detail("Entry haptics", String(engine.entries))
                    HStack(spacing: 10) {
                        Button("Add raw role to active profile") {
                            engine.addObservedRole(engine.observedRole)
                        }
                        .disabled(!engine.observedRole.hasPrefix("AX") || engine.rule(engine.observedRole) != nil)
                        Text("Newly discovered roles start at Level 1.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }
            GroupBox("UI roles observed during this session") {
                VStack(alignment: .leading, spacing: 8) {
                    if engine.roleObservations.isEmpty {
                        Text("Move over Finder files, Dock icons or scrollbars to identify their actual Accessibility tags.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(engine.roleObservations) { item in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.role).font(.system(size: 12, weight: .medium))
                                    Text("\(item.subrole.isEmpty ? "No subrole" : item.subrole) · \(item.app)")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("×\(item.count)").font(.system(size: 12)).monospacedDigit()
                                Button("Add") { engine.addObservedRole(item.role) }
                                    .disabled(engine.rule(item.role) != nil || !item.role.hasPrefix("AX"))
                            }
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(8)
            }
            GroupBox("Recent haptic events") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(engine.eventLog.prefix(18).enumerated()), id: \.offset) { item in
                        Text(item.element).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .lineLimit(2).multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.system(size: 13))
    }
}
