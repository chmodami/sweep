import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    let app: InstalledApp
    @State private var isConfirming = false

    var body: some View {
        let accent = Accent.color(for: app)
        VStack(spacing: 0) {
            TopBar {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { model.moveToTrash.toggle() }
                } label: {
                    Image(systemName: model.moveToTrash ? "trash" : "flame.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PillButtonStyle(foreground: model.moveToTrash ? .secondary : .orange, height: 32, iconOnly: true))
                .help(model.moveToTrash
                      ? "Files go to the Trash. Click to delete them permanently."
                      : "Files will be deleted permanently. Click to use the Trash.")

                Button { isConfirming = true } label: {
                    HStack(spacing: 6) {
                        if model.isRemoving {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text(model.isRemoving ? "Removing…" : "Remove")
                    }
                }
                .buttonStyle(PillButtonStyle(foreground: .white, solidFill: .red, height: 32))
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Remove the selected items (⌘⌫)")
                .disabled(model.checkedItems.isEmpty || model.isScanning || model.isRemoving)
            }

            hero(accent)

            // A busca costuma levar milissegundos: em vez de piscar um spinner, a lista só aparece com fade.
            ScrollView {
                if !model.isScanning {
                    VStack(alignment: .leading, spacing: 18) {
                        ItemCard(items: model.items.filter { $0.kind != .name }, accent: accent)
                        let maybe = model.items.filter { $0.kind == .name }
                        if !maybe.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Might belong to this app — check")
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
        }
        .overlay {
            if isConfirming {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.55)
                        .onTapGesture { isConfirming = false }
                        .transition(.opacity)
                    ConfirmPanel(
                        title: String(localized: "Remove \(app.name)?"),
                        message: confirmationMessage,
                        confirmTitle: model.moveToTrash ? String(localized: "Move to Trash") : String(localized: "Delete"),
                        onCancel: { isConfirming = false },
                        onConfirm: {
                            isConfirming = false
                            model.removeChecked()
                        }
                    ) {
                        Image(nsImage: app.icon).resizable().frame(width: 60, height: 60)
                    }
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
            Text(model.isScanning ? "Looking for files…" : "selected of \(Format.bytes(model.totalSize)) found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 18)
    }

    private var confirmationMessage: String {
        let items = model.checkedItems
        let size = Format.bytes(model.checkedSize)
        let count = items.count
        var text = switch (model.moveToTrash, count == 1) {
        case (true, true): String(localized: "1 item · \(size) will go to the Trash.")
        case (true, false): String(localized: "\(count) items · \(size) will go to the Trash.")
        case (false, true): String(localized: "1 item · \(size) will be deleted forever.")
        case (false, false): String(localized: "\(count) items · \(size) will be deleted forever.")
        }
        text += " " + String(localized: "The app will be quit if it’s open.")
        if model.moveToTrash && items.contains(where: \.needsAdmin) {
            text += " " + String(localized: "Protected system items are deleted directly and require your password.")
        }
        return text
    }
}

/// Botão de raio 10 (40 pt nos painéis, 32 pt na linha do topo), com realce ao passar o mouse e ao pressionar.
/// Sem `solidFill`, usa o fundo e a borda padrão dos chips.
struct PillButtonStyle: ButtonStyle {
    let foreground: Color
    var weight: Font.Weight = .semibold
    var solidFill: Color?
    var height: CGFloat = 40
    /// Quadrado do tamanho da altura, para botões só com símbolo.
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, style: self)
    }

    private struct Pill: View {
        let configuration: Configuration
        let style: PillButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var isHighlighted: Bool { isHovered && isEnabled }

        /// Nos chips, o ícone cinza vai para a cor principal no hover; cores de destaque (ex.: laranja) se mantêm.
        private var foreground: Color {
            style.solidFill == nil && isHighlighted && style.foreground == .secondary ? .primary : style.foreground
        }

        var body: some View {
            configuration.label
                .font((style.height < 40 ? Font.callout : Font.body).weight(style.weight))
                .foregroundStyle(foreground)
                .padding(.horizontal, style.iconOnly ? 0 : (style.height < 40 ? 12 : 16))
                .frame(width: style.iconOnly ? style.height : nil, height: style.height)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 10)
                    if let fill = style.solidFill {
                        shape.fill(fill)
                    } else {
                        Color.clear.chipSurface(shape, fill: isHighlighted ? 0.14 : 0.08)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                // Brilho só nos botões de cor sólida: nos chips translúcidos ele apagava o ícone.
                .brightness(style.solidFill != nil && isHighlighted ? 0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
                .animation(.smooth(duration: 0.15), value: configuration.isPressed)
                .animation(.smooth(duration: 0.15), value: isHovered)
        }
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
                        .background(category.color, in: RoundedRectangle(cornerRadius: 8))
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
            .layoutPriority(1)

            Spacer(minLength: 8)

            if isHovered {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
            if item.needsAdmin {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Requires an administrator password")
            }
            Text(Format.bytes(item.size))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .chipSurface(RoundedRectangle(cornerRadius: 14), fill: isHovered ? 0.08 : 0.05)
        .opacity(isOn ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.smooth(duration: 0.15)) { isOn.toggle() } }
        .onHover { isHovered = $0 }
    }
}

/// Confirmação da remoção, no lugar do diálogo padrão do sistema.
struct ConfirmPanel<Icon: View>: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                icon
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.red))
                    .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
                    .offset(x: 6, y: 6)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(foreground: .primary, weight: .medium))
                .keyboardShortcut(.cancelAction)

                Button(action: onConfirm) {
                    Text(confirmTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(foreground: .white, solidFill: .red))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .chipSurface(RoundedRectangle(cornerRadius: 20), fill: 0.05)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Linha do topo das telas internas: voltar à esquerda e as ações da tela à direita.
struct TopBar<Actions: View>: View {
    @EnvironmentObject private var model: AppModel
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Button { model.close() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(PillButtonStyle(foreground: .secondary, height: 32, iconOnly: true))
            .help("Back")
            .disabled(model.isRemoving)
            Spacer()
            actions
        }
        .padding(.horizontal, 22)
    }
}
