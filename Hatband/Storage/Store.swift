import Foundation
import SwiftData

/// The SwiftData container in its Class A directory. Opened only by
/// `AppModel.load()` once protected data is available.
@MainActor final class Store {
    let container: ModelContainer
    /// Nil in memory.
    let directory: URL?

    var context: ModelContext { container.mainContext }

    /// Application Support/Store.
    static let directoryURL: URL = URL.applicationSupportDirectory.appendingPathComponent("Store", isDirectory: true)

    /// Test hook, nil in production: "save", "erase", "reassert".
    static var onEvent: ((String) -> Void)?

    private init(container: ModelContainer, directory: URL?) {
        self.container = container
        self.directory = directory
    }

    static func onDisk() throws -> Store {
        try onDisk(at: directoryURL)
    }

    /// Creates the directory with complete protection before the container opens.
    static func onDisk(at directory: URL) throws -> Store {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        let configuration = ModelConfiguration(
            "Hatband", schema: Records.schema, url: directory.appendingPathComponent("Hatband.store"),
            allowsSave: true, cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
        let container = try ModelContainer(for: Records.schema, configurations: configuration)
        let store = Store(container: container, directory: directory)
        store.reassertProtection()
        return store
    }

    static func inMemory() throws -> Store {
        let configuration = ModelConfiguration(
            schema: Records.schema, isStoredInMemoryOnly: true, allowsSave: true,
            groupContainer: ModelConfiguration.GroupContainer.none,
            cloudKitDatabase: ModelConfiguration.CloudKitDatabase.none)
        let container = try ModelContainer(for: Records.schema, configurations: configuration)
        return Store(container: container, directory: nil)
    }

    /// Complete protection on the directory and every file in it, -wal and
    /// -shm included. Idempotent.
    func reassertProtection() {
        defer { Store.onEvent?("reassert") }
        guard let directory else { return }
        let manager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        try? manager.setAttributes(attributes, ofItemAtPath: directory.path)
        let files = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])) ?? []
        for file in files {
            try? manager.setAttributes(attributes, ofItemAtPath: file.path)
        }
    }

    func setExcludedFromBackup(_ excluded: Bool) throws {
        guard var url = directory else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try url.setResourceValues(values)
    }

    func owner() throws -> OwnerRecord? {
        try context.fetch(FetchDescriptor<OwnerRecord>()).first
    }

    /// Every person, oldest update first.
    func people() throws -> [PersonRecord] {
        let descriptor = FetchDescriptor<PersonRecord>(sortBy: [SortDescriptor(\.updatedAt)])
        return try context.fetch(descriptor)
    }

    /// Matched in Swift: no `#Predicate` over `Data`.
    func person(id: Data) throws -> PersonRecord? {
        try people().first { $0.personaID == id }
    }

    func insert(_ record: any PersistentModel) {
        context.insert(record)
    }

    func delete(_ record: any PersistentModel) {
        context.delete(record)
    }

    func save() throws {
        try context.save()
        Store.onEvent?("save")
    }

    /// Empties the persistent store. Drop this instance afterwards.
    func erase() throws {
        try container.erase()
        Store.onEvent?("erase")
    }

    static func removeDirectory() {
        removeDirectory(at: directoryURL)
    }

    /// After the `Store` instance is dropped.
    static func removeDirectory(at directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
