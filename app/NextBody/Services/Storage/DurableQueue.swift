import Foundation

/// Imports legacy queues only after every operation has been durably read back.
public struct DurableQueue<Item: Codable> {
    private let kind: String
    private let store: LocalDataStore
    public init(kind: String, store: LocalDataStore) { self.kind = kind; self.store = store }
    public func items() throws -> [Item] {
        try store.allOperations(kind: kind).map { try JSONDecoder().decode(Item.self, from: $0.payload) }
    }
    public func save(_ item: Item, id: String, account: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(item)
        try store.enqueue(operation: LocalOperation(id: id, account: account, kind: kind, payload: data))
    }
    public func acknowledge(id: String, account: String) throws { try store.acknowledge(account: account, id: id) }
    public func importLegacy(_ items: [Item], identity: (Item) -> (String, String)) throws {
        for item in items {
            let (id,account) = identity(item)
            try save(item, id: id, account: account)
        }
        for item in items {
            let (id,account) = identity(item)
            guard try store.operations(account: account, kind: kind).contains(where: { $0.id == id }) else {
                throw LocalDataStore.Failure.database("Pending record import was not verified")
            }
        }
    }
}
