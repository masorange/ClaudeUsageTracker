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
    private let catalog = CatalogModel()
    private lazy var model = AppModel(session: session)
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyCleanup.run()
        installEditMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: DashboardView(model: model, prefs: prefs, currency: currency, updates: updates, catalog: catalog)
        )
        // Let the popover follow SwiftUI's size so it grows downwards from the menu bar instead of off-screen.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        model.objectWillChange
            .merge(with: prefs.objectWillChange, currency.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
        model.$report
            .sink { [weak self] report in self?.catalog.updateDiscounts(from: report) }
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

    /// Accessory apps have no main menu, so ⌘C/⌘V/⌘A would not reach the sign-in web view without this.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "ClaudeUsageTracker", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
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
