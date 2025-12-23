import SwiftUI
import SwiftData

@main
struct VantaSpeechApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") {
                    NotificationCenter.default.post(name: .startNewRecording, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandGroup(after: .appInfo) {
                Button("Preferences...") {
                    NotificationCenter.default.post(name: .openPreferences, object: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .modelContainer(sharedModelContainer)
        }

        MenuBarExtra("Vanta Speech", systemImage: "waveform") {
            MenuBarView()
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}

extension Notification.Name {
    static let startNewRecording = Notification.Name("startNewRecording")
    static let openPreferences = Notification.Name("openPreferences")
}
