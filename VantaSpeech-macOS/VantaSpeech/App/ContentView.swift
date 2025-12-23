import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: Tab = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    enum Tab: String, CaseIterable {
        case library = "Library"
        case record = "Record"

        var icon: String {
            switch self {
            case .library: return "folder"
            case .record: return "mic.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .library:
                LibraryView()
            case .record:
                RecordingView()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                }
            }
        }
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recording.self, inMemory: true)
}
