import Foundation

public indirect enum PersistableValue: Hashable {
    case string(String?)
    case number(NSNumber?)
    case bool(Bool?)
    case date(Date?)
    case data(Data?)
    case array([PersistableValue]?)
    case dictionary([String: PersistableValue]?)

    // swiftlint:disable:next cyclomatic_complexity
    public static func number<N: Numeric>(_ numeric: N) -> PersistableValue {
        switch numeric {
        case let value as CChar:
            return .number(NSNumber(value: value))
        case let value as UInt8:
            return .number(NSNumber(value: value))
        case let value as Int16:
            return .number(NSNumber(value: value))
        case let value as UInt16:
            return .number(NSNumber(value: value))
        case let value as Int32:
            return .number(NSNumber(value: value))
        case let value as UInt32:
            return .number(NSNumber(value: value))
        case let value as Int64:
            return .number(NSNumber(value: value))
        case let value as UInt64:
            return .number(NSNumber(value: value))
        case let value as Float:
            return .number(NSNumber(value: value))
        case let value as Double:
            return .number(NSNumber(value: value))
        case let value as Bool:
            return .number(NSNumber(value: value))
        case let value as Int:
            return .number(NSNumber(value: value))
        case let value as UInt:
            return .number(NSNumber(value: value))
        default:
            return .number(nil)
        }
    }

    public var underlyingValue: AnyHashable {
        switch self {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let bool):
            return bool
        case .date(let date):
            return date
        case .data(let data):
            return data
        case .array(let array):
            return array?.map(\.underlyingValue)
        case .dictionary(let dictionary):
            return dictionary.map {
                [String: AnyHashable](uniqueKeysWithValues: $0.map { key, value in
                    (key, value.underlyingValue)
                })
            }
        }
    }
}
