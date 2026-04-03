import Foundation

enum AppVariant: String {
    case prod
    case test

    static var current: AppVariant {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "MirageAppVariant") as? String,
              let variant = AppVariant(rawValue: rawValue) else {
            return .prod
        }

        return variant
    }

    var isTest: Bool {
        self == .test
    }
}
