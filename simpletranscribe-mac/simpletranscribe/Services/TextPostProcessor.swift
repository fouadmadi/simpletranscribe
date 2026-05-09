import Foundation

// MARK: - Config

struct PostProcessorConfig: Codable {
    var capitaliseSentences: Bool = true
    var removeFillersEnabled: Bool = false
    var numberFormattingEnabled: Bool = false
    var customRules: [CustomRule] = []

    struct CustomRule: Codable, Identifiable {
        var id: UUID = UUID()
        var find: String
        var replace: String
    }

    static func fromUserDefaults() -> PostProcessorConfig {
        if let data = UserDefaults.standard.data(forKey: "postProcessorConfig"),
           let config = try? JSONDecoder().decode(PostProcessorConfig.self, from: data) {
            return config
        }
        return PostProcessorConfig()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "postProcessorConfig")
        }
    }
}

// MARK: - Processor

enum TextPostProcessor {
    static let fillerWords: Set<String> = [
        "um", "uh", "er", "ah", "like", "you know", "i mean",
        "sort of", "kind of", "basically", "literally", "right"
    ]

    // Compiled regexes (cached)
    private static let sentenceCapRegex = try? NSRegularExpression(
        pattern: #"(?<=[.!?])\s+([a-z])"#, options: [])
    private static let standaloneIRegex = try? NSRegularExpression(
        pattern: #"\bi\b"#, options: [])

    static func process(_ text: String, config: PostProcessorConfig) -> String {
        var result = text
        if config.capitaliseSentences   { result = capitaliseSentences(result) }
        if config.removeFillersEnabled  { result = removeFillers(result) }
        if config.numberFormattingEnabled { result = formatNumbers(result) }
        for rule in config.customRules where !rule.find.isEmpty {
            result = result.replacingOccurrences(
                of: #"\b"# + NSRegularExpression.escapedPattern(for: rule.find) + #"\b"#,
                with: rule.replace,
                options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    // MARK: - Transforms

    static func capitaliseSentences(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text.prefix(1).uppercased() + text.dropFirst()

        // Capitalise letter after sentence-ending punctuation + whitespace
        if let regex = sentenceCapRegex {
            let range = NSRange(result.startIndex..., in: result)
            var replacements: [(NSRange, String)] = []
            regex.enumerateMatches(in: result, range: range) { match, _, _ in
                guard let m = match else { return }
                let matchStr = (result as NSString).substring(with: m.range)
                replacements.append((m.range, matchStr.uppercased()))
            }
            var nsResult = result as NSString
            for (range, replacement) in replacements.reversed() {
                nsResult = nsResult.replacingCharacters(in: range, with: replacement) as NSString
            }
            result = nsResult as String
        }

        // Capitalise standalone "i" → "I"
        if let regex = standaloneIRegex {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "I")
        }

        return result
    }

    static func removeFillers(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        return words.filter { !fillerWords.contains($0.lowercased()) }.joined(separator: " ")
    }

    static func formatNumbers(_ text: String) -> String {
        let numberMap: [(String, String)] = [
            ("one thousand", "1000"), ("two thousand", "2000"),
            ("one hundred", "100"), ("two hundred", "200"), ("three hundred", "300"),
            ("four hundred", "400"), ("five hundred", "500"), ("six hundred", "600"),
            ("seven hundred", "700"), ("eight hundred", "800"), ("nine hundred", "900"),
            ("ninety", "90"), ("eighty", "80"), ("seventy", "70"), ("sixty", "60"),
            ("fifty", "50"), ("forty", "40"), ("thirty", "30"), ("twenty", "20"),
            ("nineteen", "19"), ("eighteen", "18"), ("seventeen", "17"), ("sixteen", "16"),
            ("fifteen", "15"), ("fourteen", "14"), ("thirteen", "13"), ("twelve", "12"),
            ("eleven", "11"), ("ten", "10"), ("nine", "9"), ("eight", "8"),
            ("seven", "7"), ("six", "6"), ("five", "5"), ("four", "4"),
            ("three", "3"), ("two", "2"), ("one", "1"), ("zero", "0"),
        ]
        var result = text
        for (word, digit) in numberMap {
            result = result.replacingOccurrences(
                of: #"\b"# + word + #"\b"#,
                with: digit,
                options: [.regularExpression, .caseInsensitive])
        }
        return result
    }
}
