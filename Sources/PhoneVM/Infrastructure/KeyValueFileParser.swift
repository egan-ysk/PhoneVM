import Foundation

enum KeyValueFileParser {
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else {
                continue
            }

            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: separatorIndex)
            let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }

            result[key] = value
        }

        return result
    }

    static func parseFile(at url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return [:]
        }
        return parse(text)
    }
}
