//
//  ClaudeUsageTrackerApp.swift
//  Claude Usage Tracker
//
//  Copyright © 2025 Sergio Bañuls. All rights reserved.
//  Licensed under Personal Use License (Non-Commercial)
//

import SwiftUI
import Combine

@main
struct ClaudeUsageTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var manager = ClaudeUsageManager()
    var localizationManager = LocalizationManager()
    var pricingManager = PricingManager()
    var currencyManager = CurrencyManager()
    var liteLLMManager = LiteLLMManager()
    var updateManager = UpdateManager()
    var preferencesManager = PreferencesManager()
    private var timer: Timer?
    private var updateCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Vincular managers con el manager de datos
        manager.pricingManager = pricingManager
        manager.localizationManager = localizationManager
        manager.liteLLMManager = liteLLMManager
        manager.accountFilter = preferencesManager.accountFilter

        // Check for updates on startup
        Task {
            await updateManager.checkForUpdates()
        }

        // Crear item en la barra de menú
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "💰 ..."
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Observar cambios en el manager para actualizar la barra de menú
        manager.onDataUpdated = { [weak self] in
            self?.updateMenuBarTitle()
        }

        manager.onLoadingStateChanged = { [weak self] isLoading in
            if isLoading {
                self?.showLoading()
            }
        }

        // Fetch exchange rate initially
        currencyManager.fetchExchangeRate()

        // Observe language changes to fetch exchange rate and update menu bar
        localizationManager.$currentLanguage
            .sink { [weak self] _ in
                self?.currencyManager.fetchExchangeRate()
                // Update immediately with current rate (format changes even if rate doesn't)
                DispatchQueue.main.async {
                    self?.updateMenuBarTitle()
                }
            }
            .store(in: &cancellables)

        // Observe exchange rate changes to update menu bar
        currencyManager.$exchangeRate
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateMenuBarTitle()
                }
            }
            .store(in: &cancellables)

        // Observe update availability to update menu bar
        updateManager.$updateAvailable
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateMenuBarTitle()
                }
            }
            .store(in: &cancellables)

        // Observe cost visibility preference changes to update menu bar
        preferencesManager.$showCostInStatusBar
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateMenuBarTitle()
                }
            }
            .store(in: &cancellables)

        // Observe account filter changes to reload data
        preferencesManager.$accountFilter
            .dropFirst() // Skip initial value
            .sink { [weak self] newFilter in
                self?.manager.accountFilter = newFilter
                self?.manager.loadData(showLoading: true)
            }
            .store(in: &cancellables)

        // Cargar datos iniciales (sin mostrar loading)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.manager.loadData(showLoading: false)
        }

        // Update every 5 minutes (reduced from 60s to minimize CPU usage)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.manager.loadData(showLoading: false)
        }

        // Check for updates every 2 hours
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 7200, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updateManager.checkForUpdates()
            }
        }

        // Register for app termination to clean up resources
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
        stopMonitoringClicksOutside()
    }
    
    @objc func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
        stopMonitoringClicksOutside()
    }

    func startMonitoringClicksOutside() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                self?.closePopover()
            }
        }
    }

    func stopMonitoringClicksOutside() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    func showPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 450, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MainView()
                .environmentObject(manager)
                .environmentObject(localizationManager)
                .environmentObject(pricingManager)
                .environmentObject(currencyManager)
                .environmentObject(liteLLMManager)
                .environmentObject(updateManager)
                .environmentObject(preferencesManager)
        )
        self.popover = popover

        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        startMonitoringClicksOutside()
    }
    
    func updateMenuBarTitle() {
        if let button = statusItem?.button {
            let displayText: String

            if preferencesManager.showCostInStatusBar {
                let cost = manager.currentMonthCost
                displayText = currencyManager.formatAmount(cost, language: localizationManager.currentLanguage)
            } else {
                displayText = "***"
            }

            // Use attributed string for smaller colored dot
            if updateManager.updateAvailable {
                let attributedString = NSMutableAttributedString()
                attributedString.append(NSAttributedString(string: "💰 \(displayText) "))

                // Add small orange dot centered vertically
                let dotAttributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.orange,
                    .font: NSFont.systemFont(ofSize: 8, weight: .bold),
                    .baselineOffset: 2  // Raise the dot to center it with the text
                ]
                attributedString.append(NSAttributedString(string: "●", attributes: dotAttributes))

                button.attributedTitle = attributedString
            } else {
                button.title = "💰 \(displayText)"
            }
        }
    }
    
    func showLoading() {
        if let button = statusItem?.button {
            button.title = "💰 ..."
        }
    }
}
