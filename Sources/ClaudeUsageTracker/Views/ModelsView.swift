import SwiftUI
import UsageCore

struct ModelsView: View {
    @ObservedObject var catalog: CatalogModel
    @ObservedObject var prefs: Preferences
    let price: (Double) -> String
    @State private var query = ""
    @State private var kind: ModelKind?
    @State private var expanded: String?
    @State private var changingKey = false

    var body: some View {
        Group {
            if catalog.keySource == .none || changingKey {
                APIKeyPrompt(catalog: catalog, prefs: prefs, invalid: catalog.state == .invalidKey,
                             onDone: changingKey ? { changingKey = false } : nil)
            } else if catalog.entries.isEmpty && catalog.state == .invalidKey {
                APIKeyPrompt(catalog: catalog, prefs: prefs, invalid: true)
            } else if catalog.entries.isEmpty && (catalog.isLoading || catalog.state == .idle || catalog.state == .ok) {
                LoadingView(prefs: prefs)
            } else if catalog.entries.isEmpty {
                ErrorStateView(message: errorMessage ?? "", prefs: prefs) {
                    Task { await catalog.refresh() }
                }
            } else {
                list
            }
        }
        .task { await catalog.refreshIfStale() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            if catalog.state == .invalidKey {
                BannerView(text: prefs.tr("Your LiteLLM key is not valid or has expired.", "Tu key de LiteLLM no es válida o ha caducado."),
                           actionTitle: prefs.tr("Change", "Cambiar")) { changingKey = true }
            } else if let errorMessage {
                BannerView(text: errorMessage, actionTitle: prefs.tr("Retry", "Reintentar")) {
                    Task { await catalog.refresh() }
                }
            }
            TextField(prefs.tr("Search model…", "Buscar modelo…"), text: $query)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $kind) {
                Text(prefs.tr("All", "Todos")).tag(ModelKind?.none)
                Text("Chat").tag(ModelKind?.some(.chat))
                Text("Embeddings").tag(ModelKind?.some(.embedding))
                Text(prefs.tr("Image", "Imagen")).tag(ModelKind?.some(.image))
                Text(prefs.tr("Other", "Otros")).tag(ModelKind?.some(.other))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.provider) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                row(entry)
                            }
                        } header: {
                            Text(group.provider.rawValue.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                                .background(.background)
                        }
                    }
                }
            }
            .frame(height: 400)
            Text(prefs.tr("\(filtered.count) models · LiteLLM list prices per 1M tokens",
                          "\(filtered.count) modelos · precios de tarifa de LiteLLM por 1M tokens"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var filtered: [CatalogEntry] {
        ModelCatalog.filter(catalog.entries, kind: kind, query: query)
    }

    private var groups: [(provider: ModelProvider, entries: [CatalogEntry])] {
        ModelCatalog.grouped(filtered)
    }

    private func row(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if entry.isTest {
                    tag(prefs.tr("test", "prueba"))
                } else if entry.isAlias {
                    tag("alias")
                }
                Spacer()
                if let context = entry.maxInputTokens {
                    Text("\(Formatting.tokens(context, locale: prefs.language.locale)) ctx")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let discount = entry.discount {
                    Text("−" + Formatting.percent(discount, locale: prefs.language.locale) + prefs.tr(" this month", " este mes"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            Text(priceLine(entry))
                .font(.caption)
                .foregroundStyle(.secondary)
            if expanded == entry.id {
                details(entry)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            expanded = expanded == entry.id ? nil : entry.id
        }
    }

    private func details(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let read = entry.cacheReadPerMillion {
                Text(prefs.tr("Cache read: \(price(read))", "Lectura de caché: \(price(read))"))
            }
            if let write = entry.cacheWritePerMillion {
                Text(prefs.tr("Cache write: \(price(write))", "Escritura de caché: \(price(write))"))
            }
            if let output = entry.maxOutputTokens {
                Text(prefs.tr("Max output: \(Formatting.tokens(output, locale: prefs.language.locale)) tokens",
                              "Salida máxima: \(Formatting.tokens(output, locale: prefs.language.locale)) tokens"))
            }
            HStack(spacing: 6) {
                Text(entry.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button(prefs.tr("Copy", "Copiar")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.id, forType: .string)
                }
                .buttonStyle(.link)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
    }

    private func priceLine(_ entry: CatalogEntry) -> String {
        guard entry.hasPrice else {
            return prefs.tr("no published list price", "sin tarifa publicada")
        }
        var parts: [String] = []
        if let input = entry.inputPerMillion {
            parts.append(prefs.tr("\(price(input)) input", "\(price(input)) entrada"))
        }
        if let output = entry.outputPerMillion, output > 0 {
            parts.append(prefs.tr("\(price(output)) output", "\(price(output)) salida"))
        }
        return parts.joined(separator: " · ") + " / 1M"
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var errorMessage: String? {
        switch catalog.state {
        case .offline:
            return prefs.tr("No connection. Showing the last catalog received.", "Sin conexión. Se muestra el último catálogo recibido.")
        case .apiChanged:
            return prefs.tr("LiteLLM changed its data format. Check for an app update.",
                            "LiteLLM ha cambiado el formato de los datos. Busca una actualización de la app.")
        case .failed(let detail):
            return prefs.tr("Could not load models (\(detail)).", "No se pudieron cargar los modelos (\(detail)).")
        default:
            return nil
        }
    }
}
