import SwiftUI

/// View для отображения ошибки в debug mode
/// Показывает детали ошибки с возможностью копирования
struct DebugErrorView: View {
    let error: DebugManager.DebugError
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Заголовок ошибки
                    GroupBox {
                        Text(error.errorDescription)
                            .font(.body)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Ошибка", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }

                    // Контекст
                    GroupBox {
                        Text(error.context)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Контекст", systemImage: "info.circle")
                    }

                    // Время
                    GroupBox {
                        Text(error.timestamp, format: .dateTime)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Время", systemImage: "clock")
                    }

                    // Технические детали (сворачиваемый)
                    DisclosureGroup {
                        Text(error.errorDetails)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } label: {
                        Label("Технические детали", systemImage: "wrench.and.screwdriver")
                    }

                    // Stack trace (сворачиваемый)
                    DisclosureGroup {
                        Text(error.stackTrace)
                            .font(.caption2)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } label: {
                        Label("Stack Trace", systemImage: "list.bullet.rectangle")
                    }
                }
                .padding()
            }
            .navigationTitle("Debug Error")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(
                            copied ? "Скопировано" : "Копировать",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = error.fullText
        copied = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

#Preview {
    DebugErrorView(
        error: DebugManager.DebugError(
            timestamp: Date(),
            errorDescription: "Не удалось подключиться к серверу транскрипции",
            errorDetails: "URLError: The network connection was lost",
            context: "TranscriptionService at TranscriptionService.swift:42",
            stackTrace: "Thread.callStackSymbols..."
        )
    )
}
