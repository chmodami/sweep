import SwiftUI

/// Ícone de uma categoria: símbolo branco num quadrado colorido.
struct SymbolTile: View {
    let symbol: String
    let color: Color
    var side: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.43, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(color, in: RoundedRectangle(cornerRadius: side * 0.27))
    }
}

struct JunkView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isConfirming = false

    /// Antes da varredura mostra o painel de armazenamento; depois, o que foi encontrado.
    private var hasResults: Bool { model.hasScannedJunk && !model.isScanningJunk }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.close() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .chipSurface(RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help("Back")
                .disabled(model.isRemoving)
                Spacer()
            }
            .padding(.horizontal, 22)

            hero

            ScrollView {
                Group {
                    if hasResults {
                        results
                    } else {
                        overview
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 4)
                .geometryGroup()
                .transition(.opacity)
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .animation(.smooth(duration: 0.25), value: hasResults)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer.opacity(isConfirming ? 0 : 1)
            }
        }
        .overlay {
            if isConfirming {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.55)
                        .onTapGesture { isConfirming = false }
                        .transition(.opacity)
                    ConfirmPanel(
                        title: String(localized: "Clean up \(Format.bytes(model.checkedJunkSize))?"),
                        message: confirmationMessage,
                        confirmTitle: String(localized: "Clean up"),
                        onCancel: { isConfirming = false },
                        onConfirm: {
                            isConfirming = false
                            model.cleanJunk()
                        }
                    ) {
                        SymbolTile(symbol: "sparkles", color: .orange, side: 60)
                    }
                    .padding(14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .padding(.top, -30) // cobre também a faixa dos botões da janela
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.18), value: isConfirming)
    }

    private var hero: some View {
        VStack(spacing: 4) {
            SymbolTile(symbol: "sparkles", color: .orange, side: hasResults ? 56 : 72)
                .shadow(color: Color.orange.opacity(0.45), radius: 20, y: 8)
                .padding(.bottom, 8)
            Text("Accumulated junk")
                .font(.title2.weight(.semibold))
            if hasResults {
                Text(Format.bytes(model.checkedJunkSize))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: model.checkedJunkSize)
                    .padding(.top, 4)
                Text("selected of \(Format.bytes(model.junkTotal)) found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Find caches, logs and leftovers taking up space. Nothing is removed without your OK.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 30)
            }
        }
        .padding(.bottom, 18)
        .animation(.smooth(duration: 0.25), value: hasResults)
    }

    private var overview: some View {
        VStack(spacing: 12) {
            if let disk = model.disk {
                StorageCard(disk: disk, appsTotal: model.appsTotal)
            }
            ScanScopeCard()
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 18) {
            let safe = model.junkGroups.filter { !$0.needsReview }
            let review = model.junkGroups.filter(\.needsReview)
            if model.junkGroups.isEmpty {
                Text("Nothing to clean")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                JunkBreakdownCard(groups: model.junkGroups)
            }
            if !safe.isEmpty {
                JunkSection(title: "Safe to clean", groups: safe)
            }
            if !review.isEmpty {
                JunkSection(title: "Review first · goes to the Trash", groups: review)
            }
        }
    }

    private var confirmationMessage: String {
        let groups = model.checkedJunk
        var parts: [String] = []
        if groups.contains(where: { $0.cleanup != .trash }) {
            parts.append(String(localized: "Caches, logs and the Trash are deleted permanently."))
        }
        if groups.contains(where: { $0.cleanup == .trash }) {
            parts.append(String(localized: "Leftovers and installers go to the Trash."))
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private var footer: some View {
        // Mesmo padrão da tela de detalhes: barra de 52 pt com raio 16 e botões de 40 pt com raio 10.
        HStack(spacing: 6) {
            if hasResults {
                Button { model.scanJunk() } label: {
                    Label("Scan again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PillButtonStyle(foreground: .secondary, weight: .medium))
                .disabled(model.isRemoving)

                Spacer(minLength: 0)

                Button { isConfirming = true } label: {
                    HStack(spacing: 7) {
                        if model.isRemoving {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(model.isRemoving ? "Cleaning…" : "Clean up")
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(PillButtonStyle(foreground: .white, solidFill: .red))
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.checkedJunk.isEmpty || model.isRemoving)
            } else {
                Button { model.scanJunk() } label: {
                    HStack(spacing: 8) {
                        if model.isScanningJunk {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        Text(model.isScanningJunk ? "Scanning…" : "Scan for junk")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(foreground: .white, solidFill: .orange))
                .keyboardShortcut(.defaultAction)
                .disabled(model.isScanningJunk)
            }
        }
        .padding(6)
        .frame(height: 52)
        .chipSurface(RoundedRectangle(cornerRadius: 16), fill: 0.05)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 20)
        .overlay(alignment: .top) {
            // A varredura fica parada enquanto o pedido de permissão do macOS espera resposta.
            if model.isScanningJunk {
                Text("macOS may ask for permission to read data from other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .offset(y: -12)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Gráficos

/// Título pequeno em caixa alta usado no topo dos cartões.
struct CardTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Uso do disco: número em destaque, barra empilhada (apps · outros · livre) e legenda com valores.
struct StorageCard: View {
    let disk: DiskUsage
    let appsTotal: Int64

    private var other: Int64 { max(disk.used - appsTotal, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Storage")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.bytes(disk.free))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("free of \(Format.bytes(disk.total))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            StackedBar(total: disk.total, segments: [
                .init(value: appsTotal, color: ChartPalette.apps),
                .init(value: other, color: ChartPalette.other),
            ])
            HStack(spacing: 16) {
                LegendItem(color: ChartPalette.apps, label: "Apps", value: appsTotal)
                LegendItem(color: ChartPalette.other, label: "Other", value: other)
                LegendItem(color: ChartPalette.free, label: "Free", value: disk.free)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chipSurface(RoundedRectangle(cornerRadius: 14), fill: 0.05)
    }
}

/// Barra horizontal empilhada; o que sobra até o total fica como trilho (espaço livre).
struct StackedBar: View {
    struct Segment {
        let value: Int64
        let color: Color
    }

    let total: Int64
    let segments: [Segment]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let width = proxy.size.width - gap * CGFloat(segments.count)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(segment.color)
                        .frame(width: max(width * CGFloat(segment.value) / CGFloat(max(total, 1)), 4))
                }
                RoundedRectangle(cornerRadius: 4).fill(ChartPalette.free)
            }
        }
        .frame(height: 12)
    }
}

struct LegendItem: View {
    let color: Color
    let label: LocalizedStringKey
    let value: Int64

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text(Format.bytes(value)).monospacedDigit()
        }
        .font(.caption)
    }
}

/// O que a varredura procura, antes de rodar.
struct ScanScopeCard: View {
    private let items: [(symbol: String, color: Color, label: LocalizedStringKey)] = [
        ("shippingbox.fill", .orange, "App caches"),
        ("doc.text.fill", .gray, "Logs and crash reports"),
        ("hammer.fill", .blue, "Developer caches"),
        ("trash.fill", .red, "Trash"),
        ("questionmark.folder.fill", .purple, "Leftovers from deleted apps"),
        ("arrow.down.circle.fill", .teal, "Installers in Downloads"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "What the scan looks for")
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        SymbolTile(symbol: item.symbol, color: item.color, side: 22)
                        Text(item.label)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chipSurface(RoundedRectangle(cornerRadius: 14), fill: 0.05)
    }
}

/// Onde está o lixo encontrado: uma barra por categoria, com o valor escrito ao lado.
struct JunkBreakdownCard: View {
    let groups: [JunkGroup]

    private var rows: [(label: String, size: Int64)] {
        let leftovers = groups.filter { $0.id.hasPrefix("orphan:") }.reduce(Int64(0)) { $0 + $1.size }
        var rows = groups.filter { !$0.id.hasPrefix("orphan:") && $0.isMeasured }.map { ($0.title, $0.size) }
        if leftovers > 0 { rows.append((String(localized: "Leftovers from deleted apps"), leftovers)) }
        return rows.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        let rows = rows
        let largest = max(rows.first?.size ?? 1, 1)
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: "Where the junk is")
            VStack(spacing: 9) {
                ForEach(rows, id: \.label) { row in
                    HStack(spacing: 10) {
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 140, alignment: .leading)
                        SizeBar(fraction: Double(row.size) / Double(largest), color: ChartPalette.other)
                        Text(Format.bytes(row.size))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .chipSurface(RoundedRectangle(cornerRadius: 14), fill: 0.05)
    }
}

struct JunkSection: View {
    @EnvironmentObject private var model: AppModel
    let title: LocalizedStringKey
    let groups: [JunkGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
            VStack(spacing: 6) {
                ForEach(groups) { group in
                    JunkRow(group: group, isOn: Binding(
                        get: { model.junkChecked.contains(group.id) },
                        set: { isOn in
                            if isOn { model.junkChecked.insert(group.id) } else { model.junkChecked.remove(group.id) }
                        }
                    ))
                }
            }
        }
    }
}

struct JunkRow: View {
    let group: JunkGroup
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(isOn: isOn, color: .orange)
            SymbolTile(symbol: group.symbol, color: group.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(group.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Sem prioridade, o Spacer dividia a largura com o texto e cortava títulos curtos.
            .layoutPriority(1)

            Spacer(minLength: 8)

            if isHovered, group.cleanup != .emptyTrash {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(Array(group.urls.prefix(20)))
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
            Text(group.isMeasured ? Format.bytes(group.size) : "—")
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
        .help(group.urls.prefix(8).map { Format.path($0) }.joined(separator: "\n"))
    }
}

/// Cartão da tela inicial que leva à limpeza, já mostrando quanto foi encontrado.
struct JunkCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var isHovered = false

    var body: some View {
        Button { model.openJunk() } label: {
            HStack(spacing: 12) {
                SymbolTile(symbol: "sparkles", color: .orange, side: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Accumulated junk")
                        .font(.body.weight(.medium))
                    Group {
                        if model.hasScannedJunk {
                            Text("Caches, logs and leftovers from deleted apps")
                        } else if let disk = model.disk {
                            Text("\(Format.bytes(disk.free)) free · scan to find junk")
                        } else {
                            Text("Scan to find junk")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                if model.isScanningJunk {
                    ProgressView().controlSize(.small)
                } else if model.hasScannedJunk {
                    Text(Format.bytes(model.junkTotal))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .chipSurface(RoundedRectangle(cornerRadius: 14), fill: isHovered ? 0.08 : 0.05)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
