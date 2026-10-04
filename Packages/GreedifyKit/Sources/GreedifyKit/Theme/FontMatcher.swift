import Foundation

/// Picks the installed font family for a skin's `pledit.txt` font name (theme images spec §3).
public enum FontMatcher {
    /// Windows fonts from the Winamp era with a Mac look-alike; nil means "use the system font".
    static let windowsEquivalents: [String: String?] = [
        "ms sans serif": "Geneva", "small fonts": "Monaco", "terminal": "Monaco", "system": nil,
    ]

    public static func bestFamily(for wanted: String, among installed: [String]) -> String? {
        let name = wanted.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if let exact = installed.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return exact }

        let words = name.lowercased().split(separator: " ")
        let prefixes = installed.filter { family in
            let familyWords = family.lowercased().split(separator: " ")
            return !familyWords.isEmpty && familyWords.count < words.count && Array(words.prefix(familyWords.count)) == familyWords
        }
        if let longest = prefixes.max(by: { $0.split(separator: " ").count < $1.split(separator: " ").count }) { return longest }

        if let mapped = windowsEquivalents[name.lowercased()] {
            return mapped.flatMap { target in installed.first { $0.caseInsensitiveCompare(target) == .orderedSame } }
        }
        return nil
    }
}
