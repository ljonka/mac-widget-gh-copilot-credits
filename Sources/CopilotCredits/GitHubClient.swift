import Foundation
import CreditsCore

actor GitHubClient {
    func fetch() throws -> Quota {
        let candidates = [Bundle.main.object(forInfoDictionaryKey: "GHCliPath") as? String]
            .compactMap { $0 } + ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "")
                .split(separator: ":").map { "\($0)/gh" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw CreditsError.cli("gh fehlt. Bitte mit brew install gh installieren.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["api", "--hostname", "github.com", "/copilot_internal/user"]
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: timeout)
        defer { timeout.cancel() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CreditsError.cli(message.isEmpty ? "GitHub-Abfrage fehlgeschlagen (Zeitlimit 25 s)." : message)
        }
        return try Quota.decode(data)
    }
}
