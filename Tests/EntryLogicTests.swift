import Foundation

@main
struct EntryLogicTests {
    static func main() {
        var state = EntryLogic()
        precondition(!state.update(nil), "Initial empty observation cannot tick")
        precondition(state.update("button"), "Entering button must tick")
        precondition(!state.update("button"), "Remaining on button must not repeat")
        precondition(state.update("slider"), "Moving to adjacent control must tick")
        precondition(!state.update(nil), "Exiting must not tick")
        precondition(state.update("button"), "Re-entry must tick")
        state.reset()
        precondition(!state.update("button"), "Initial observation after resetting is a baseline")
        print("PASS: initial baseline, enter, no repeat, adjacent entry, silent exit, re-entry, reset")
    }
}
