import Foundation

// First observation is a baseline; we only tick on a subsequent entry.
struct EntryLogic {
    private(set) var previous: String? = nil
    private(set) var hasBaseline = false

    mutating func reset() { previous = nil; hasBaseline = false }

    mutating func update(_ next: String?) -> Bool {
        if !hasBaseline {
            previous = next
            hasBaseline = true
            return false
        }
        let entered = next != nil && next != previous
        previous = next
        return entered
    }
}
