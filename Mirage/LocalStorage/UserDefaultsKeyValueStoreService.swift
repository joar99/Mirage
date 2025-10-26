import Foundation

public class UserDefaultsKeyValueStoreService: LocalKeyValueStoreServiceProtocol {
    private let userDefaults: UserDefaults?
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    private let appGroupIdentifier: String

    public init(appGroupIdentifier: String) {
        self.appGroupIdentifier = appGroupIdentifier
        userDefaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - PersistenceControllerProtocol

    public func store(_ value: PersistableValue, for key: PersistenceKey) {
        userDefaults?.set(value.underlyingValue, forKey: key.rawValue)
    }

    public func storeObject<T: Codable>(value: T, for key: PersistenceKey) throws {
        let data = try jsonEncoder.encode(value)
        userDefaults?.set(data, forKey: key.rawValue)
    }

    public func value<T>(for key: PersistenceKey, as type: T.Type?) -> T? {
        userDefaults?.value(forKey: key.rawValue) as? T
    }

    public func object<T: Codable>(for key: PersistenceKey, as type: T.Type?) throws -> T? {
        guard let data = userDefaults?.value(forKey: key.rawValue) as? Data else { return nil }
        return try jsonDecoder.decode(T.self, from: data)
    }

    public func removeValue(for key: PersistenceKey) {
        userDefaults?.removeObject(forKey: key.rawValue)
    }

    public func removeAllValues() {
        userDefaults?.removePersistentDomain(forName: appGroupIdentifier)
    }
}
