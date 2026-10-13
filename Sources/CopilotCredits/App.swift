import AppKit
import CreditsCore

@main
struct CopilotCreditsApp {
    @MainActor
    static func main() {
        // Uses exactly the same gh client and decoder as the widget.
        if CommandLine.arguments.contains("--check") {
            Task {
                do {
                    let quota = try await GitHubClient().fetch()
                    var tracker = BudgetTracker()
                    let budget = try tracker.update(quota)
                    print("OK: \(budget.remaining) Credits, \(budget.days) Tage, \(budget.dailyBudget) Credits/Tag")
                    exit(0)
                } catch {
                    fputs("\(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            RunLoop.main.run()
        } else {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
