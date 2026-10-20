import SwiftUI

@main
struct SweepApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Sweep", id: "main") {
            RootView()
                .environmentObject(delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// Apps arrastados para o ícone do Sweep ou abertos com `open -a Sweep App.app`.
    /// Tratar aqui evita que o SwiftUI abra uma janela nova para cada arquivo.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, !model.isRemoving else { return }
        model.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    private var glowColor: Color {
        if let result = model.result { return result.failures.isEmpty ? .green : .orange }
        return Accent.color(for: model.selected ?? model.highlightedApp)
    }

    var body: some View {
        ZStack {
            Glow(color: glowColor)
            Group {
                if let result = model.result {
                    ResultView(result: result)
                } else if let app = model.selected {
                    DetailView(app: app)
                } else {
                    HomeView()
                }
            }
            .padding(.top, 30) // espaço para os botões da janela
            .geometryGroup()
            .transition(.opacity)
        }
        // Altura fixa: redimensionar a janela entre telas causava saltos na transição.
        .frame(width: 460, height: 600)
        .containerBackground(.thickMaterial, for: .window)
        .animation(.smooth(duration: 0.28), value: model.selected)
        .animation(.smooth(duration: 0.28), value: model.result == nil)
        .alert("Sweep", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        // Na abertura a frio o SwiftUI entrega o arquivo aqui, e não ao AppDelegate.
        .onOpenURL { url in if !model.isRemoving { model.open(url) } }
        .onAppear { model.reloadApps() }
    }
}
