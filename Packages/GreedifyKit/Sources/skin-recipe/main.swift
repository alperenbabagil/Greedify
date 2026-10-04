// Drafts a curated Greedify theme from a classic Winamp skin (curated skins spec §5).
//   swift run --package-path Packages/GreedifyKit skin-recipe <skin.wsz> --name "<Theme Name>" [--out <dir>]
// Writes <slug>.greedifytheme (the recipe to tune) and <slug>.contact.png (the skin's art, sampled areas boxed).
import Foundation
import GreedifyKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
let name = option("--name")
let out = URL(filePath: option("--out") ?? FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
guard let path = args.first else { fail("usage: skin-recipe <skin.wsz> --name \"<Theme Name>\" [--out <dir>]") }
let input = URL(filePath: path)
guard let data = try? Data(contentsOf: input) else { fail("can't read \(path)") }
let themeName = name ?? input.deletingPathExtension().lastPathComponent
let slug = themeName.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")

do {
    let draft = try SkinRecipeMaker.recipe(fromArchive: data, name: themeName, fileName: input.lastPathComponent)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let themeURL = out.appending(path: "\(slug).greedifytheme")
    try draft.theme.encoded().write(to: themeURL)
    print("wrote \(themeURL.path)")
    if let sheet = draft.contactSheet {
        let sheetURL = out.appending(path: "\(slug).contact.png")
        try sheet.write(to: sheetURL)
        print("wrote \(sheetURL.path)")
    }
    print("\nmeasured:")
    for note in draft.notes { print("  • \(note)") }
} catch {
    fail("couldn't convert \(path): \(error.localizedDescription)")
}
