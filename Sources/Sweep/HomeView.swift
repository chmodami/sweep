import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isSearchFocused: Bool
    /// Linha para onde rolar; só muda pelas setas, para o mouse não fazer a lista andar sozinha.
    @State private var scrollTarget: URL?

    var body: some View {
        let apps = model.visibleApps
        let largest = max(model.apps.map(\.size).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 20) {
            searchField

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 6) {
                        Text(model.search.isEmpty ? "Apps" : "Resultados")
                        if !apps.isEmpty {
                            Text("\(apps.count)").monospacedDigit().foregroundStyle(.tertiary)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        Picker("Ordenar", selection: $model.sortOrder) {
                            ForEach(SortOrder.allCases) { order in
                                Label(order.title, systemImage: order.symbol).tag(order)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: model.sortOrder.symbol)
                                .contentTransition(.symbolEffect(.replace))
                            Text(model.sortOrder.title)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)

                if apps.isEmpty {
                    Text(model.apps.isEmpty ? "Carregando apps…" : "Nenhum app encontrado")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    Spacer(minLength: 0)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                                    AppRow(
                                        app: app,
                                        fraction: Double(app.size) / Double(largest),
                                        isHighlighted: index == model.highlighted
                                    )
                                    .id(app.id)
                                    .onHover { if $0 { model.highlighted = index } }
                                    .onTapGesture { model.select(app) }
                                }
                            }
                            .padding(.bottom, 12)
                        }
                        .scrollIndicators(.never)
                        .mask(fadeBelowFirstRows)
                        .onChange(of: scrollTarget) {
                            // Navegando pelo teclado, mantém a linha destacada entre as nítidas.
                            guard let scrollTarget else { return }
                            withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(scrollTarget, anchor: .center) }
                        }
                        .onChange(of: model.search) { proxy.scrollTo(apps.first?.id, anchor: .top) }
                        .onChange(of: model.sortOrder) { withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(model.visibleApps.first?.id, anchor: .top) } }
                    }
                }
            }

            HStack(spacing: 20) {
                KeyHint(symbol: "arrow.up.arrow.down", label: "navegar")
                KeyHint(symbol: "return", label: "abrir")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .animation(.smooth(duration: 0.22), value: apps.map(\.id))
        .onAppear { isSearchFocused = true }
    }

    /// As 5 primeiras linhas visíveis ficam nítidas; as de baixo vão sumindo até quase transparentes.
    private var fadeBelowFirstRows: some View {
        GeometryReader { proxy in
            let rowsHeight = 4.4 * 62.0 // o fade começa no meio da 5ª linha (cada linha: 60 pt + 2 pt de espaço)
            let start = min(rowsHeight / max(proxy.size.height, 1), 1)
            let end = min((rowsHeight + 90) / max(proxy.size.height, 1), 1)
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: start),
                    .init(color: .black.opacity(0.12), location: end),
                    .init(color: .black.opacity(0.06), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func moveHighlight(by offset: Int) {
        model.highlighted = min(max(model.highlighted + offset, 0), max(model.visibleApps.count - 1, 0))
        scrollTarget = model.highlightedApp?.id
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Buscar app", text: $model.search)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isSearchFocused)
                // Lê a lista atual na hora da tecla, não a capturada num render anterior.
                .onSubmit { if let app = model.highlightedApp { model.select(app) } }
                .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
            if !model.search.isEmpty {
                Button { model.search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
    }
}

struct AppRow: View {
    let app: InstalledApp
    let fraction: Double
    let isHighlighted: Bool

    var body: some View {
        let accent = Accent.color(for: app)
        HStack(spacing: 14) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 40, height: 40)
                .shadow(color: accent.opacity(isHighlighted ? 0.5 : 0.2), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(Format.bytes(app.size))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(isHighlighted ? .primary : .secondary)
                }
                SizeBar(fraction: fraction, color: accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(isHighlighted ? 0.08 : 0))
        }
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.15), value: isHighlighted)
    }
}

/// Barra proporcional ao tamanho do app em relação ao maior app instalado.
struct SizeBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(proxy.size.width * fraction, 4))
            }
        }
        .frame(height: 4)
    }
}

/// Tecla desenhada + legenda, para os atalhos do rodapé.
struct KeyHint: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
            Text(label)
                .font(.callout)
        }
        .foregroundStyle(.secondary)
    }
}
