import AppKit
import SwiftUI
import CreditsCore

@MainActor
final class WidgetModel: ObservableObject {
    @Published var budget: DailyBudget?
    @Published var error: String?
    @Published var updated: Date?
    private let client = GitHubClient()
    private var tracker: BudgetTracker
    private var refreshing = false
    private let stateURL: URL

    init() {
        stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CopilotCredits/state.json")
        tracker = (try? Data(contentsOf: stateURL))
            .flatMap { try? JSONDecoder().decode(BudgetTracker.self, from: $0) } ?? BudgetTracker()
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let quota = try await client.fetch()
            let result = try tracker.update(quota)
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try JSONEncoder().encode(tracker).write(to: stateURL, options: .atomic)
            budget = result
            updated = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct WidgetView: View {
    @ObservedObject var model: WidgetModel

    private var tint: Color {
        guard model.error == nil, let budget = model.budget else { return .gray }
        switch budget.tone {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func resetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd.MM.yyyy HH:mm 'UTC'"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Copilot · Heute").font(.headline)
                Spacer()
                Circle().fill(tint).frame(width: 9, height: 9)
            }
            if let budget = model.budget {
                Text("\(number(budget.percent)) %")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint)
                ProgressView(value: min(budget.percent, 100), total: 100).tint(tint)
                Text("\(number(budget.usedToday)) / \(number(budget.dailyBudget)) Credits heute")
                    .font(.subheadline).monospacedDigit()
                Text("\(number(budget.remaining)) übrig · \(budget.days) Tage inkl. heute")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Monat: \(number(budget.usedThisPeriod)) / \(number(budget.entitlement)) Credits")
                    .font(.caption).monospacedDigit()
                Text("Reset: \(resetDate(budget.reset))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model.error == nil ? "Credits werden geladen …" : "Keine aktuellen Daten")
                    .font(.subheadline)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .help(error)
            } else if let updated = model.updated {
                Text("Stand \(updated.formatted(date: .omitted, time: .shortened)) · Tag in UTC")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 300, height: 260, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(.dark)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = WidgetModel()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 260),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: WidgetView(model: model))
        placeOnDesktop()
        panel.setFrameAutosaveName("CopilotCreditsWidget")
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "Copilot Credits")
        let menu = NSMenu()
        menu.addItem(withTitle: "Jetzt aktualisieren", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Widget zurücksetzen", action: #selector(resetPosition), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func placeOnDesktop() {
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 320,
                                         y: screen.visibleFrame.maxY - 280))
        }
    }

    @objc private func resetPosition() { placeOnDesktop(); panel.orderFrontRegardless() }
    @objc private func refresh() { Task { await model.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }
}
