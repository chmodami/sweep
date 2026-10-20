import SwiftUI

struct ItemCategory {
    let label: String
    let symbol: String
    let color: Color
}

extension FoundItem {
    /// Nome amigável, ícone e cor do tipo de arquivo, a partir da pasta onde ele está.
    var category: ItemCategory {
        if kind == .appBundle { return ItemCategory(label: "Aplicativo", symbol: "app.fill", color: .blue) }
        let parent = url.deletingLastPathComponent().path
        let crash = ItemCategory(label: "Relatórios de falha", symbol: "exclamationmark.triangle.fill", color: .red)
        let categories: [(suffix: String, category: ItemCategory)] = [
            ("/Application Support", ItemCategory(label: "Dados do app", symbol: "externaldrive.fill", color: .blue)),
            ("/Application Scripts", ItemCategory(label: "Scripts", symbol: "scroll.fill", color: .gray)),
            ("/Caches", ItemCategory(label: "Cache", symbol: "shippingbox.fill", color: .orange)),
            ("/Caches/SentryCrash", crash),
            ("/CrashReporter", crash),
            ("/DiagnosticReports", crash),
            ("/Containers", ItemCategory(label: "Contêiner", symbol: "cube.fill", color: .indigo)),
            ("/Group Containers", ItemCategory(label: "Contêiner compartilhado", symbol: "square.stack.3d.up.fill", color: .indigo)),
            ("/Cookies", ItemCategory(label: "Cookies", symbol: "circle.hexagongrid.fill", color: .brown)),
            ("/HTTPStorages", ItemCategory(label: "Dados de rede", symbol: "network", color: .teal)),
            ("/WebKit", ItemCategory(label: "Dados de navegação", symbol: "safari.fill", color: .cyan)),
            ("/LaunchAgents", ItemCategory(label: "Serviço em segundo plano", symbol: "gearshape.2.fill", color: .purple)),
            ("/LaunchDaemons", ItemCategory(label: "Serviço do sistema", symbol: "gearshape.2.fill", color: .purple)),
            ("/PrivilegedHelperTools", ItemCategory(label: "Ferramenta auxiliar", symbol: "wrench.and.screwdriver.fill", color: .purple)),
            ("/Logs", ItemCategory(label: "Logs", symbol: "doc.text.fill", color: .gray)),
            ("/Preferences", ItemCategory(label: "Preferências", symbol: "slider.horizontal.3", color: .pink)),
            ("/Preferences/ByHost", ItemCategory(label: "Preferências", symbol: "slider.horizontal.3", color: .pink)),
            ("/Saved Application State", ItemCategory(label: "Estado das janelas", symbol: "macwindow", color: .mint)),
            ("/receipts", ItemCategory(label: "Recibo de instalação", symbol: "doc.plaintext.fill", color: .green)),
            ("/Applications", ItemCategory(label: "Atalho", symbol: "arrow.up.right.square.fill", color: .yellow)),
        ]
        return categories.last { parent.hasSuffix($0.suffix) }?.category
            ?? ItemCategory(label: "Arquivo", symbol: "doc.fill", color: .gray)
    }
}

/// Cor de destaque tirada do ícone de cada app, usada no brilho de fundo e nas barras.
@MainActor
enum Accent {
    static let standard = Color(red: 0.42, green: 0.40, blue: 1.0)
    private static var cache: [URL: Color] = [:]

    static func color(for app: InstalledApp?) -> Color {
        guard let app else { return standard }
        if let color = cache[app.url] { return color }
        let color = dominantColor(of: app.icon).map { Color(nsColor: $0) } ?? standard
        cache[app.url] = color
        return color
    }

    /// Média dos pixels pesada pela saturação, para pegar a cor "da marca" e não o fundo branco.
    private static func dominantColor(of image: NSImage) -> NSColor? {
        let side = 24
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for x in 0..<side {
            for y in 0..<side {
                guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), pixel.alphaComponent > 0.5 else { continue }
                let weight = 0.02 + pixel.saturationComponent * pixel.brightnessComponent
                red += pixel.redComponent * weight
                green += pixel.greenComponent * weight
                blue += pixel.blueComponent * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }
        let average = NSColor(deviceRed: red / total, green: green / total, blue: blue / total, alpha: 1)
        // Ícones quase cinza não têm uma cor marcante; fica a cor padrão.
        guard average.saturationComponent > 0.12 else { return nil }
        return NSColor(
            deviceHue: average.hueComponent,
            saturation: max(average.saturationComponent, 0.55),
            brightness: max(average.brightnessComponent, 0.85),
            alpha: 1
        )
    }
}

/// Manchas de cor desfocadas atrás do conteúdo, que dão vida ao vidro da janela.
struct Glow: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.55))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: -120, y: -200)
            Circle()
                .fill(color.opacity(0.28))
                .frame(width: 300, height: 300)
                .blur(radius: 130)
                .offset(x: 160, y: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.6), value: color)
    }
}

struct CheckCircle: View {
    let isOn: Bool
    let color: Color

    var body: some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(isOn ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
            .contentTransition(.symbolEffect(.replace))
    }
}
