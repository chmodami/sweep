import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let apps = model.visibleApps
        let largest = max(model.apps.map(\.size).max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 20) {
            searchField

            VStack(alignment: .leading, spacing: 6) {
                Text(model.search.isEmpty ? "Maiores apps" : "Resultados")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 14)

                if apps.isEmpty {
                    Text(model.apps.isEmpty ? "Carregando apps…" : "Nenhum app encontrado")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                            AppRow(
                                app: app,
                                fraction: Double(app.size) / Double(largest),
                                isHighlighted: index == model.highlighted
                            )
                            .onHover { if $0 { model.highlighted = index } }
                            .onTapGesture { model.select(app) }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Label("navegar", systemImage: "arrow.up.arrow.down")
                Label("abrir", systemImage: "return")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .animation(.smooth(duration: 0.22), value: apps.map(\.id))
        .onAppear { isSearchFocused = true }
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
                .onKeyPress(.downArrow) { model.highlighted = min(model.highlighted + 1, model.visibleApps.count - 1); return .handled }
                .onKeyPress(.upArrow) { model.highlighted = max(model.highlighted - 1, 0); return .handled }
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
