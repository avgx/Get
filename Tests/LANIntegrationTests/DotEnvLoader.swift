import Foundation

/// Loads `.env` from the package root (next to `Package.swift`). Process environment **overrides** file values.
enum TestEnvironment {
    private static let dotenv: [String: String] = loadDotEnv()

    private static let merged: [String: String] = {
        var out = dotenv
        for (k, v) in ProcessInfo.processInfo.environment {
            out[k] = v
        }
        return out
    }()

    static func value(for key: String) -> String? {
        merged[key]
    }

    private static func loadDotEnv() -> [String: String] {
        let fromPackage = packageRootURL(from: URL(fileURLWithPath: #filePath)).appendingPathComponent(".env")
        let fromCwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".env")
        let url = [fromPackage, fromCwd].first { FileManager.default.isReadableFile(atPath: $0.path) }
        guard let url,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            return [:]
        }
        var map: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2 {
                let first = value.first!
                let last = value.last!
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            map[key] = value
        }
        return map
    }

    private static func packageRootURL(from fileURL: URL) -> URL {
        var dir = fileURL.deletingLastPathComponent()
        while true {
            let pkg = dir.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: pkg.path) {
                return dir
            }
            guard dir.path != "/" else {
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            }
            dir.deleteLastPathComponent()
        }
    }
}
