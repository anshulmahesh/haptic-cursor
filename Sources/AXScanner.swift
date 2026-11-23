import Cocoa
import ApplicationServices
import CoreGraphics

// Pure observation: does not post mouse events, change focus, press UI elements, or draw overlays.
struct AXProbe {
    let hit: ElementHit?
    let observedRole: String
    let observedSubrole: String
    let observedApp: String
}

struct ElementHit {
    let key: String
    let role: String
    let subrole: String
    let title: String
    let profileKey: String
    let app: String
    let frame: CGRect
}

final class AXScanner {
    private let systemWide = AXUIElementCreateSystemWide()
    private let fallbackRoles: Set<String> = ["AXOutlineRow", "AXMenuExtra", "AXMenuBarButton"]

    init() { AXUIElementSetMessagingTimeout(systemWide, 0.12) }

    func probe(at point: CGPoint, ignoringPID: pid_t, supportedRoles: Set<String>) -> AXProbe {
        // Accessibility hit-testing can synchronously call NSHostingView.hitTest
        // in the target process. For our own window that means SwiftUI's
        // MainActor, so this function must never execute on a worker queue.
        guard Thread.isMainThread else {
            return AXProbe(hit: nil, observedRole: "Off-main probe blocked", observedSubrole: "", observedApp: "")
        }
        // Exclude our own window BEFORE system-wide AX hit-testing (checking
        // the PID of an AX result afterwards is too late to prevent re-entry).
        if isOverOwnWindow(point, ownPID: ignoringPID) {
            return AXProbe(hit: nil, observedRole: "Own app window", observedSubrole: "", observedApp: "")
        }
        var raw: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &raw)
        let result = raw.flatMap { scanAncestors($0, at: point, ignoringPID: ignoringPID, supportedRoles: supportedRoles) }
        let needsDockLookup = status != .success || result?.hit == nil ||
            (result?.observedApp == "com.apple.dock" && result?.hit?.role != "AXDockItem")
        if needsDockLookup {
            // Dock can expose its own hierarchy instead of ordinary app hit-testing.
            if let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier {
                let dock = AXUIElementCreateApplication(dockPID)
                AXUIElementSetMessagingTimeout(dock, 0.10)
                var dockHit: AXUIElement?
                if AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &dockHit) == .success,
                   let element = dockHit,
                   let dockResult = scanAncestors(element, at: point, ignoringPID: ignoringPID, supportedRoles: supportedRoles),
                   dockResult.hit?.role == "AXDockItem" {
                    return dockResult
                }
                if let found = findDockItem(dock, at: point, maxDepth: 5) {
                    return makeProbe(found, at: point, ignoringPID: ignoringPID, supportedRoles: supportedRoles)
                }
            }
        }
        if let resolved = result { return resolved }
        return AXProbe(hit: nil, observedRole: status == .success ? "Unknown" : "Unavailable", observedSubrole: "", observedApp: "")
    }

    private func isOverOwnWindow(_ point: CGPoint, ownPID: pid_t) -> Bool {
        // Window-server bounds and CGEvent mouse coordinates both use screen
        // space with the origin at the upper-left of the primary display.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                 as? [[String: Any]] else { return false }
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value == ownPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? NSNumber,
                  let y = bounds["Y"] as? NSNumber,
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber else { continue }
            let rect = CGRect(x: x.doubleValue, y: y.doubleValue,
                              width: width.doubleValue, height: height.doubleValue)
            if rect.contains(point) { return true }
        }
        return false
    }

    private func makeProbe(_ item: AXUIElement, at point: CGPoint, ignoringPID: pid_t, supportedRoles: Set<String>) -> AXProbe {
        scanAncestors(item, at: point, ignoringPID: ignoringPID, supportedRoles: supportedRoles) ?? AXProbe(hit: nil, observedRole: "Unknown", observedSubrole: "", observedApp: "")
    }

    private func scanAncestors(_ first: AXUIElement, at point: CGPoint, ignoringPID: pid_t, supportedRoles: Set<String>) -> AXProbe? {
        var current = first
        var detectedRole = "Unknown"
        var detectedSubrole = ""
        var detectedApp = ""
        var initial = true
        var possible: ElementHit?
        var finderCandidate: ElementHit?
        for _ in 0..<12 {
            var pid: pid_t = 0
            if AXUIElementGetPid(current, &pid) != .success { break }
            if pid == ignoringPID { return nil }
            let role = string(current, key: kAXRoleAttribute as CFString) ?? "Unknown"
            let subrole = string(current, key: kAXSubroleAttribute as CFString) ?? ""
            let appID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "PID \(pid)"
            if initial {
                detectedRole = role
                detectedSubrole = subrole
                detectedApp = appID
                initial = false
            }
            let isFinder = appID == "com.apple.finder"
            if let bar = attachedScrollbar(current, at: point) {
                return AXProbe(hit: makeHit(bar, pid: pid, appID: appID, at: point, forcedProfile: nil), observedRole: detectedRole, observedSubrole: detectedSubrole, observedApp: detectedApp)
            }
            if let frame = rect(current), frame.contains(point), frame.width >= 3, frame.height >= 3,
               frame.width <= 2700, frame.height <= 1700 {
                if isFinder && ["AXRow", "AXCell", "AXImage", "AXStaticText", "AXOutlineRow"].contains(role), finderCandidate == nil {
                    finderCandidate = makeHit(current, pid: pid, appID: appID, at: point, forcedProfile: "FinderItem")
                }
                if (supportedRoles.contains(role) || fallbackRoles.contains(role)), possible == nil {
                    possible = makeHit(current, pid: pid, appID: appID, at: point, forcedProfile: nil)
                }
            }
            guard let parent = attribute(current, key: kAXParentAttribute as CFString),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = parent as! AXUIElement
        }
        // Group Finder file icon and label into one logical file/folder profile.
        if let candidate = finderCandidate {
            return AXProbe(hit: candidate, observedRole: detectedRole, observedSubrole: detectedSubrole, observedApp: detectedApp)
        }
        if let candidate = possible {
            return AXProbe(hit: candidate, observedRole: detectedRole, observedSubrole: detectedSubrole, observedApp: detectedApp)
        }
        return AXProbe(hit: nil, observedRole: detectedRole, observedSubrole: detectedSubrole, observedApp: detectedApp)
    }

    private func attachedScrollbar(_ item: AXUIElement, at point: CGPoint) -> AXUIElement? {
        for key in ["AXVerticalScrollBar", "AXHorizontalScrollBar"] {
            guard let raw = attribute(item, key: key as CFString), CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let bar = raw as! AXUIElement
            if let geometry = rect(bar), geometry.width >= 2, geometry.height >= 2, geometry.contains(point) { return bar }
        }
        return nil
    }

    private func findDockItem(_ root: AXUIElement, at point: CGPoint, maxDepth: Int) -> AXUIElement? {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !stack.isEmpty && visited < 170 {
            let (item, depth) = stack.removeLast()
            visited += 1
            let role = string(item, key: kAXRoleAttribute as CFString) ?? ""
            if role == "AXDockItem", let frame = rect(item), frame.contains(point) { return item }
            if depth >= maxDepth { continue }
            guard let raw = attribute(item, key: kAXChildrenAttribute as CFString), CFGetTypeID(raw) == CFArrayGetTypeID() else { continue }
            let values = raw as! [AnyObject]
            for value in values.reversed() where CFGetTypeID(value) == AXUIElementGetTypeID() {
                stack.append((value as! AXUIElement, depth + 1))
            }
        }
        return nil
    }

    private func makeHit(_ item: AXUIElement, pid: pid_t, appID: String, at point: CGPoint, forcedProfile: String?) -> ElementHit? {
        guard let geometry = rect(item), geometry.contains(point) else { return nil }
        let role = string(item, key: kAXRoleAttribute as CFString) ?? "Unknown"
        let subrole = string(item, key: kAXSubroleAttribute as CFString) ?? ""
        let name = string(item, key: kAXTitleAttribute as CFString)
            ?? string(item, key: kAXDescriptionAttribute as CFString)
            ?? string(item, key: kAXHelpAttribute as CFString) ?? ""
        let profile = forcedProfile ?? role
        // Dock magnification changes the frame; its accessible name is a steadier identity.
        // Other elements use the geometry key already proven in the working v1 tester.
        let geometryKey = "\(Int(geometry.minX))|\(Int(geometry.minY))|\(Int(geometry.width))|\(Int(geometry.height))"
        let identity = (role == "AXDockItem" && !name.isEmpty) ? "dock|\(subrole)|\(name)" : geometryKey
        let key = "\(pid)|\(profile)|\(role)|\(identity)"
        return ElementHit(key: key, role: role, subrole: subrole, title: String(name.prefix(90)), profileKey: profile, app: appID, frame: geometry)
    }

    private func attribute(_ item: AXUIElement, key: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, key, &value) == .success else { return nil }
        return value
    }

    private func string(_ item: AXUIElement, key: CFString) -> String? {
        attribute(item, key: key) as? String
    }

    private func rect(_ item: AXUIElement) -> CGRect? {
        guard let p = attribute(item, key: kAXPositionAttribute as CFString),
              let s = attribute(item, key: kAXSizeAttribute as CFString),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        let pos = p as! AXValue, size = s as! AXValue
        guard AXValueGetType(pos) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(pos, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
}
