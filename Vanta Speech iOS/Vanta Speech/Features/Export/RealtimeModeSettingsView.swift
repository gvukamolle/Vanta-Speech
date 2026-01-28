import SwiftUI

struct RealtimeModeSettingsView: View {
    @AppStorage("realtime_pauseThreshold") private var pauseThreshold: Double = 3.0

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Пауза для завершения фразы")
                        Spacer()
                        Text(String(format: "%.1f сек", pauseThreshold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $pauseThreshold, in: 1.0...5.0, step: 0.5)
                        .tint(.pinkVibrant)
                }
            } header: {
                Text("Определение пауз")
            } footer: {
                Text("Когда вы молчите дольше указанного времени, текущий фрагмент отправляется на транскрипцию. Меньшее значение = быстрее появляется текст, но может разбивать фразы.")
            }

            Section {
                Button("Сбросить по умолчанию") {
                    resetToDefaults()
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Real-time настройки")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resetToDefaults() {
        pauseThreshold = 3.0
    }
}

#Preview {
    NavigationStack {
        RealtimeModeSettingsView()
    }
}
