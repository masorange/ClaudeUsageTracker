import AppKit
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
    /// Providers whose accordion is open, persisted as a comma-separated list (first run: Anthropic only).
    @AppStorage("expandedProviders") private var expandedProvidersRaw = ModelProvider.anthropic.rawValue

    var body: some View {
        Group {
            if !catalog.isPrepared {
                LoadingView(prefs: prefs)
            } else if catalog.keySource == .none || changingKey {
                APIKeyPrompt(catalog: catalog, prefs: prefs, invalid: catalog.state == .invalidKey,
                             onDone: changingKey ? { changingKey = false } : nil)
            } else if catalog.entries.isEmpty && catalog.state == .invalidKey {
                APIKeyPrompt(catalog: catalog, prefs: prefs, invalid: true)
            } else if catalog.entries.isEmpty && catalog.state == .ok && !catalog.isLoading {
                ErrorStateView(message: prefs.tr("The proxy returned no models for your key.",
                                                 "El proxy no ha devuelto ningún modelo para tu key."),
                               prefs: prefs) { Task { await catalog.refresh() } }
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
        .task {
            catalog.prepare()
            await catalog.refreshIfStale()
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            banner
            searchField
            HStack {
                Picker(prefs.tr("Type", "Tipo"), selection: $kind) {
                    Text(prefs.tr("All", "Todos")).tag(ModelKind?.none)
                    Text("Chat").tag(ModelKind?.some(.chat))
                    Text("Embeddings").tag(ModelKind?.some(.embedding))
                    Text(prefs.tr("Image", "Imagen")).tag(ModelKind?.some(.image))
                    Text(prefs.tr("Other", "Otros")).tag(ModelKind?.some(.other))
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
                Text(prefs.tr("\(filtered.count) models", "\(filtered.count) modelos"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if groups.isEmpty {
                        Text(prefs.tr("No models match your search.", "Ningún modelo coincide con la búsqueda."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    }
                    ForEach(groups, id: \.provider) { group in
                        section(group.provider, entries: group.entries)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(height: 400)
            Text(prefs.tr("Current proxy prices per 1M tokens (list price struck through during campaigns)",
                          "Precios actuales del proxy por 1M tokens (tarifa tachada si hay campaña)"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var banner: some View {
        if catalog.state == .invalidKey {
            BannerView(text: prefs.tr("Your LiteLLM key is not valid or has expired.", "Tu key de LiteLLM no es válida o ha caducado."),
                       actionTitle: prefs.tr("Change", "Cambiar")) { changingKey = true }
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if let errorMessage {
            BannerView(text: errorMessage, actionTitle: prefs.tr("Retry", "Reintentar")) {
                Task { await catalog.refresh() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prefs.tr("Search model…", "Buscar modelo…"), text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .accessibilityLabel(prefs.tr("Clear search", "Borrar búsqueda"))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.25)))
    }

    private var expandedProviders: Set<String> {
        Set(expandedProvidersRaw.split(separator: ",").map(String.init))
    }

    /// While searching every provider with matches is shown open.
    private func isOpen(_ provider: ModelProvider) -> Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || expandedProviders.contains(provider.rawValue)
    }

    private func toggle(_ provider: ModelProvider) {
        var open = expandedProviders
        if open.contains(provider.rawValue) { open.remove(provider.rawValue) } else { open.insert(provider.rawValue) }
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedProvidersRaw = open.sorted().joined(separator: ",")
        }
    }

    private func section(_ provider: ModelProvider, entries: [CatalogEntry]) -> some View {
        let open = isOpen(provider)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                toggle(provider)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                    ProviderIconView(provider: provider, size: 16)
                    Text(provider == .other ? prefs.tr("Other", "Otros") : provider.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text("\(entries.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    Spacer()
                    if !open, let best = entries.compactMap(\.discount).max() {
                        Text(best >= 0.995 ? prefs.tr("Free models", "Modelos gratis")
                                           : prefs.tr("Up to −", "Hasta −") + Formatting.percent(best, locale: prefs.language.locale))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(provider.rawValue), \(entries.count)")
            .accessibilityHint(open ? prefs.tr("Collapse", "Contraer") : prefs.tr("Expand", "Desplegar"))
            if open {
                card(entries)
                    .transition(.opacity)
            }
        }
    }

    private func card(_ entries: [CatalogEntry]) -> some View {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().padding(.leading, 10)
                    }
                    row(entry)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15)))
    }

    // MARK: - Row

    private func row(_ entry: CatalogEntry) -> some View {
        let isExpanded = expanded == entry.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.isTest {
                    tag(prefs.tr("test", "prueba"))
                } else if entry.isAlias {
                    tag("alias")
                }
                Spacer(minLength: 4)
                if let discount = entry.discount {
                    campaignBadge(discount)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            HStack(spacing: 8) {
                if let context = entry.maxInputTokens {
                    Text("\(Formatting.tokens(context, locale: prefs.language.locale)) ctx")
                }
                Spacer(minLength: 4)
                if entry.discount != nil, let list = listPriceLine(entry) {
                    Text(list)
                        .strikethrough()
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Text(priceLine(entry))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            if isExpanded {
                details(entry)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .opacity(entry.hasPrice && !entry.isTest ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                expanded = isExpanded ? nil : entry.id
            }
        }
    }

    private func details(_ entry: CatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let read = entry.cacheReadPerMillion {
                detailLine(prefs.tr("Cache read", "Lectura de caché"), price(read))
            }
            if let write = entry.cacheWritePerMillion {
                detailLine(prefs.tr("Cache write", "Escritura de caché"), price(write))
            }
            if let output = entry.maxOutputTokens {
                detailLine(prefs.tr("Max output", "Salida máxima"),
                           "\(Formatting.tokens(output, locale: prefs.language.locale)) tokens")
            }
            HStack(spacing: 6) {
                Text(entry.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button(prefs.tr("Copy id", "Copiar id")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.id, forType: .string)
                }
                .buttonStyle(.link)
            }
            .padding(.top, 2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private func priceLine(_ entry: CatalogEntry) -> String {
        var parts: [String] = []
        if let input = entry.inputPerMillion {
            parts.append(prefs.tr("In \(price(input))", "Entrada \(price(input))"))
        }
        if let output = entry.outputPerMillion, output > 0 {
            parts.append(prefs.tr("Out \(price(output))", "Salida \(price(output))"))
        }
        return parts.isEmpty ? prefs.tr("No published list price", "Sin tarifa publicada") : parts.joined(separator: " · ")
    }

    /// Current campaign from the proxy's pricing (not this month's past usage).
    private func campaignBadge(_ discount: Double) -> some View {
        let text = discount >= 0.995
            ? prefs.tr("Free", "Gratis")
            : "−" + Formatting.percent(discount, locale: prefs.language.locale)
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
            .lineLimit(1)
            .help(prefs.tr("Campaign: the proxy currently charges less than the list price.",
                           "Campaña: el proxy cobra ahora menos que el precio de tarifa."))
    }

    private func listPriceLine(_ entry: CatalogEntry) -> String? {
        guard let input = entry.listInputPerMillion else { return nil }
        return price(input)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    // MARK: - Data

    private var filtered: [CatalogEntry] {
        ModelCatalog.filter(catalog.entries, kind: kind, query: query)
    }

    private var groups: [(provider: ModelProvider, entries: [CatalogEntry])] {
        ModelCatalog.grouped(filtered)
    }

    private var errorMessage: String? {
        switch catalog.state {
        case .offline:
            return prefs.tr("No connection. Showing the last catalog received.", "Sin conexión. Se muestra el último catálogo recibido.")
        case .keychainDenied:
            return prefs.tr("macOS denied access to the saved key. Open the tab again and choose \"Always Allow\", or save the key again.",
                            "macOS ha denegado el acceso a la key guardada. Vuelve a abrir la pestaña y elige \"Permitir siempre\", o guarda la key de nuevo.")
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
