import SwiftUI

struct ContentView: View {
    @Bindable var store: LibraryStore
    @State private var selectedID: Project.ID?
    @State private var tick = TickPlayer()
    @State private var soundOn = true
    @State private var soundHover = false
    @State private var sortOrder: [KeyPathComparator<Project>] = []
    @State private var launchTarget: Project?

    private var projects: [Project] {
        let base = store.visibleProjects
        return sortOrder.isEmpty ? base : base.sorted(using: sortOrder)
    }
    private var selectedIndex: Int? { projects.firstIndex { $0.id == selectedID } }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            VStack(spacing: 0) {
                HeaderBar(store: store, projects: projects,
                          selectedIndex: selectedIndex,
                          onPrev: { move(-1) }, onNext: { move(1) },
                          onOpen: openSelected)

                stage

                Divider().overlay(Color.chromeBorder)

                ProjectListView(projects: projects, selectedID: $selectedID,
                                sortOrder: $sortOrder, store: store)
                    .frame(minHeight: 200)

                FooterBar(store: store, count: projects.count)
            }
            .background(Color.stageBottom)
            .ignoresSafeArea(.container, edges: .top)
            .confirmationDialog(
                launchTarget.map { "Start “\($0.name)”" } ?? "",
                isPresented: Binding(get: { launchTarget != nil },
                                     set: { if !$0 { launchTarget = nil } }),
                titleVisibility: .visible,
                presenting: launchTarget
            ) { project in
                ForEach(Launcher.allCases) { app in
                    Button("Start with \(app.displayName)") { app.launch(project) }
                        .disabled(!app.isInstalled)
                }
                Button("Set Cover from Image…") { store.presentSetCover(for: project.id) }
                if store.isCustomCover(project.id) {
                    Button("Reset Cover") { store.resetCover(for: project.id) }
                }
                Button("Open in Finder") { openInFinder(project.url) }
                Button("Cancel", role: .cancel) { }
            }
        }
        .preferredColorScheme(store.appTheme.colorScheme)
        .onChange(of: soundOn) { _, v in tick.enabled = v }
        .onAppear { store.load() }
        .onChange(of: store.projects.count) { _, _ in ensureSelection() }
        .onChange(of: store.filter) { _, _ in resetSelection() }
        .onChange(of: store.searchText) { _, _ in resetSelection() }
    }

    // MARK: - Stage

    private func metrics(for height: CGFloat) -> CoverFlowMetrics {
        var m = CoverFlowMetrics()
        m.cardSize = min(max(height * 0.58, 160), 360)
        return m
    }

    private var stage: some View {
        GeometryReader { geo in
            let metrics = metrics(for: geo.size.height)
            ZStack {
                LinearGradient(colors: [Color.stageTop, Color.stageBottom],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.stageGlow, .clear],
                               center: .center, startRadius: 0, endRadius: geo.size.width * 0.6)

                if projects.isEmpty {
                    emptyState
                } else {
                    CoverFlowView(projects: projects, selectedID: $selectedID,
                                  metrics: metrics, tick: tick, store: store,
                                  onActivateCenter: { launchTarget = $0 })
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                soundToggle.padding(18)
            }
        }
        .frame(minHeight: 320)
    }

    /// A discreet, translucent mute toggle that lives in the cover area's
    /// bottom-right corner and brightens on hover.
    private var soundToggle: some View {
        Button { soundOn.toggle() } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(soundHover ? 0.95 : 0.5))
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .opacity(soundHover ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .onHover { soundHover = $0 }
        .animation(.easeOut(duration: 0.18), value: soundHover)
        .help(soundOn ? "Mute click sound" : "Unmute click sound")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.isScanning ? "rays" : "folder.badge.questionmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: store.isScanning)
            Text(store.isScanning ? "Scanning projects…" : "No projects found")
                .foregroundStyle(.secondary)
            Text(store.rootURL.path).font(.caption).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Selection helpers

    private func ensureSelection() {
        if selectedID == nil || !(projects.contains { $0.id == selectedID }) {
            selectedID = projects.first?.id
        }
    }

    private func resetSelection() { selectedID = projects.first?.id }

    private func move(_ delta: Int) {
        guard !projects.isEmpty else { return }
        let idx = selectedIndex ?? 0
        let next = max(0, min(projects.count - 1, idx + delta))
        selectedID = projects[next].id
    }

    private func openSelected() {
        guard let idx = selectedIndex else { return }
        openInFinder(projects[idx].url)
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Bindable var store: LibraryStore
    let projects: [Project]
    let selectedIndex: Int?
    let onPrev: () -> Void
    let onNext: () -> Void
    let onOpen: () -> Void

    private var current: Project? {
        guard let i = selectedIndex, projects.indices.contains(i) else { return nil }
        return projects[i]
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                transport("backward.fill", action: onPrev)
                transport("forward.fill", action: onNext)
                Spacer(minLength: 0)
            }
            .frame(width: 210)

            nowPlaying
                .frame(maxWidth: 580)
                .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                searchField
            }
            .frame(width: 210)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.chromeBorder).frame(height: 1) }
    }

    private func transport(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.borderless)
    }

    private var nowPlaying: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(current?.name ?? "Projex Finder")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                // Line 2 — project Type, color-linked to the kind.
                HStack(spacing: 5) {
                    Image(systemName: current?.kind.symbol ?? "folder")
                        .font(.system(size: 9, weight: .semibold))
                    Text(current?.kind.label ?? "—")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(current?.kind.color ?? Color.secondary)

                // Line 3 — description (README/manifest, or composed from structure).
                Text(current?.summary ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    Text(indexLabel).font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(height: 3)
                    Text("\(projects.count)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                }
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity)

            // Open-in-Finder, right-centered inside the play box.
            Button(action: onOpen) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Finder")
            .disabled(current == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.inset)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.chromeBorder, lineWidth: 1))
        )
    }

    private var indexLabel: String {
        guard let i = selectedIndex else { return "—" }
        return "\(i + 1)"
    }

    private var progress: Double {
        guard let i = selectedIndex, projects.count > 1 else { return 0 }
        return Double(i + 1) / Double(projects.count)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.plain)
                .frame(width: 150)
            if !store.searchText.isEmpty {
                Button { store.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.inset)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.chromeBorder, lineWidth: 1))
        )
    }
}

// MARK: - Footer

private struct FooterBar: View {
    let store: LibraryStore
    let count: Int

    var body: some View {
        HStack {
            Button { store.load() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rescan workspace")

            Spacer()
            Text(summary).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()

            if store.isScanning { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Color.chromeBorder).frame(height: 1) }
    }

    private var summary: String {
        let size = ByteCountFormatter.string(fromByteCount: store.totalSize, countStyle: .file)
        let avail = store.availableSpaceLabel
        return "\(count) projects · \(size)" + (avail.isEmpty ? "" : " · \(avail)")
    }
}
