import Foundation
import CDuckDB

// Only interrupt is called concurrently. The lock protects pointer lifetime and
// the sticky cancellation flag; the connection itself belongs to the worker.
public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var connection: duckdb_connection?
    public init() {}
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let connection { duckdb_interrupt(connection) }
    }
    public func check() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
    fileprivate func attach(_ connection: duckdb_connection?) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.connection = connection
    }
    fileprivate func detach() {
        lock.lock(); defer { lock.unlock() }; connection = nil
    }
}

final class Database {
    private var database: duckdb_database?
    private var connection: duckdb_connection?
    private let cancellation: Cancellation
    private let temporary: URL
    init(cancellation: Cancellation) throws {
        self.cancellation = cancellation
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DataScope-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        guard duckdb_open(nil, &database) == DuckDBSuccess else { throw ProfilingError("DuckDB konnte nicht geöffnet werden.") }
        guard duckdb_connect(database, &connection) == DuckDBSuccess else {
            duckdb_close(&database); throw ProfilingError("DuckDB-Verbindung fehlgeschlagen.")
        }
        do {
            try cancellation.attach(connection)
            try execute("SET autoinstall_known_extensions = false")
            try execute("SET autoload_known_extensions = false")
            try execute("SET threads = 4")
            try execute("SET memory_limit = '512MB'")
            try execute("SET temp_directory = \(literal(temporary.path))")
        } catch {
            cancellation.detach(); duckdb_disconnect(&connection); duckdb_close(&database)
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
    deinit {
        cancellation.detach(); duckdb_disconnect(&connection); duckdb_close(&database)
        try? FileManager.default.removeItem(at: temporary)
    }
    func execute(_ sql: String) throws { _ = try query(sql) }
    func query(_ sql: String) throws -> [[String?]] {
        try cancellation.check()
        var result = duckdb_result()
        defer { duckdb_destroy_result(&result) }
        let state = duckdb_query(connection, sql, &result)
        try cancellation.check()
        guard state == DuckDBSuccess else {
            let message = duckdb_result_error(&result).map { String(cString: $0) } ?? "Unbekannter DuckDB-Fehler"
            throw ProfilingError(message)
        }
        return (0..<duckdb_row_count(&result)).map { row in
            (0..<duckdb_column_count(&result)).map { column in
                if duckdb_value_is_null(&result, column, row) { return nil }
                guard let value = duckdb_value_varchar(&result, column, row) else { return nil }
                defer { duckdb_free(value) }
                return String(cString: value)
            }
        }
    }
}
func literal(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
func identifier(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

public enum Profiler {
    public static func extensionURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["DATASCOPE_EXCEL_EXTENSION"] { return URL(fileURLWithPath: path) }
        if let resource = Bundle.main.resourceURL?.appendingPathComponent("excel.duckdb_extension"),
           FileManager.default.fileExists(atPath: resource.path) { return resource }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Vendor/excel.duckdb_extension")
    }

    private static func importData(into db: Database, url: URL, options: ImportOptions) throws {
        let format = url.pathExtension.lowercased()
        let source: String
        if format == "xlsx" {
            let ext = extensionURL()
            guard FileManager.default.fileExists(atPath: ext.path) else { throw ProfilingError("Excel-Erweiterung fehlt. Bitte scripts/setup.sh ausführen.") }
            try db.execute("LOAD \(literal(ext.path))")
            let sheet = options.sheet.isEmpty ? "" : ", sheet=\(literal(options.sheet))"
            source = "read_xlsx(\(literal(url.path)), header=\(options.header), all_varchar=true, stop_at_empty=false\(sheet))"
        } else if ["csv", "tsv"].contains(format) {
            let delimiter = options.delimiter.isEmpty ? (format == "tsv" ? "\t" : "") : options.delimiter
            guard delimiter.utf8.count <= 4 else { throw ProfilingError("Das Trennzeichen darf höchstens vier UTF-8-Bytes haben.") }
            let delim = delimiter.isEmpty ? "" : ", delim=\(literal(delimiter))"
            source = "read_csv(\(literal(url.path)), header=\(options.header), all_varchar=true, allow_quoted_nulls=false, nullstr='', strict_mode=true, ignore_errors=false, skip=0, null_padding=false\(delim))"
        } else {
            throw ProfilingError("Bitte eine CSV-, TSV- oder XLSX-Datei auswählen.")
        }
        try db.execute("CREATE TABLE imported AS SELECT * FROM \(source)")
    }

    private static func expressions(for column: String, decimalComma: Bool) -> (cleaned: String, number: String, date: String) {
        let cleaned = "regexp_replace(\(column), '^\\s+|\\s+$', '', 'g')"
        let number = decimalComma
            ? "CASE WHEN regexp_full_match(\(cleaned), '[+-]?([0-9]+|[0-9]{1,3}(\\.[0-9]{3})+)(,[0-9]+)?') THEN try_cast(replace(replace(\(cleaned), '.', ''), ',', '.') AS DOUBLE) END"
            : "try_cast(\(cleaned) AS DOUBLE)"
        let date = """
            CASE
                WHEN regexp_full_match(\(cleaned), '[0-9]{4}-[0-9]{2}-[0-9]{2}') THEN try_cast(\(cleaned) AS DATE)
                WHEN regexp_full_match(\(cleaned), '[0-9]{2}\\.[0-9]{2}\\.[0-9]{4}') THEN try_strptime(\(cleaned), '%d.%m.%Y')::DATE
                WHEN regexp_full_match(\(cleaned), '[0-9]{2}/[0-9]{2}/[0-9]{4}') THEN try_strptime(\(cleaned), '%d/%m/%Y')::DATE
            END
            """
        return (cleaned, number, date)
    }

    public static func run(url: URL, options: ImportOptions = .init(), cancellation: Cancellation = .init(),
                           progress: @Sendable (String) -> Void = { _ in }) throws -> Profile {
        let start = Date()
        try cancellation.check()
        let db = try Database(cancellation: cancellation)
        progress("Datei wird importiert …")
        try importData(into: db, url: url, options: options)
        let importSeconds = Date().timeIntervalSince(start)
        let rows = Int(try db.query("SELECT count(*) FROM imported")[0][0]!)!
        let names = try db.query("DESCRIBE imported").compactMap { $0[0] }
        var profiles: [ColumnProfile] = []
        for (index, name) in names.enumerated() {
            try cancellation.check()
            progress("Spalte \(index + 1) von \(names.count): \(name)")
            let col = identifier(name)
            let expressions = expressions(for: col, decimalComma: options.decimalComma)
            let cleaned = expressions.cleaned
            let number = expressions.number
            let date = expressions.date
            let result = try db.query("""
                WITH vals AS (SELECT \(col) AS v, \(cleaned) AS cleaned, \(number) AS n, \(date) AS d FROM imported)
                SELECT count(*) FILTER (WHERE v IS NULL),
                       count(*) FILTER (WHERE v = ''),
                       count(*) FILTER (WHERE v <> '' AND cleaned = ''),
                       count(DISTINCT v) FILTER (WHERE cleaned <> ''),
                       count(*) FILTER (WHERE isfinite(n)),
                       min(n) FILTER (WHERE isfinite(n)),
                       max(n) FILTER (WHERE isfinite(n)),
                       avg(n) FILTER (WHERE isfinite(n)),
                       count(*) FILTER (WHERE d IS NOT NULL),
                       count(*) FILTER (WHERE regexp_full_match(cleaned, '[+-]?(0|[1-9][0-9]*)')),
                       count(*) FILTER (WHERE isfinite(n) AND regexp_matches(cleaned, '[.,]')),
                       coalesce(max(char_length(v)), 0) FROM vals
                """)[0]
            let nulls = Int(result[0]!)!
            let empty = Int(result[1]!)!
            let whitespace = Int(result[2]!)!
            let numeric = Int(result[4]!)!
            let meaningful = rows - nulls - empty - whitespace
            let dateCount = Int(result[8]!)!
            let integerCount = Int(result[9]!)!
            let decimalCount = Int(result[10]!)!
            let dataType: InferredDataType
            if meaningful == 0 {
                dataType = .empty
            } else if dateCount == meaningful {
                dataType = .date
            } else if numeric == meaningful && integerCount == meaningful {
                dataType = .integer
            } else if numeric == meaningful && decimalCount > 0 {
                dataType = .decimal
            } else {
                dataType = .string
            }
            profiles.append(ColumnProfile(name: name, nulls: Int(result[0]!)!, empty: Int(result[1]!)!,
                                          whitespace: Int(result[2]!)!, distinct: Int(result[3]!)!, numeric: numeric,
                                          minimum: result[5].flatMap(Double.init), maximum: result[6].flatMap(Double.init),
                                          mean: result[7].flatMap(Double.init), dataType: dataType,
                                          maximumLength: Int(result[11]!)!))
        }
        let preview = try db.query("SELECT * FROM imported LIMIT 100")
        try cancellation.check()
        let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return Profile(source: url.lastPathComponent, options: options, rows: rows, columns: profiles, preview: preview,
                       importSeconds: importSeconds, totalSeconds: Date().timeIntervalSince(start), fileBytes: bytes,
                       engineVersion: String(cString: duckdb_library_version()), createdAt: Date())
    }

    public static func inspect(url: URL, options: ImportOptions, columnName: String,
                               inferredType: InferredDataType, filter: RowFilter,
                               rules: [ProfileRule], cancellation: Cancellation = .init()) throws -> ColumnDetail {
        let db = try Database(cancellation: cancellation)
        try importData(into: db, url: url, options: options)
        let names = try db.query("DESCRIBE imported").compactMap { $0[0] }
        guard names.contains(columnName) else { throw ProfilingError("Die Spalte \(columnName) wurde nicht gefunden.") }
        let column = identifier(columnName)
        let expressions = expressions(for: column, decimalComma: options.decimalComma)
        let values = "SELECT \(column) AS v, \(expressions.cleaned) AS cleaned, \(expressions.number) AS n, \(expressions.date) AS d FROM imported"
        let filterCondition: String
        switch filter {
        case .all: filterCondition = "true"
        case .missing: filterCondition = "v IS NULL OR v = '' OR (v <> '' AND cleaned = '')"
        case .null: filterCondition = "v IS NULL"
        case .empty: filterCondition = "v = ''"
        case .whitespace: filterCondition = "v <> '' AND cleaned = ''"
        case .typeViolation:
            switch inferredType {
            case .integer:
                filterCondition = "cleaned <> '' AND (n IS NULL OR NOT isfinite(n) OR NOT regexp_full_match(cleaned, '[+-]?(0|[1-9][0-9]*)'))"
            case .decimal:
                filterCondition = "cleaned <> '' AND (n IS NULL OR NOT isfinite(n))"
            case .date:
                filterCondition = "cleaned <> '' AND d IS NULL"
            case .string, .empty:
                filterCondition = "false"
            }
        }
        let matchingRows = Int(try db.query("WITH vals AS (\(values)) SELECT count(*) FROM vals WHERE \(filterCondition)")[0][0]!)!
        let selectedColumns = names.map(identifier).joined(separator: ", ")
        let rowResults = try db.query("""
            WITH vals AS (
                SELECT row_number() OVER () AS row_number, imported.*, \(column) AS v, \(expressions.cleaned) AS cleaned,
                       \(expressions.number) AS n, \(expressions.date) AS d FROM imported
            )
            SELECT row_number, \(selectedColumns) FROM vals WHERE \(filterCondition) LIMIT 200
            """)
        let rows = rowResults.compactMap { row -> DetailRow? in
            guard let first = row.first, let text = first, let number = Int(text) else { return nil }
            return DetailRow(rowNumber: number, values: Array(row.dropFirst()))
        }
        let frequentValues = try db.query("""
            WITH vals AS (\(values))
            SELECT v, count(*) FROM vals WHERE cleaned <> '' GROUP BY v ORDER BY count(*) DESC, v LIMIT 5
            """).compactMap { row -> ValueFrequency? in
                guard let value = row[0], let count = row[1].flatMap(Int.init) else { return nil }
                return ValueFrequency(value: value, count: count)
            }
        let textPatterns = try db.query("""
            WITH vals AS (\(values))
            SELECT regexp_replace(regexp_replace(cleaned, '[0-9]', '0', 'g'), '[[:alpha:]]', 'A', 'g'), count(*)
            FROM vals WHERE cleaned <> '' GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 5
            """).compactMap { row -> ValueFrequency? in
                guard let value = row[0], let count = row[1].flatMap(Int.init) else { return nil }
                return ValueFrequency(value: value, count: count)
            }
        let summary = try db.query("""
            WITH vals AS (\(values))
            SELECT min(n) FILTER (WHERE isfinite(n)), max(n) FILTER (WHERE isfinite(n)),
                   quantile_cont(n, 0.25) FILTER (WHERE isfinite(n)),
                   quantile_cont(n, 0.5) FILTER (WHERE isfinite(n)),
                   quantile_cont(n, 0.75) FILTER (WHERE isfinite(n)),
                   count(*) FILTER (WHERE isfinite(n)) FROM vals
            """)[0]
        let distribution: NumericDistribution?
        if let minimum = summary[0].flatMap(Double.init), let maximum = summary[1].flatMap(Double.init),
           let q1 = summary[2].flatMap(Double.init), let median = summary[3].flatMap(Double.init),
           let q3 = summary[4].flatMap(Double.init), let numericCount = summary[5].flatMap(Int.init) {
            var bins: [Int] = []
            if minimum == maximum {
                bins = [numericCount, 0, 0, 0, 0]
            } else {
                for index in 0..<5 {
                    let lower = minimum + (maximum - minimum) * Double(index) / 5
                    let upper = minimum + (maximum - minimum) * Double(index + 1) / 5
                    let bound = index == 4 ? "n >= \(lower) AND n <= \(upper)" : "n >= \(lower) AND n < \(upper)"
                    let count = try db.query("WITH vals AS (\(values)) SELECT count(*) FROM vals WHERE isfinite(n) AND \(bound)")[0][0]
                    bins.append(count.flatMap(Int.init) ?? 0)
                }
            }
            distribution = NumericDistribution(firstQuartile: q1, median: median, thirdQuartile: q3, bins: bins)
        } else {
            distribution = nil
        }
        var ruleResults: [RuleResult] = []
        for rule in rules {
            try cancellation.check()
            let violations: Int
            switch rule.kind {
            case .required:
                violations = Int(try db.query("WITH vals AS (\(values)) SELECT count(*) FROM vals WHERE v IS NULL OR v = '' OR (v <> '' AND cleaned = '')")[0][0]!)!
            case .unique:
                violations = Int(try db.query("WITH vals AS (\(values)) SELECT coalesce(sum(c - 1), 0) FROM (SELECT count(*) AS c FROM vals WHERE cleaned <> '' GROUP BY v HAVING count(*) > 1)")[0][0]!)!
            case .numberRange:
                var conditions = ["n IS NULL", "NOT isfinite(n)"]
                if let minimum = rule.minimum { conditions.append("n < \(minimum)") }
                if let maximum = rule.maximum { conditions.append("n > \(maximum)") }
                violations = Int(try db.query("WITH vals AS (\(values)) SELECT count(*) FROM vals WHERE cleaned <> '' AND (\(conditions.joined(separator: " OR ")))")[0][0]!)!
            case .matchesPattern:
                if rule.pattern.isEmpty {
                    violations = 0
                } else {
                    violations = Int(try db.query("WITH vals AS (\(values)) SELECT count(*) FROM vals WHERE cleaned <> '' AND NOT regexp_full_match(cleaned, \(literal(rule.pattern)))")[0][0]!)!
                }
            }
            ruleResults.append(RuleResult(ruleID: rule.id, ruleName: rule.kind.displayName, violations: violations))
        }
        return ColumnDetail(columnName: columnName, filter: filter, matchingRows: matchingRows, rows: rows,
                            frequentValues: frequentValues, textPatterns: textPatterns,
                            numericDistribution: distribution, ruleResults: ruleResults)
    }
}
