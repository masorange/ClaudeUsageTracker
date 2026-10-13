import AppKit
import Combine
import SwiftUI
import UsageCore

@main
enum Main {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences()
    private let currency = CurrencyService()
    private let updates = UpdateChecker()
    private let session = IAPSession()
    private lazy var model = AppModel(session: session)
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyCleanup.run()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(model: model, prefs: prefs, currency: currency, updates: updates)
        )

        model.objectWillChange
            .merge(with: prefs.objectWillChange, currency.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
        prefs.$refreshMinutes
            .removeDuplicates()
            .sink { [weak self] minutes in self?.model.startAutoRefresh(minutes: minutes) }
            .store(in: &cancellables)
        updateTitle()

        Task {
            await model.refresh()
            await currency.refreshIfNeeded()
            await updates.check()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
        Task { await model.refreshIfStale() }
    }

    private func updateTitle() {
        let locale = prefs.language.locale
        statusItem.button?.title = MenuBarTitle.make(
            report: model.report,
            state: model.state,
            mode: prefs.menuBarMode,
            money: { self.currency.format($0, currency: self.prefs.currency, language: self.prefs.language) },
            percent: { Formatting.percent($0, locale: locale) }
        )
    }
}
