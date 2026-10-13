import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var catalog: CatalogModel
    @State private var changingKey = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Picker(prefs.tr("Menu bar shows", "Barra de menú"), selection: $prefs.menuBarMode) {
                ForEach(MenuBarMode.allCases) { mode in
                    Text(label(for: mode)).tag(mode)
                }
            }
            Picker(prefs.tr("Language", "Idioma"), selection: $prefs.language) {
                Text("Español").tag(AppLanguage.es)
                Text("English").tag(AppLanguage.en)
            }
            Picker(prefs.tr("Currency", "Moneda"), selection: $prefs.currency) {
                Text("USD ($)").tag(DisplayCurrency.usd)
                Text("EUR (€)").tag(DisplayCurrency.eur)
            }
            Picker(prefs.tr("Refresh every", "Actualizar cada"), selection: $prefs.refreshMinutes) {
                ForEach(Preferences.refreshOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            Toggle(prefs.tr("Open at login", "Abrir al iniciar el Mac"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        try LaunchAtLogin.set(enabled)
                        launchError = nil
                    } catch {
                        launchError = error.localizedDescription
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }
            Section(prefs.tr("LiteLLM key", "Key de LiteLLM")) {
                Text(keySourceLabel).foregroundStyle(.secondary)
                if changingKey {
                    APIKeyPrompt(catalog: catalog, prefs: prefs, onDone: { changingKey = false })
                } else {
                    HStack {
                        Button(prefs.tr("Change", "Cambiar")) { changingKey = true }
                        if catalog.keySource == .stored {
                            Button(prefs.tr("Forget", "Olvidar"), role: .destructive) { catalog.forgetKey() }
                        }
                    }
                }
            }
            Button(prefs.tr("Sign out", "Cerrar sesión"), role: .destructive) {
                Task { await model.signOut() }
            }
        }
        .formStyle(.grouped)
        .frame(height: 460)
    }

    private var keySourceLabel: String {
        switch catalog.keySource {
        case .stored: return prefs.tr("Saved in Keychain", "Guardada en el Llavero")
        case .detected: return prefs.tr("Detected in Claude Code", "Detectada en Claude Code")
        case .none: return prefs.tr("Not configured", "Sin configurar")
        }
    }

    private func label(for mode: MenuBarMode) -> String {
        switch mode {
        case .spend: return prefs.tr("Spend", "Gasto")
        case .spendAndPercent: return prefs.tr("Spend + %", "Gasto + %")
        case .percent: return prefs.tr("Budget %", "% del presupuesto")
        case .iconOnly: return prefs.tr("Icon only", "Solo icono")
        }
    }
}
