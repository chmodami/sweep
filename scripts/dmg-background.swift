// Desenha o fundo da janela do instalador (.dmg) em 1x e 2x.
// Uso: swift scripts/dmg-background.swift <pasta-de-saída>
// Gera background.png e background@2x.png; o release.sh junta os dois num .tiff.
//
// As posições precisam bater com o layout do release.sh: janela de 640 × 400 pt,
// ícone do Sweep centrado em (170, 190) e Applications em (470, 190), medidos a partir do topo.
import AppKit

let width: CGFloat = 640
let height: CGFloat = 400
let iconY: CGFloat = 190
let appX: CGFloat = 170
let applicationsX: CGFloat = 470

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Converte uma coordenada medida do topo (como no Finder) para a do AppKit (a partir de baixo).
func fromTop(_ y: CGFloat) -> CGFloat { height - y }

func render(scale: CGFloat, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // Fundo claro: com imagem de fundo o Finder sempre escreve os nomes dos ícones em preto,
    // mesmo no modo escuro, então um fundo escuro deixaria os nomes ilegíveis.
    NSGradient(starting: rgb(250, 249, 255), ending: rgb(232, 229, 248))!.draw(in: bounds, angle: -90)

    // Brilho roxo atrás do ícone do Sweep e um mais fraco atrás de Applications.
    func glow(x: CGFloat, radius: CGFloat, color: NSColor) {
        let center = NSPoint(x: x, y: fromTop(iconY))
        NSGradient(colors: [color, color.withAlphaComponent(0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }
    glow(x: appX, radius: 170, color: rgb(124, 92, 255, 0.28))
    glow(x: applicationsX, radius: 140, color: rgb(90, 110, 255, 0.10))

    // Seta entre os dois ícones.
    let arrowY = fromTop(iconY)
    let start = appX + 92
    let end = applicationsX - 92
    let line = NSBezierPath()
    line.move(to: NSPoint(x: start, y: arrowY))
    line.line(to: NSPoint(x: end, y: arrowY))
    line.lineWidth = 3
    line.lineCapStyle = .round
    line.setLineDash([2, 9], count: 2, phase: 0)
    rgb(60, 52, 110, 0.30).setStroke()
    line.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: end - 12, y: arrowY + 12))
    head.line(to: NSPoint(x: end + 1, y: arrowY))
    head.line(to: NSPoint(x: end - 12, y: arrowY - 12))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    rgb(60, 52, 110, 0.50).setStroke()
    head.stroke()

    // Legenda.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let caption = NSAttributedString(string: "Drag Sweep to Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: rgb(48, 44, 80, 0.55),
        .paragraphStyle: paragraph,
    ])
    caption.draw(in: NSRect(x: 0, y: fromTop(338), width: width, height: 20))

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try render(scale: 1, to: output.appendingPathComponent("background.png"))
try render(scale: 2, to: output.appendingPathComponent("background@2x.png"))
