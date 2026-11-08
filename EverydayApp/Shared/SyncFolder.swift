// Keeps your iPhone and iPad in step through a folder you pick, like "EverydayApp" in
// iCloud Drive. Every device that picks the same folder reads and writes the same file
// (EverydayApp.json, the same format as a backup), and iCloud copies it between them.
// This works with a free Apple developer account, because the app only uses a folder
// you chose. It doesn't need Apple's built-in iCloud sync.
//
// Whichever copy was changed most recently wins. The app checks when it opens, every
// 30 seconds while it's open, a moment after you change something, and when you leave it.

import Foundation
import SwiftData

@MainActor
@Observable
final class SyncFolder {
    nonisolated static let fileName = "EverydayApp.json"
    private static let bookmarkKey = "syncFolderBookmark"
    private static let nameKey = "syncFolderName"
    private static let changedKey = "syncLocalChangedAt"
    private static let fingerprintKey = "syncFingerprint"

    private(set) var folderName: String?
    private(set) var lastSynced: Date?
    var problem: String?

    private var folder: URL?
    var isOn: Bool { folder != nil }

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private var checking = false
    private var soon: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
        folder = Self.resolveBookmark()
        folderName = folder == nil ? nil : UserDefaults.standard.string(forKey: Self.nameKey)
        // Any save to the database (your changes) triggers a sync a moment later.
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                self?.syncSoon()
            }
        }
    }

    // MARK: This device's changes

    /// When this device's data last changed. Compared with the folder copy's `savedAt`.
    private var localChangedAt: Date {
        get { UserDefaults.standard.object(forKey: Self.changedKey) as? Date ?? .distantPast }
        // Kept to the millisecond, like the file, so equal times compare as equal.
        set { UserDefaults.standard.set(newValue.toMillisecond, forKey: Self.changedKey) }
    }

    /// The fingerprint of the data when we last looked, to notice changes.
    private var knownFingerprint: String? {
        get { UserDefaults.standard.string(forKey: Self.fingerprintKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.fingerprintKey) }
    }

    /// This device's data as a backup, stamped with when it last changed.
    private func currentBackup() throws -> EverydayBackup {
        if context.hasChanges { try context.save() }
        var backup = try EverydayBackup(from: context)
        let fingerprint = backup.fingerprint
        if fingerprint != knownFingerprint {
            knownFingerprint = fingerprint
            localChangedAt = .now
        }
        backup.savedAt = localChangedAt
        return backup
    }

    /// Replaces this device's data with a backup, without counting it as a new change.
    private func apply(_ backup: EverydayBackup) throws {
        try backup.restore(into: context)
        knownFingerprint = try EverydayBackup(from: context).fingerprint
        localChangedAt = backup.savedAt
    }

    // MARK: Syncing

    /// Syncs 2 seconds from now, so a burst of taps turns into one sync.
    func syncSoon() {
        guard isOn else { return }
        soon?.cancel()
        soon = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    /// Brings in the other device's changes if they're newer, or sends this device's if they are.
    func syncNow() async {
        guard let folder, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let local = try currentBackup()
            let found = try await Task.detached { try SyncFolder.read(folder: folder) }.value
            let copies = found.copies.compactMap(EverydayBackup.decode)
            if found.copies.isEmpty {
                try await write(local)   // empty folder: start it with this device's data
            } else if let remote = copies.max(by: { $0.savedAt < $1.savedAt }) {
                // When both devices wrote at once, iCloud keeps the extra copies on the side.
                // The newest copy of all wins, and the file is rewritten as that one.
                let same = remote.fingerprint == local.fingerprint
                let theirs = remote.savedAt.milliseconds, mine = local.savedAt.milliseconds
                if theirs > mine && !same {
                    try apply(remote)
                }
                if found.hadConflicts || (mine > theirs && !same) {
                    try await write(try currentBackup())
                    await Task.detached { SyncFolder.resolveConflicts(folder: folder) }.value
                }
            } else {
                problem = "The file in this folder isn't an EverydayApp file."
                return
            }
            problem = nil
            lastSynced = .now
        } catch {
            problem = "Couldn't sync: \(error.localizedDescription)"
        }
    }

    private func write(_ backup: EverydayBackup) async throws {
        guard let folder else { return }
        let data = try backup.encoded()
        try await Task.detached { try SyncFolder.write(data, folder: folder) }.value
    }

    // MARK: Setting up

    /// Starts syncing with a folder you picked. Returns what's already in the folder (from
    /// your other device), if anything, so you can choose which copy to keep.
    func connect(_ url: URL) -> EverydayBackup? {
        do {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Self.nameKey)
            folder = Self.resolveBookmark() ?? url
            folderName = url.lastPathComponent
            problem = nil
            let copies = try Self.read(folder: folder!).copies
            guard !copies.isEmpty else { return nil }
            guard let found = copies.compactMap(EverydayBackup.decode).max(by: { $0.savedAt < $1.savedAt }) else {
                problem = "The file in this folder isn't an EverydayApp file."
                return nil
            }
            return found.isEmpty ? nil : found
        } catch {
            problem = "Couldn't use that folder: \(error.localizedDescription)"
            return nil
        }
    }

    /// Keeps the folder's copy (from your other device) and replaces this device's data with it.
    func useFolderCopy(_ backup: EverydayBackup) {
        do {
            try apply(backup)
            problem = nil
            lastSynced = .now
        } catch {
            problem = "Couldn't load the folder's copy: \(error.localizedDescription)"
        }
    }

    /// Makes this device's data the copy in the folder.
    func useThisDevice() async {
        localChangedAt = .now
        knownFingerprint = nil
        do {
            let backup = try currentBackup()
            try await write(backup)
            problem = nil
            lastSynced = .now
        } catch {
            problem = "Couldn't save to the folder: \(error.localizedDescription)"
        }
    }

    /// Stops syncing. The file in the folder is left alone.
    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        soon?.cancel()
        folder = nil
        folderName = nil
        lastSynced = nil
        problem = nil
    }

    // MARK: Backups

    /// Replaces everything on this device with a backup file. If syncing is on, the
    /// backup then counts as the newest copy and goes to your other devices too.
    func importBackup(_ backup: EverydayBackup) throws {
        try backup.restore(into: context)
        syncSoon()
    }

    /// Writes a backup file to share or save, named like "EverydayApp backup 2026-11-08.json".
    func makeBackupFile() throws -> URL {
        if context.hasChanges { try context.save() }
        let day = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appending(path: "EverydayApp backup \(day).json")
        try EverydayBackup(from: context).encoded().write(to: url, options: .atomic)
        return url
    }

    // MARK: File access

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        // A moved folder still resolves, but the saved bookmark should be refreshed.
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    enum SyncError: LocalizedError {
        case downloading
        var errorDescription: String? { "The other device's copy is still downloading from iCloud. Try again in a moment." }
    }

    /// What's in the folder: the file, plus any copies iCloud set aside because two devices
    /// saved at the same time. No copies means there's no file yet.
    nonisolated struct Found: Sendable {
        var copies: [Data] = []
        var hadConflicts = false
    }

    /// Reads the file through a file coordinator, which also waits for iCloud. If iCloud hasn't
    /// downloaded it yet, starts that and throws, so an empty-looking folder never overwrites
    /// your other device's data.
    nonisolated private static func read(folder: URL) throws -> Found {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appending(path: fileName)
        let placeholder = folder.appending(path: ".\(fileName).icloud")
        let files = FileManager.default
        if !files.fileExists(atPath: file.path), files.fileExists(atPath: placeholder.path) {
            try? files.startDownloadingUbiquitousItem(at: file)
            throw SyncError.downloading
        }
        var found = Found()
        var inner: Error?
        var outer: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &outer) { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do { found.copies.append(try Data(contentsOf: url)) } catch { inner = error }
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
                found.hadConflicts = true
                if let data = try? Data(contentsOf: version.url) { found.copies.append(data) }
            }
        }
        if let error = outer ?? inner { throw error }
        return found
    }

    /// Clears the copies iCloud set aside, once the newest one has been written as the file.
    nonisolated private static func resolveConflicts(folder: URL) {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appending(path: fileName)
        NSFileCoordinator().coordinate(writingItemAt: file, options: [], error: nil) { url in
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
                version.isResolved = true
            }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
    }

    nonisolated private static func write(_ data: Data, folder: URL) throws {
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        let file = folder.appending(path: fileName)
        var inner: Error?
        var outer: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &outer) { url in
            do { try data.write(to: url, options: .atomic) } catch { inner = error }
        }
        if let error = outer ?? inner { throw error }
    }
}
