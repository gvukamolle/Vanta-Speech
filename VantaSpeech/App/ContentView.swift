import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .library

    enum Tab {
        case library
        case record
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "list.bullet")
                }
                .tag(Tab.library)

            RecordingView()
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }
                .tag(Tab.record)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    ContentView()
}
