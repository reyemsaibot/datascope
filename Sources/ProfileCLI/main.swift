import Foundation
import ProfilingCore

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first, !path.hasPrefix("--") else {
    print("Usage: profile FILE [--delimiter ';'] [--sheet NAME] [--decimal-comma] [--no-header] [--cancel-after SECONDS]")
    exit(2)
}
func argument(_ key: String) -> String? {
    guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }; return args[i + 1]
}
var options = ImportOptions()
options.delimiter = argument("--delimiter") ?? ""
options.sheet = argument("--sheet") ?? ""
options.decimalComma = args.contains("--decimal-comma")
options.header = !args.contains("--no-header")
let cancellation = Cancellation()
if let value = argument("--cancel-after"), let seconds = Double(value) {
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { cancellation.cancel() }
}
do {
    let result = try Profiler.run(url: URL(fileURLWithPath: path), options: options, cancellation: cancellation)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(result), as: UTF8.self))
} catch is CancellationError {
    FileHandle.standardError.write(Data("Analyse abgebrochen.\n".utf8)); exit(130)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
}
