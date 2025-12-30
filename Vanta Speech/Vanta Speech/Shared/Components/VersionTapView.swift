import SwiftUI

/// Компонент отображения версии приложения с детекцией 5 нажатий
/// для активации режима отладки
struct VersionTapView: View {
    @StateObject private var debugManager = DebugManager.shared
    @State private var tapCount = 0
    @State private var lastTapTime: Date?
    @State private var showDebugActivated = false
    @State private var showDebugDeactivated = false

    private let requiredTaps = 5
    private let tapTimeout: TimeInterval = 2.0

    var body: some View {
        HStack {
            Text("Версия")
            Spacer()
            Text(appVersion)
                .foregroundStyle(debugManager.isDebugModeEnabled ? .orange : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: tapCount)
        .alert("Режим отладки активирован", isPresented: $showDebugActivated) {
            Button("OK") {}
        } message: {
            Text("Теперь все ошибки будут показываться на экране с возможностью копирования.\n\nДля отключения нажмите на версию 5 раз снова.")
        }
        .alert("Режим отладки отключён", isPresented: $showDebugDeactivated) {
            Button("OK") {}
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        if debugManager.isDebugModeEnabled {
            return "\(version) (\(build)) DEBUG"
        } else {
            return version
        }
    }

    private func handleTap() {
        let now = Date()

        // Сброс счётчика если прошло слишком много времени
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) > tapTimeout {
            tapCount = 0
        }

        lastTapTime = now
        tapCount += 1

        if tapCount >= requiredTaps {
            if debugManager.isDebugModeEnabled {
                debugManager.disableDebugMode()
                showDebugDeactivated = true
            } else {
                debugManager.enableDebugMode()
                showDebugActivated = true
            }
            tapCount = 0
        }
    }
}

#Preview {
    Form {
        Section("О приложении") {
            VersionTapView()
        }
    }
}
