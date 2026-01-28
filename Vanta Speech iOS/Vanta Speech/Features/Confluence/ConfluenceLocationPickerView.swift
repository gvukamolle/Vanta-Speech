import SwiftUI

/// Sheet для выбора Space и родительской страницы
struct ConfluenceLocationPickerView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = ConfluenceManager.shared

    /// Callback при выборе расположения
    let onSelect: (String, String?, String?) -> Void

    // Navigation state
    @State private var selectedSpace: ConfluenceSpace?
    @State private var navigationPath: [ConfluencePage] = []
    @State private var currentPages: [ConfluencePage] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if selectedSpace == nil {
                    spacesListView
                } else {
                    pagesListView
                }
            }
            .navigationTitle(selectedSpace?.name ?? "Выбор пространства")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ConfluencePage.self) { page in
                ChildPagesListView(
                    parentPage: page,
                    spaceKey: selectedSpace?.key ?? "",
                    onSelect: { pageId, pageTitle in
                        onSelect(selectedSpace!.key, pageId, pageTitle)
                        dismiss()
                    }
                )
            }
        }
    }

    // MARK: - Spaces List

    private var spacesListView: some View {
        List {
            if manager.spaces.isEmpty && manager.isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Загрузка пространств...")
                        .foregroundStyle(.secondary)
                }
            } else if manager.spaces.isEmpty {
                ContentUnavailableView(
                    "Нет пространств",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Не удалось загрузить пространства Confluence")
                )
            } else {
                ForEach(manager.spaces) { space in
                    Button {
                        selectSpace(space)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(space.name)
                                Text(space.key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            if manager.spaces.isEmpty {
                await manager.loadSpaces()
            }
        }
    }

    // MARK: - Pages List (root level)

    private var pagesListView: some View {
        List {
            // Option to select space root
            Section {
                Button {
                    onSelect(selectedSpace!.key, nil, nil)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "house.fill")
                            .foregroundStyle(.orange)
                        Text("Корень пространства")
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Саммари будут создаваться в корне пространства")
            }

            // Child pages
            if !currentPages.isEmpty {
                Section("Страницы") {
                    ForEach(currentPages) { page in
                        pageRow(page: page)
                    }
                }
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Загрузка страниц...")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(selectedSpace?.name ?? "")
                        .font(.headline)
                    Text(selectedSpace?.key ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    selectedSpace = nil
                    currentPages = []
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Пространства")
                    }
                }
            }
        }
    }

    // MARK: - Page Row

    private func pageRow(page: ConfluencePage) -> some View {
        HStack {
            Button {
                // Select this page as parent
                onSelect(selectedSpace!.key, page.id, page.title)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.secondary)
                    Text(page.title)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Navigate to children
            Button {
                navigationPath.append(page)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func selectSpace(_ space: ConfluenceSpace) {
        selectedSpace = space
        loadRootPages()
    }

    private func loadRootPages() {
        guard let space = selectedSpace else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                currentPages = try await manager.getRootPages(spaceKey: space.key)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Child Pages List View

private struct ChildPagesListView: View {
    let parentPage: ConfluencePage
    let spaceKey: String
    let onSelect: (String, String) -> Void

    @StateObject private var manager = ConfluenceManager.shared
    @State private var pages: [ConfluencePage] = []
    @State private var isLoading = true

    var body: some View {
        List {
            // Select current page option
            Section {
                Button {
                    onSelect(parentPage.id, parentPage.title)
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Выбрать эту папку")
                    }
                }
                .buttonStyle(.plain)
            }

            // Child pages
            if !pages.isEmpty {
                Section("Дочерние страницы") {
                    ForEach(pages) { page in
                        NavigationLink(value: page) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.secondary)
                                Text(page.title)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } else if !isLoading {
                Section {
                    Text("Нет дочерних страниц")
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Загрузка...")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(parentPage.title)
        .task {
            await loadChildren()
        }
    }

    private func loadChildren() async {
        do {
            pages = try await manager.getChildPages(pageId: parentPage.id)
        } catch {
            // Ignore errors, just show empty
        }
        isLoading = false
    }
}

#Preview {
    ConfluenceLocationPickerView { spaceKey, pageId, pageTitle in
        print("Selected: \(spaceKey), \(pageId ?? "root"), \(pageTitle ?? "root")")
    }
}
