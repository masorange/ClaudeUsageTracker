import SwiftUI
import UsageCore

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var currency: CurrencyService
    @ObservedObject var updates: UpdateChecker
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showingSettings {
                SettingsView(model: model, prefs: prefs)
            } else {
                content
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .environment(\.locale, prefs.language.locale)
    }

    private var money: (Double) -> String {
        { currency.format($0, currency: prefs.currency, language: prefs.language) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(showingSettings ? prefs.tr("Settings", "Ajustes") : monthTitle)
                .font(.headline)
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isLoading)
            .help(prefs.tr("Refresh", "Actualizar"))
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "xmark.circle" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help(prefs.tr("Settings", "Ajustes"))
        }
        .padding(12)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = prefs.language.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let title = formatter.string(from: model.report?.monthStart ?? Date())
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    @ViewBuilder
    private var content: some View {
        if let report = model.report {
            VStack(alignment: .leading, spacing: 0) {
                statusBanner
                BudgetCard(report: report, prefs: prefs, money: money)
                Divider()
                TokensChart(report: report, prefs: prefs, money: money)
                Divider()
                ModelList(models: report.models, prefs: prefs, money: money)
            }
        } else if model.state == .needsLogin {
            LoginPromptView(prefs: prefs) { signIn() }
        } else if model.isLoading || model.state == .idle || model.state == .ok {
            LoadingView(prefs: prefs)
        } else {
            ErrorStateView(message: errorMessage ?? "", prefs: prefs) {
                Task { await model.refresh() }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if model.state == .needsLogin {
            BannerView(text: prefs.tr("Your session expired. Sign in to update the data.",
                                      "La sesión ha caducado. Inicia sesión para actualizar los datos."),
                       actionTitle: prefs.tr("Sign in", "Iniciar sesión"), action: signIn)
        } else if let errorMessage {
            BannerView(text: errorMessage, actionTitle: prefs.tr("Retry", "Reintentar")) {
                Task { await model.refresh() }
            }
        }
    }

    private var errorMessage: String? {
        switch model.state {
        case .offline:
            return prefs.tr("No connection. Showing the last data received.",
                            "Sin conexión. Se muestran los últimos datos recibidos.")
        case .apiChanged:
            return prefs.tr("AI Platform changed its data format. Check for an app update.",
                            "AI Platform ha cambiado el formato de los datos. Busca una actualización de la app.")
        case .failed(let detail):
            return prefs.tr("Could not load data (\(detail)).", "No se pudieron cargar los datos (\(detail)).")
        default:
            return nil
        }
    }

    private func signIn() {
        model.signIn(title: prefs.tr("Sign in to AI Platform", "Iniciar sesión en AI Platform"))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(freshnessText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if updates.updateAvailable {
                Button(prefs.tr("Update to \(updates.latestVersion)", "Actualizar a \(updates.latestVersion)")) {
                    updates.openReleasePage()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            Text("v\(AppInfo.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(prefs.tr("Quit", "Salir"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var freshnessText: String {
        guard let updated = model.report?.dataUpdatedAt ?? model.lastSuccess else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = prefs.language.locale
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: updated, relativeTo: Date())
        return prefs.tr("Data updated \(relative)", "Datos actualizados \(relative)")
    }
}
