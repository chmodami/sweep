import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var model: AppModel
    let result: RemovalResult
    @State private var appeared = false

    private var succeeded: Bool { result.failures.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            Spacer()

            ZStack {
                Circle()
                    .fill((succeeded ? Color.green : Color.orange).gradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: (succeeded ? Color.green : Color.orange).opacity(0.5), radius: 24, y: 8)
                Image(systemName: succeeded ? "checkmark" : "exclamationmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .padding(.bottom, 18)

            Text(result.removedApp ? "\(result.app.name) removed" : "Files removed")
                .font(.title2.weight(.semibold))
            Text(Format.bytes(result.freed))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.top, 8)
            Text(result.toTrash ? "moved to the Trash" : "freed on disk")
                .foregroundStyle(.secondary)

            if !succeeded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn’t remove:").font(.callout.weight(.medium))
                        ForEach(result.failures, id: \.self) { failure in
                            Text(failure).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .frame(maxHeight: 150)
                .chipSurface(RoundedRectangle(cornerRadius: 14), fill: 0.05)
                .padding(.top, 18)
            }

            Spacer()

            Button { model.close() } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(foreground: .white, solidFill: .accentColor))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { appeared = true }
        }
    }
}
