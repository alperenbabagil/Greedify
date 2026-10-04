import Foundation
import Observation

/// Where user themes live. Injected so tests can use an in-memory folder.
public protocol ThemeFolder {
    var url: URL? { get }
    func list() throws -> [String]
    func read(_ name: String) throws -> Data
    func write(_ data: Data, as name: String) throws
    func delete(_ name: String) throws
}

public struct DiskThemeFolder: ThemeFolder {
    public let directory: URL
    private let trash: (URL) throws -> Void

    /// `trash` disposes of a deleted theme file; it moves it to the Trash by default, so a delete can be undone.
    public init(directory: URL, trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.directory = directory
        self.trash = trash
    }
    public var url: URL? { directory }

    public func list() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }
    public func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
    public func write(_ data: Data, as name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    public func delete(_ name: String) throws { try trash(directory.appendingPathComponent(name)) }
}

/// One theme in the list: a built-in, a user file, or a user file that failed to load (`theme == nil`).
public struct ThemeEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let theme: Theme?
    public let error: String?
    public let isBuiltin: Bool

    public init(id: String, theme: Theme?, error: String?, isBuiltin: Bool) {
        self.id = id; self.theme = theme; self.error = error; self.isBuiltin = isBuiltin
    }

    public var isSystem: Bool { id == ThemeStore.systemID }
    public var name: String { theme?.name ?? id }
}

/// The themes: built-ins only for the user; Debug builds add live recipes from a folder as `dev.<file>`
/// (curated skins spec §4–§5). An old selection of an imported skin maps to its curated theme.
@MainActor @Observable
public final class ThemeStore {
    public nonisolated static let systemID = "builtin.system"
    nonisolated static let fileExtension = "greedifytheme"
    nonisolated static let devPrefix = "dev."

    public private(set) var entries: [ThemeEntry] = []
    public private(set) var selectedID: String
    @ObservationIgnored private let devFolder: (any ThemeFolder)?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let builtins: [ThemeEntry]

    /// `devFolder`: recipes being tuned (Debug only; the app passes nil in Release). `legacyFolder`: the old Themes
    /// folder, read once to map a selected imported skin to its curated theme.
    public init(settings: AppSettings, devFolder: (any ThemeFolder)? = nil, legacyFolder: (any ThemeFolder)? = nil) {
        self.devFolder = devFolder
        self.settings = settings
        builtins = Theme.builtins().map { ThemeEntry(id: $0.id, theme: $0.theme, error: nil, isBuiltin: true) }
        selectedID = settings.themeID
        reload()
        migrateImportedSelection(legacyFolder)
    }

    public var devFolderURL: URL? { devFolder?.url }

    /// The selected theme, or System while the selected one is missing or broken (the selection is kept,
    /// so a dev recipe comes back once it's fixed).
    public var current: ThemeEntry {
        entries.first { $0.id == selectedID && $0.theme != nil }
            ?? builtins.first
            ?? ThemeEntry(id: Self.systemID, theme: Theme.defaults(for: .dark), error: nil, isBuiltin: true)
    }

    public func reload() {
        let names = ((try? devFolder?.list()) ?? [])
            .filter { ($0 as NSString).pathExtension == Self.fileExtension }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let dev = names.compactMap { name -> ThemeEntry? in
            guard let devFolder else { return nil }
            let id = Self.devPrefix + name
            do { return ThemeEntry(id: id, theme: try Theme.decode(from: devFolder.read(name)), error: nil, isBuiltin: false) }
            catch { return ThemeEntry(id: id, theme: nil, error: "Couldn't read this recipe: \(Self.reason(error))", isBuiltin: false) }
        }
        entries = builtins + dev
    }

    public func select(_ id: String) {
        selectedID = id
        settings.themeID = id
    }

    /// A selection left from the import era (a file name in the old Themes folder) becomes the curated theme of the
    /// same skin, matched by the skin file named in `source` (or the old file's name), else System.
    private func migrateImportedSelection(_ legacyFolder: (any ThemeFolder)?) {
        guard !selectedID.hasPrefix("builtin."), !selectedID.hasPrefix(Self.devPrefix) else { return }
        let recorded = (try? legacyFolder?.read(selectedID)).flatMap { try? Theme.decode(from: $0) }?.source
        let wanted = Self.skinStem(ofSource: recorded) ?? Self.stem(selectedID)
        let match = builtins.first { entry in
            guard let stem = Self.skinStem(ofSource: entry.theme?.source) else { return false }
            return stem.caseInsensitiveCompare(wanted) == .orderedSame
        }
        select(match?.id ?? Self.systemID)
    }

    /// `Winamp skin base-2.91.wsz` → `base-2.91`.
    nonisolated static func skinStem(ofSource source: String?) -> String? {
        guard let source, source.hasPrefix("Winamp skin ") else { return nil }
        return stem(String(source.dropFirst("Winamp skin ".count)))
    }

    nonisolated static func stem(_ file: String) -> String { (file as NSString).deletingPathExtension }

    /// A one-line reason for a theme file that failed to load.
    nonisolated static func reason(_ error: Error) -> String {
        var text: String
        switch error {
        case DecodingError.dataCorrupted(let context), DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context), DecodingError.keyNotFound(_, let context):
            text = ((context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String) ?? context.debugDescription
        default:
            text = error.localizedDescription
        }
        text = text.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        text = text.trimmingCharacters(in: .whitespaces)
        if text.count > 120 { text = String(text.prefix(119)) + "…" }
        return text.isEmpty ? "unknown error" : text
    }
}
