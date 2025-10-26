public protocol LocalKeyValueStoreServiceProtocol: AnyObject {
    func store(_ value: PersistableValue, for key: PersistenceKey)
    func storeObject<T: Codable>(value: T, for key: PersistenceKey) throws

    func value<T>(for key: PersistenceKey, as type: T.Type?) -> T?
    func object<T: Codable>(for key: PersistenceKey, as type: T.Type?) throws -> T?

    func removeValue(for key: PersistenceKey)
    func removeAllValues()
}

extension LocalKeyValueStoreServiceProtocol {
    public func value<T>(for key: PersistenceKey) -> T? {
        value(for: key, as: nil)
    }

    public func value<T>(for key: PersistenceKey, default defaultValue: T) -> T {
        value(for: key, default: defaultValue, as: nil)
    }

    public func value<T>(for key: PersistenceKey, default defaultValue: T, as type: T.Type? = nil) -> T {
        value(for: key, as: type) ?? defaultValue
    }

    public func bool(for key: PersistenceKey, default defaultValue: Bool = false) -> Bool {
        value(for: key, as: Bool.self) ?? defaultValue
    }

    public func object<T: Codable>(for key: PersistenceKey) throws -> T? {
        try object(for: key, as: nil)
    }

    public func object<T: Codable>(for key: PersistenceKey, default defaultValue: T) -> T {
        object(for: key, default: defaultValue, as: nil)
    }

    public func object<T: Codable>(for key: PersistenceKey, default defaultValue: T, as type: T.Type? = nil) -> T {
        (try? object(for: key, as: type)) ?? defaultValue
    }
}
