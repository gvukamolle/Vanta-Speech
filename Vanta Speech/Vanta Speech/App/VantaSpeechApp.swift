import SwiftData
import SwiftUI
import UIKit

@main
struct VantaSpeechApp: App {
    @StateObject private var coordinator = RecordingCoordinator.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Очищаем stale recording action и pending preset при холодном старте
        // Это предотвращает автостарт записи из-за "зависших" ключей
        let defaults = UserDefaults(suiteName: AppGroupConstants.suiteName)
        defaults?.removeObject(forKey: AppGroupConstants.recordingActionKey)
        defaults?.synchronize()

        // Подписываемся на уведомление о завершении приложения
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Останавливаем запись и завершаем Live Activity при закрытии приложения
            Task { @MainActor in
                _ = await RecordingCoordinator.shared.stopRecording()
                await LiveActivityManager.shared.endActivityImmediately()
            }
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
        ])

        // Use App Group container for sharing data with Widget Extension
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(AppGroupConstants.suiteName)
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // Основное окно приложения
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    AdaptiveRootView()
                        .environmentObject(coordinator)
                        .environmentObject(coordinator.audioRecorder)
                        .onAppear {
                            coordinator.setModelContext(sharedModelContainer.mainContext)
                        }
                        .task {
                            // Очищаем старые Live Activity при запуске, если нет активной записи
                            if !coordinator.audioRecorder.isRecording {
                                await LiveActivityManager.shared.endActivityImmediately()
                            }
                        }
                } else {
                    LoginView()
                }
            }
            .tint(.pinkVibrant)
            .vantaThemed()
        }
        .modelContainer(sharedModelContainer)

        // Дополнительное окно для просмотра записи (Stage Manager на iPad)
        WindowGroup("Запись", id: "recording", for: UUID.self) { $recordingId in
            if let id = recordingId {
                RecordingDetailWindow(recordingId: id)
                    .environmentObject(coordinator)
                    .environmentObject(coordinator.audioRecorder)
                    .vantaThemed()
            }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 600, height: 800)
    }
}
