import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
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
            Button(prefs.tr("Sign out", "Cerrar sesión"), role: .destructive) {
                Task { await model.signOut() }
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
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
