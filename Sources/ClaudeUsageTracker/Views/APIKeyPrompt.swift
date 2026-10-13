import SwiftUI

/// Asks for the LiteLLM key when none is stored or detected, or when the current one is rejected.
struct APIKeyPrompt: View {
    @ObservedObject var catalog: CatalogModel
    @ObservedObject var prefs: Preferences
    var invalid = false
    var onDone: (() -> Void)?
    @State private var key = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(invalid
                 ? prefs.tr("Your LiteLLM key is not valid or has expired", "Tu key de LiteLLM no es válida o ha caducado")
                 : prefs.tr("Add your LiteLLM key", "Añade tu key de LiteLLM"))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(prefs.tr("It is needed to list the models available to you. It is stored in your Mac's Keychain and only sent to llm.tools.cloud.masorange.es.",
                          "Hace falta para listar los modelos que tienes disponibles. Se guarda en el Llavero de tu Mac y solo se envía a llm.tools.cloud.masorange.es."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("sk-…", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                if let onDone {
                    Button(prefs.tr("Cancel", "Cancelar"), action: onDone)
                }
                Button(prefs.tr("Save", "Guardar"), action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(prefs.tr("You'll find it in your Claude Code configuration (ANTHROPIC_AUTH_TOKEN). Generating a new key in AI Platform invalidates the previous one.",
                          "La encontrarás en tu configuración de Claude Code (ANTHROPIC_AUTH_TOKEN). Generar una nueva en AI Platform invalida la anterior."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let value = key
        key = ""
        Task {
            await catalog.saveKey(value)
            onDone?()
        }
    }
}
