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
                    let budget = try MonthlyBudget.calculate(quota)
                    print("OK: \(budget.usedThisPeriod)/\(budget.entitlement) Credits verbraucht (\(budget.percent) %)")
                    print("Tag \(budget.elapsedDays)/\(budget.totalDays): Ø \(budget.actualDaily), Soll \(budget.idealDaily) Credits/Tag")
                    print("Abweichung \(budget.deviationPercent) %, Prognose \(budget.projectedUsage) Credits: \(budget.fitsBudget ? "Budget reicht" : "Budget überschritten")")
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
