import Foundation

public struct ImportOptions: Sendable, Codable {
    public var delimiter = "" // empty = detect
    public var header = true
    public var sheet = "" // empty = first worksheet
    public var decimalComma = false
    public init() {}
}

public enum InferredDataType: String, Sendable, Codable {
    case integer
    case decimal
    case date
    case string
    case empty

    public var displayName: String {
        switch self {
        case .integer: "Ganzzahl"
        case .decimal: "Dezimalzahl"
        case .date: "Datum"
        case .string: "Text"
        case .empty: "Leer"
        }
    }
}

public struct ColumnProfile: Sendable, Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let nulls: Int
    public let empty: Int
    public let whitespace: Int
    public let distinct: Int
    public let numeric: Int
    public let minimum: Double?
    public let maximum: Double?
    public let mean: Double?
    public let dataType: InferredDataType
    public let maximumLength: Int
    public var missing: Int { nulls + empty + whitespace }
}

public enum RowFilter: String, Sendable, Codable, CaseIterable, Identifiable {
    case all
    case missing
    case null
    case empty
    case whitespace
    case typeViolation

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .all: "Alle Werte"
        case .missing: "Fehlend"
        case .null: "NULL"
        case .empty: "Leer"
        case .whitespace: "Whitespace"
        case .typeViolation: "Typverletzung"
        }
    }
}

public struct ValueFrequency: Sendable, Codable, Identifiable {
    public let value: String
    public let count: Int
    public var id: String { value }
}

public struct NumericDistribution: Sendable, Codable {
    public let firstQuartile: Double
    public let median: Double
    public let thirdQuartile: Double
    public let bins: [Int]
}

public enum RuleKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case required
    case unique
    case numberRange
    case matchesPattern

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .required: "Pflichtfeld"
        case .unique: "Eindeutig"
        case .numberRange: "Zahlenbereich"
        case .matchesPattern: "Muster (Regex)"
        }
    }
}

public struct ProfileRule: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public var kind: RuleKind
    public var minimum: Double?
    public var maximum: Double?
    public var pattern: String

    public init(id: UUID = UUID(), kind: RuleKind, minimum: Double? = nil, maximum: Double? = nil, pattern: String = "") {
        self.id = id
        self.kind = kind
        self.minimum = minimum
        self.maximum = maximum
        self.pattern = pattern
    }
}

public struct RuleResult: Sendable, Codable, Identifiable {
    public let ruleID: UUID
    public let ruleName: String
    public let violations: Int
    public var id: UUID { ruleID }
}

public struct DetailRow: Sendable, Codable, Identifiable {
    public let rowNumber: Int
    public let values: [String?]
    public var id: Int { rowNumber }
}

public struct ColumnDetail: Sendable, Codable {
    public let columnName: String
    public let filter: RowFilter
    public let matchingRows: Int
    public let rows: [DetailRow]
    public let frequentValues: [ValueFrequency]
    public let textPatterns: [ValueFrequency]
    public let numericDistribution: NumericDistribution?
    public let ruleResults: [RuleResult]
}

public struct Profile: Sendable, Codable {
    public let source: String
    public let options: ImportOptions
    public let rows: Int
    public let columns: [ColumnProfile]
    public let preview: [[String?]]
    public let importSeconds: Double
    public let totalSeconds: Double
    public let fileBytes: Int64
    public let engineVersion: String
    public let createdAt: Date
}
public struct ProfilingError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
