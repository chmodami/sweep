import SwiftUI

struct ItemCategory {
    let label: String
    let symbol: String
    let color: Color
}

extension FoundItem {
    /// Nome amigável, ícone e cor do tipo de arquivo, a partir da pasta onde ele está.
    var category: ItemCategory {
        if kind == .appBundle { return ItemCategory(label: String(localized: "App"), symbol: "app.fill", color: .blue) }
        let parent = url.deletingLastPathComponent().path
        let crash = ItemCategory(label: String(localized: "Crash reports"), symbol: "exclamationmark.triangle.fill", color: .red)
        let categories: [(suffix: String, category: ItemCategory)] = [
            ("/Application Support", ItemCategory(label: String(localized: "App data"), symbol: "externaldrive.fill", color: .blue)),
            ("/Application Scripts", ItemCategory(label: String(localized: "Scripts"), symbol: "scroll.fill", color: .gray)),
            ("/Caches", ItemCategory(label: String(localized: "Cache"), symbol: "shippingbox.fill", color: .orange)),
            ("/Caches/SentryCrash", crash),
            ("/CrashReporter", crash),
            ("/DiagnosticReports", crash),
            ("/Containers", ItemCategory(label: String(localized: "Container"), symbol: "cube.fill", color: .indigo)),
            ("/Group Containers", ItemCategory(label: String(localized: "Shared container"), symbol: "square.stack.3d.up.fill", color: .indigo)),
            ("/Cookies", ItemCategory(label: String(localized: "Cookies"), symbol: "circle.hexagongrid.fill", color: .brown)),
            ("/HTTPStorages", ItemCategory(label: String(localized: "Network data"), symbol: "network", color: .teal)),
            ("/WebKit", ItemCategory(label: String(localized: "Browsing data"), symbol: "safari.fill", color: .cyan)),
            ("/LaunchAgents", ItemCategory(label: String(localized: "Background service"), symbol: "gearshape.2.fill", color: .purple)),
            ("/LaunchDaemons", ItemCategory(label: String(localized: "System service"), symbol: "gearshape.2.fill", color: .purple)),
            ("/PrivilegedHelperTools", ItemCategory(label: String(localized: "Helper tool"), symbol: "wrench.and.screwdriver.fill", color: .purple)),
            ("/Logs", ItemCategory(label: String(localized: "Logs"), symbol: "doc.text.fill", color: .gray)),
            ("/Preferences", ItemCategory(label: String(localized: "Preferences"), symbol: "slider.horizontal.3", color: .pink)),
            ("/Preferences/ByHost", ItemCategory(label: String(localized: "Preferences"), symbol: "slider.horizontal.3", color: .pink)),
            ("/Saved Application State", ItemCategory(label: String(localized: "Window state"), symbol: "macwindow", color: .mint)),
            ("/receipts", ItemCategory(label: String(localized: "Install receipt"), symbol: "doc.plaintext.fill", color: .green)),
            ("/Applications", ItemCategory(label: String(localized: "Shortcut"), symbol: "arrow.up.right.square.fill", color: .yellow)),
        ]
        return categories.last { parent.hasSuffix($0.suffix) }?.category
            ?? ItemCategory(label: String(localized: "File"), symbol: "doc.fill", color: .gray)
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

extension Color {
    /// Cor com uma variação para o modo claro e outra para o escuro.
    init(light: UInt32, dark: UInt32) {
        func color(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

/// Cores dos gráficos, validadas com o validate_palette.js da skill de dataviz (claro e escuro):
/// azul e âmbar passam em separação para daltonismo; o âmbar tem contraste baixo no claro,
/// por isso todo gráfico mostra os valores escritos na legenda.
enum ChartPalette {
    static let apps = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let other = Color(light: 0xC77700, dark: 0xC27A16)
    static let free = Color.primary.opacity(0.08)
}
