import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

enum LibraryFilter: Hashable {
    case allProjects
    case favorites
    case recent
    case kind(ProjectKind)
    case recentlyModified
    case thisWeek
    case largeProjects
}

@MainActor
@Observable
final class LibraryStore {
    var projects: [Project] = []
    var rootURL: URL
    var isScanning = false
    var searchText = ""
    var filter: LibraryFilter = .allProjects

    /// Selected appearance; persisted and applied at the app root.
    var appTheme: AppTheme {
        didSet { UserDefaults.standard.set(appTheme.rawValue, forKey: "appTheme") }
    }

    private var favorites: Set<String>
    private var addedURLs: [URL]
    private var customCovers: [String: String]   // project path → cached image path

    init() {
        // Default to the conventional ~/Developer folder on first launch; if it
        // doesn't exist the empty state invites the user to choose any workspace.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultURL = home.appendingPathComponent("Developer", isDirectory: true)
        let saved = UserDefaults.standard.string(forKey: "rootPath")
        rootURL = saved.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultURL
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        addedURLs = (UserDefaults.standard.stringArray(forKey: "addedPaths") ?? [])
            .map { URL(fileURLWithPath: $0) }
        customCovers = (UserDefaults.standard.dictionary(forKey: "customCovers") as? [String: String]) ?? [:]
        appTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "") ?? .dark
    }

    // MARK: - Loading

    func load() {
        isScanning = true
        let root = rootURL
        let favs = favorites
        let added = addedURLs

        Task.detached(priority: .userInitiated) {
            let scanned = ProjectScanner.immediateProjects(in: root)
            let existing = Set(scanned.map { $0.id })
            let addedProjects = added
                .filter { FileManager.default.fileExists(atPath: $0.path) }
                .filter { !existing.contains($0.path) }
                .map { ProjectScanner.placeholder(for: $0) }
            let initial = scanned + addedProjects

            await MainActor.run {
                self.projects = initial.map {
                    var p = $0; p.isFavorite = favs.contains(p.id); return p
                }
            }

            await withTaskGroup(of: (String, ProjectScanner.Analysis, CoverSource).self) { group in
                for p in initial {
                    group.addTask {
                        let analysis = ProjectScanner.analyze(p.url)
                        let cover = CoverResolver.resolve(p)
                        return (p.id, analysis, cover)
                    }
                }
                for await (id, analysis, cover) in group {
                    await MainActor.run { self.apply(id: id, analysis: analysis, cover: cover) }
                }
            }
            await MainActor.run {
                self.applyCustomCovers()
                self.isScanning = false
                self.renderWebPreviews()
            }
        }
    }

    // MARK: - Custom (manual) covers

    func isCustomCover(_ id: Project.ID) -> Bool { customCovers[id] != nil }

    func setCustomCover(from imageURL: URL, for id: Project.ID) {
        guard let cached = CoverResolver.makeSquareThumbnail(from: imageURL) else { NSSound.beep(); return }
        customCovers[id] = cached.path
        UserDefaults.standard.set(customCovers, forKey: "customCovers")
        setCover(cached, for: id)
    }

    func resetCover(for id: Project.ID) {
        customCovers.removeValue(forKey: id)
        UserDefaults.standard.set(customCovers, forKey: "customCovers")
        load()   // re-resolve from scratch
    }

    func presentSetCover(for id: Project.ID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Set Cover"
        panel.message = "Choose an image to use as this project's cover"
        if panel.runModal() == .OK, let u = panel.url { setCustomCover(from: u, for: id) }
    }

    private func applyCustomCovers() {
        for (id, imgPath) in customCovers where FileManager.default.fileExists(atPath: imgPath) {
            setCover(URL(fileURLWithPath: imgPath), for: id)
        }
    }

    /// For projects that ended up with a metadata cover but have a renderable
    /// web front-end, render the real page (sequentially) and swap the cover in.
    private func renderWebPreviews() {
        Task { @MainActor in
            let renderer = WebPreviewRenderer()
            for p in projects {
                guard case .generated = p.cover else { continue }
                guard let entry = ProjectScanner.htmlEntry(for: p.url) else { continue }

                let mtime = (try? FileManager.default.attributesOfItem(atPath: entry.path)[.modificationDate]) as? Date
                let seed = entry.path + "|" + String(Int(mtime?.timeIntervalSince1970 ?? 0))

                if let cached = CoverResolver.existingWebPreview(seed: seed) {
                    setCover(cached, for: p.id); continue
                }
                if let cg = await renderer.render(entry: entry, accessDir: p.url),
                   let url = CoverResolver.cacheWebPreview(cg, seed: seed) {
                    setCover(url, for: p.id)
                }
            }
        }
    }

    private func setCover(_ url: URL, for id: Project.ID) {
        if let i = projects.firstIndex(where: { $0.id == id }) {
            projects[i].cover = .image(url)
        }
    }

    private func apply(id: String, analysis: ProjectScanner.Analysis, cover: CoverSource) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].kind = analysis.kind
        projects[i].sizeBytes = analysis.sizeBytes
        projects[i].cover = cover
        projects[i].summary = analysis.summary

        var lang = analysis.language
        if analysis.kind == .backend, lang == "JavaScript" || lang == "TypeScript" {
            lang = "Node.js"
        }
        projects[i].language = lang
    }

    func setRoot(_ url: URL) {
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: "rootPath")
        load()
    }

    // MARK: - User-added library items

    func isAdded(_ id: Project.ID) -> Bool { addedURLs.contains { $0.path == id } }

    func addToLibrary(_ url: URL) {
        let path = url.path
        guard !addedURLs.contains(where: { $0.path == path }),
              !projects.contains(where: { $0.id == path }) else { return }
        addedURLs.append(url)
        persistAdded()

        var p = ProjectScanner.placeholder(for: url)
        p.isFavorite = favorites.contains(p.id)
        projects.insert(p, at: 0)

        let captured = p
        Task.detached(priority: .userInitiated) {
            let analysis = ProjectScanner.analyze(url)
            let cover = CoverResolver.resolve(captured)
            await MainActor.run { self.apply(id: path, analysis: analysis, cover: cover) }
        }
    }

    func removeFromLibrary(_ id: Project.ID) {
        addedURLs.removeAll { $0.path == id }
        persistAdded()
        projects.removeAll { $0.id == id }
    }

    private func persistAdded() {
        UserDefaults.standard.set(addedURLs.map { $0.path }, forKey: "addedPaths")
    }

    // MARK: - Pickers

    func presentAddFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Add folders to your library"
        if panel.runModal() == .OK { panel.urls.forEach { addToLibrary($0) } }
    }

    func presentAddFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Add files to your library"
        if panel.runModal() == .OK { panel.urls.forEach { addToLibrary($0) } }
    }

    func presentChooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = rootURL
        panel.prompt = "Use as Workspace"
        if panel.runModal() == .OK, let u = panel.url { setRoot(u) }
    }

    // MARK: - Favorites

    func isFavorite(_ id: Project.ID) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: Project.ID) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favorites")
        if let i = projects.firstIndex(where: { $0.id == id }) {
            projects[i].isFavorite = favorites.contains(id)
        }
    }

    // MARK: - Derived

    var visibleProjects: [Project] {
        var list = projects

        switch filter {
        case .allProjects:
            list.sort { $0.lastModified > $1.lastModified }
        case .favorites:
            list = list.filter { favorites.contains($0.id) }
                       .sorted { $0.lastModified > $1.lastModified }
        case .recent, .recentlyModified:
            list.sort { $0.lastModified > $1.lastModified }
        case .thisWeek:
            let weekAgo = Date().addingTimeInterval(-7 * 86_400)
            list = list.filter { $0.lastModified >= weekAgo }
                       .sorted { $0.lastModified > $1.lastModified }
        case .largeProjects:
            list.sort { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        case .kind(let k):
            list = list.filter { $0.kind == k }
                       .sorted { $0.lastModified > $1.lastModified }
        }

        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.displayPath.lowercased().contains(q) ||
                $0.language.lowercased().contains(q) ||
                $0.kind.label.lowercased().contains(q)
            }
        }
        return list
    }

    var totalSize: Int64 { projects.compactMap { $0.sizeBytes }.reduce(0, +) }

    var availableSpaceLabel: String {
        let v = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let bytes = v?.volumeAvailableCapacityForImportantUsage else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " available"
    }

    /// Counts per kind, for the Collections sidebar.
    func count(for kind: ProjectKind) -> Int { projects.filter { $0.kind == kind }.count }
}
