import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let app: InstalledApp
    @State private var isConfirming = false

    var body: some View {
        let accent = Accent.color(for: app)
        VStack(spacing: 0) {
            HStack {
                Button { model.close() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(model.isRemoving)
                Spacer()
            }
            .padding(.horizontal, 22)

            hero(accent)

            // A busca costuma levar milissegundos: em vez de piscar um spinner, a lista só aparece com fade.
            ScrollView {
                if !model.isScanning {
                    VStack(alignment: .leading, spacing: 18) {
                        ItemCard(items: model.items.filter { $0.kind != .name }, accent: accent)
                        let maybe = model.items.filter { $0.kind == .name }
                        if !maybe.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Pode ser deste app — confira")
                                    .font(.caption.weight(.semibold))
                                    .textCase(.uppercase)
                                    .tracking(0.8)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 14)
                                ItemCard(items: maybe, accent: accent)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 4)
                    // Anima a lista como um bloco; sem isso cada linha animava a própria posição a partir do zero.
                    .geometryGroup()
                    .transition(.opacity)
                }
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .animation(.smooth(duration: 0.25), value: model.isScanning)
            // A barra flutua sobre a lista, que rola por baixo do vidro.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
                    .opacity(isConfirming ? 0 : 1)
            }
        }
        .overlay {
            if isConfirming {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.55)
                        .onTapGesture { isConfirming = false }
                        .transition(.opacity)
                    ConfirmPanel(
                        app: app,
                        message: confirmationMessage,
                        confirmTitle: model.moveToTrash ? "Mover para a Lixeira" : "Apagar",
                        onCancel: { isConfirming = false },
                        onConfirm: {
                            isConfirming = false
                            model.removeChecked()
                        }
                    )
                    .padding(14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .padding(.top, -30) // cobre também a faixa dos botões da janela
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.18), value: isConfirming)
    }

    private func hero(_ accent: Color) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: accent.opacity(0.55), radius: 22, y: 8)
                .padding(.bottom, 8)
            Text(app.name)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            Text(Format.bytes(model.isScanning ? app.size : model.checkedSize))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: model.checkedSize)
                .padding(.top, 6)
            Text(model.isScanning ? "Procurando arquivos…" : "selecionados de \(Format.bytes(model.totalSize)) encontrados")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 18)
    }

    private var confirmationMessage: String {
        let items = model.checkedItems
        let count = "\(items.count) \(items.count == 1 ? "item" : "itens") · \(Format.bytes(model.checkedSize))"
        var text = model.moveToTrash
            ? "\(count) vão para a Lixeira. O app será fechado se estiver aberto."
            : "\(count) serão apagados para sempre. O app será fechado se estiver aberto."
        if model.moveToTrash && items.contains(where: \.needsAdmin) {
            text += " Itens protegidos do sistema são apagados direto e pedem sua senha."
        }
        return text
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { model.moveToTrash.toggle() }
            } label: {
                Label(model.moveToTrash ? "Para a Lixeira" : "Apagar de vez",
                      systemImage: model.moveToTrash ? "trash" : "flame.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(model.moveToTrash ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.moveToTrash
                  ? "Os arquivos vão para a Lixeira. Clique para apagar permanentemente."
                  : "Os arquivos serão apagados permanentemente. Clique para usar a Lixeira.")

            Spacer(minLength: 0)

            Button { isConfirming = true } label: {
                HStack(spacing: 7) {
                    if model.isRemoving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text(model.isRemoving ? "Removendo…" : "Remover")
                }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.delete, modifiers: .command)
            .help("Remover os itens selecionados (⌘⌫)")
            .disabled(model.checkedItems.isEmpty || model.isScanning || model.isRemoving)
        }
        .padding(.leading, 6)
        .padding(.trailing, 7)
        .frame(height: 54)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 20)
    }
}

struct ItemCard: View {
    @EnvironmentObject private var model: AppModel
    let items: [FoundItem]
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            ForEach(items) { item in
                ItemRow(item: item, accent: accent, isOn: Binding(
                    get: { model.checked.contains(item.url) },
                    set: { isOn in
                        if isOn { model.checked.insert(item.url) } else { model.checked.remove(item.url) }
                    }
                ))
            }
        }
    }
}

struct ItemRow: View {
    let item: FoundItem
    let accent: Color
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        let category = item.category
        HStack(spacing: 12) {
            CheckCircle(isOn: isOn, color: accent)

            Group {
                if item.kind == .appBundle {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                } else {
                    Image(systemName: category.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(category.color.gradient, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.label)
                    .font(.body.weight(.medium))
                Text(item.url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(item.url.path)

            Spacer(minLength: 8)

            if isHovered {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Mostrar no Finder")
            }
            if item.needsAdmin {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Pede senha de administrador")
            }
            Text(Format.bytes(item.size))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(isHovered ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 14))
        .opacity(isOn ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.smooth(duration: 0.15)) { isOn.toggle() } }
        .onHover { isHovered = $0 }
    }
}

/// Confirmação da remoção, no lugar do diálogo padrão do sistema.
struct ConfirmPanel: View {
    let app: InstalledApp
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 60, height: 60)
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.red.gradient))
                    .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                    .offset(x: 6, y: 6)
            }

            VStack(spacing: 6) {
                Text("Remover \(app.name)?")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancelar").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)

                Button(action: onConfirm) {
                    Text(confirmTitle).font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.extraLarge)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }
}
