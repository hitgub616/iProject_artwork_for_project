import SwiftUI

struct SidebarView: View {
    @Bindable var store: LibraryStore
    @State private var showSettings = false

    private let collectionKinds: [ProjectKind] =
        [.web, .mobile, .desktop, .backend, .dataML, .tool]

    var body: some View {
        List(selection: $store.filter) {
            Section("Library") {
                Label("Projects", systemImage: "square.grid.2x2").tag(LibraryFilter.allProjects)
                Label("Favorites", systemImage: "star").tag(LibraryFilter.favorites)
                Label("Recent", systemImage: "clock").tag(LibraryFilter.recent)
            }

            Section("Collections") {
                ForEach(collectionKinds, id: \.self) { kind in
                    HStack {
                        Label(kind.label, systemImage: kind.symbol)
                        Spacer()
                        Text("\(store.count(for: kind))")
                            .foregroundStyle(.tertiary)
                            .font(.caption.monospacedDigit())
                    }
                    .tag(LibraryFilter.kind(kind))
                }
            }

            Section("Smart Collections") {
                Label("Recently Modified", systemImage: "clock.arrow.circlepath")
                    .tag(LibraryFilter.recentlyModified)
                Label("This Week", systemImage: "calendar").tag(LibraryFilter.thisWeek)
                Label("Large Projects", systemImage: "shippingbox").tag(LibraryFilter.largeProjects)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                addButton("Add Folder", systemImage: "folder.badge.plus",
                          help: "Add a project folder to your library") { store.presentAddFolder() }
                addButton("Add File", systemImage: "doc.badge.plus",
                          help: "Add a single file to your library") { store.presentAddFile() }
                Divider().padding(.vertical, 4)
                addButton("Settings", systemImage: "gearshape",
                          help: "Appearance and preferences") { showSettings = true }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
    }

    private func addButton(_ title: String, systemImage: String, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .help(help)
    }
}
