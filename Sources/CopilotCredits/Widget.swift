import AppKit
import SwiftUI
import CreditsCore

@MainActor
final class WidgetModel: ObservableObject {
    @Published var budget: MonthlyBudget?
    @Published var error: String?
    @Published var updated: Date?
    private let client = GitHubClient()
    private var refreshing = false

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let quota = try await client.fetch()
            budget = try MonthlyBudget.calculate(quota)
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
                Text("Copilot · Monat").font(.system(size: 18, weight: .semibold))
                Spacer()
                Circle().fill(tint).frame(width: 9, height: 9)
            }
            .overlay(WidgetDragHandle())
            .help("Zum Verschieben hier ziehen")
            if let budget = model.budget {
                Text("\(number(budget.percent)) %")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit().foregroundStyle(tint)
                ProgressView(value: min(budget.percent, 100), total: 100).tint(tint)
                Text("\(number(budget.usedThisPeriod)) / \(number(budget.entitlement)) Credits verbraucht")
                    .font(.system(size: 14)).monospacedDigit()
                Text("\(number(budget.remaining)) übrig · Tag \(budget.elapsedDays) / \(budget.totalDays)")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Divider()
                Text("Ø Tag: \(number(budget.actualDaily)) · Soll: \(number(budget.idealDaily)) Credits")
                    .font(.system(size: 14)).monospacedDigit()
                Text("\(budget.deviationPercent > 0 ? "+" : "")\(number(budget.deviationPercent)) % gegenüber Gleichverteilung")
                    .font(.system(size: 14)).foregroundStyle(model.error != nil ? Color.gray : (budget.fitsBudget ? .green : .red))
                Text("Prognose: \(number(budget.projectedUsage)) / \(number(budget.entitlement)) Credits")
                    .font(.system(size: 14)).monospacedDigit()
                Text(budget.fitsBudget ? "Budget reicht bis Monatsende" : "Budget wird voraussichtlich überschritten")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(model.error != nil ? Color.gray : (budget.fitsBudget ? .green : .red))
                Text("Reset: \(resetDate(budget.reset))")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            } else {
                Text(model.error == nil ? "Credits werden geladen …" : "Keine aktuellen Daten")
                    .font(.system(size: 14))
            }
            if let error = model.error {
                Text(error).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(3)
                    .help(error)
            } else if let updated = model.updated {
                Text("Stand \(updated.formatted(date: .omitted, time: .shortened)) · Tage in UTC")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 400, height: 380, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(.dark)
    }
}

private struct WidgetDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = WidgetModel()
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = false
        // Native desktop widgets are two levels above desktop icons.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: WidgetView(model: model))
        placeOnDesktop()
        panel.setFrameAutosaveName("CopilotCreditsWidget")
        panel.setContentSize(NSSize(width: 400, height: 380))
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
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 420,
                                         y: screen.visibleFrame.maxY - 400))
        }
    }

    @objc private func resetPosition() { placeOnDesktop(); panel.orderFrontRegardless() }
    @objc private func refresh() { Task { await model.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }
}
