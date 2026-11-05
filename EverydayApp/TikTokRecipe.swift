import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Recipes from TikTok videos.
///
/// TikTok pages don't include a recipe the way recipe sites do, but they do include the video's
/// caption, who posted it and a cover image. Many cooks write the ingredients (and sometimes the
/// steps) in the caption, so we pick those out. When the caption links to a recipe on a website,
/// we read that page instead, since it has the full recipe.
///
/// TikTok can change its pages at any time. If it does, this finds nothing and you get the usual
/// "couldn't find a recipe" message; the link still saves.
extension RecipeImporter {
    static func isTikTok(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
    }

    /// The recipe in a TikTok page's caption.
    static func tikTok(html: String, link: String) async throws -> LookupResult {
        guard let video = tikTokVideo(html: html) else { throw Failure.noRecipe }
        let caption = TikTokCaption(video.caption, mentions: video.mentions)

        // "Grab the recipe here: https://…" — the website has the whole recipe.
        if let page = caption.recipeLink, var result = try? await recipe(from: page) {
            result.link = link
            result.creator = "@" + video.author
            if result.coverURL == nil { result.coverURL = video.cover }
            result.coverURL = await keepableCover(result.coverURL)
            return result
        }

        var result = LookupResult(
            title: dishName(video.suggestions) ?? caption.recipeLink.flatMap(nameFromLink) ?? caption.opening,
            creator: video.author.isEmpty ? "TikTok" : "@" + video.author,
            genre: course(video.hashtags.joined(separator: " ")),
            year: "",
            coverURL: await keepableCover(video.cover),
            ingredients: caption.ingredients,
            steps: caption.steps,
            link: link
        )
        result.notes = caption.notes
        // The website didn't have a recipe we could read, but you'll still want the link.
        if let page = caption.recipeLink {
            result.notes += (result.notes.isEmpty ? "" : "\n\n") + "Full recipe: " + page
        }
        return result
    }

    /// "…/that-viral-pasta-that-almost-broke-the-internet/" → "That Viral Pasta That Almost Broke The Internet"
    static func nameFromLink(_ link: String) -> String? {
        guard let url = URL(string: link) else { return nil }
        let slug = url.pathComponents.last { $0.contains("-") } ?? ""
        let words = slug.replacingOccurrences(of: #"\.\w+$"#, with: "", options: .regularExpression)
            .split(separator: "-").filter { !$0.allSatisfy(\.isNumber) }
        guard words.count >= 2 else { return nil }
        return words.joined(separator: " ").capitalized
    }

    // MARK: Reading the page

    struct TikTokVideo {
        var caption = ""
        var author = ""
        var cover: URL?
        var suggestions: [String] = []
        var hashtags: [String] = []
        var mentions: [(range: NSRange, name: String)] = []
    }

    /// TikTok puts the video's details in a block of JSON in the page.
    static func tikTokVideo(html: String) -> TikTokVideo? {
        let pattern = #"<script[^>]*id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let json = try? JSONSerialization.jsonObject(with: Data(html[range].utf8)) as? [String: Any],
              let scope = json["__DEFAULT_SCOPE__"] as? [String: Any]
        else { return nil }

        // Phones and computers get slightly different pages.
        let detail = (scope["webapp.reflow.video.detail"] ?? scope["webapp.video-detail"]) as? [String: Any]
        guard let item = (detail?["itemInfo"] as? [String: Any])?["itemStruct"] as? [String: Any],
              let caption = item["desc"] as? String
        else { return nil }

        var video = TikTokVideo(caption: caption)
        video.author = (item["author"] as? [String: Any])?["uniqueId"] as? String ?? ""
        let share = detail?["shareMeta"] as? [String: Any]
        let videoInfo = item["video"] as? [String: Any]
        // The video's own cover; the share card has a play button drawn on it.
        let cover = videoInfo?["cover"] as? String ?? share?["cover_url"] as? String ?? ""
        video.cover = URL(string: cover)
        video.suggestions = item["suggestedWords"] as? [String] ?? []

        // Hashtags and @mentions, with where each mention is in the caption.
        for extra in item["textExtra"] as? [[String: Any]] ?? [] {
            if let tag = extra["hashtagName"] as? String, !tag.isEmpty {
                video.hashtags.append(tag)
            } else if let start = extra["start"] as? Int, let end = extra["end"] as? Int, end > start {
                let range = NSRange(location: start, length: end - start)
                if NSMaxRange(range) <= (caption as NSString).length {
                    let text = (caption as NSString).substring(with: range)
                    video.mentions.append((range, String(text.drop { $0 == "@" })))
                }
            }
        }
        return video
    }

    /// TikTok's own guess at what the video is ("Marry Me Chicken Pasta"),
    /// skipping broad ones like "pasta" or "dinner ideas".
    static func dishName(_ suggestions: [String]) -> String? {
        let broad = ["recipe", "idea", "dinner", "lunch", "breakfast", "food", "meal", "cooking", "making", "easy"]
        let pick = suggestions.first { words in
            let lower = words.lowercased()
            return lower.split(separator: " ").count >= 2 && !broad.contains { lower.contains($0) }
        }
        return pick.map { $0.capitalized }
    }

    /// A small copy of the cover photo, kept in the recipe itself. TikTok's image links
    /// stop working after a while, so a plain link would leave the recipe without its photo.
    static func keepableCover(_ url: URL?) async -> URL? {
        #if canImport(UIKit)
        guard let url, url.scheme != "data",
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data), image.size.width > 0, image.size.height > 0
        else { return url }
        let scale = min(1, 360 / min(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = small.jpegData(compressionQuality: 0.7) else { return url }
        return URL(string: "data:image/jpeg;base64," + jpeg.base64EncodedString())
        #else
        return url
        #endif
    }
}

/// Picks a recipe out of a TikTok caption. Captions are written any which way, so this is
/// a best guess: it looks for an "Ingredients:" part and an "Instructions:" part, and splits
/// them into lines by dashes, numbers or line breaks.
struct TikTokCaption {
    private(set) var ingredients: [String] = []
    private(set) var steps: [String] = []
    /// What the cook wrote besides the recipe ("This went viral…").
    private(set) var notes = ""
    /// The first bit of the caption, for a name when TikTok doesn't suggest one.
    private(set) var opening = ""
    /// A link to a recipe on a website, if the caption has one.
    private(set) var recipeLink: String?

    init(_ caption: String, mentions: [(range: NSRange, name: String)] = []) {
        // "@Whole Foods Market" → "Whole Foods Market". From the end, so earlier positions still line up.
        let text = NSMutableString(string: caption)
        for mention in mentions.sorted(by: { $0.range.location > $1.range.location })
        where NSMaxRange(mention.range) <= text.length {
            // Tags at the end ("#pasta @Le Creuset") aren't part of the recipe.
            let before = text.substring(to: mention.range.location)
            let amongTags = before.range(of: #"#[^\s#]+\s*$"#, options: .regularExpression) != nil
            text.replaceCharacters(in: mention.range, with: amongTags ? "" : mention.name)
        }
        var body = text as String

        recipeLink = Self.firstLink(in: body)
        body = Self.replace(#"https?://\S+"#, in: body, with: "")
        body = Self.replace(#"#+[^\s#]*"#, in: body, with: " ")           // hashtags
        body = Self.replace(#"@[\w.]+"#, in: body, with: "")              // leftover mentions
        body = Self.lineBreaks(body)

        let lower = body.lowercased() as NSString
        let all = NSRange(location: 0, length: lower.length)
        let ingredientsHeader = Self.header(#"\bingredients?\b"#, in: lower, range: all)
            ?? Self.header(#"\b(recipe|what you(?:'|’)ll need|you(?:'|’)ll need)\s*:"#, in: lower, range: all)
        let searchSteps = ingredientsHeader.map {
            NSRange(location: $0.end, length: lower.length - $0.end)
        } ?? all
        let stepsHeader = Self.header(#"\b(instructions|directions|method|steps|how to make it|how to)\b"#,
                                      in: lower, range: searchSteps)

        let ns = body as NSString
        func part(_ from: Int, _ to: Int) -> String {
            guard to > from else { return "" }
            return ns.substring(with: NSRange(location: from, length: to - from))
        }
        let firstHeader = ingredientsHeader?.start ?? stepsHeader?.start ?? ns.length
        let intro = part(0, firstHeader)

        if let ingredientsHeader {
            ingredients = Self.ingredientLines(part(ingredientsHeader.end, stepsHeader?.start ?? ns.length))
        }
        if let stepsHeader {
            steps = Self.stepLines(part(stepsHeader.end, ns.length))
        }

        let tidyIntro = Self.tidy(intro)
        notes = ingredients.isEmpty && steps.isEmpty ? Self.tidy(body) : tidyIntro
        opening = Self.firstSentence(tidyIntro.isEmpty ? Self.tidy(body) : tidyIntro)
    }

    // MARK: Finding the parts

    /// Where a header like "Ingredients from Whole Foods:" starts, and where its list begins.
    /// One with a colon wins, so "only 3 ingredients!" earlier on doesn't count as the header.
    private static func header(_ pattern: String, in text: NSString, range: NSRange) -> (start: Int, end: Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var fallback: (start: Int, end: Int)?
        for match in regex.matches(in: text as String, range: range) {
            let end = NSMaxRange(match.range)
            // Skip to a colon close by, so "Ingredients from Whole Foods Market :" is all header.
            let ahead = NSRange(location: end, length: min(45, text.length - end))
            let colon = text.range(of: ":", range: ahead)
            if colon.location != NSNotFound {
                let between = text.substring(with: NSRange(location: end, length: colon.location - end))
                if !between.contains("\n"), !between.contains(where: \.isNumber), !between.contains("-") {
                    return (match.range.location, NSMaxRange(colon))
                }
            }
            if fallback == nil { fallback = (match.range.location, end) }
        }
        return fallback
    }

    // MARK: Splitting into lines

    private static let units = #"(?:tbsp|tsp|tablespoons?|teaspoons?|cups?|g|gr|grams?|kg|oz|ounces?|lbs?|pounds?|ml|l|cloves?|pinch|cans?|sticks?|slices?)"#

    static func ingredientLines(_ text: String) -> [String] {
        var chunks: [String]
        // "-1 yellow onion -garlic -fresh basil" → one per dash.
        if count(#"(?:^|\s)-\s?\S"#, in: text) >= 3 {
            chunks = split(text, on: #"(?:^|\s+)-\s*"#)
        } else {
            chunks = split(text, on: #"\n|[•▪●◦✓✔]"#)
        }
        // "1 tbsp butter 1/2 tbsp chilli powder" → two, when each starts with an amount.
        chunks = chunks.flatMap { splitAmounts($0) }

        return chunks.compactMap { chunk in
            var line = tidy(chunk)
            // Group names: "Meat Sauce:" on its own, or "tomato paste Garlic Yogurt:" at the end.
            line = replace(#"\s*\*+\s*for\s+\S+\s*"#, in: line, with: "", caseInsensitive: true)
            line = replace(#"(?:^|\s+)(?:[A-Z][\w’']*\s?){1,3}:$"#, in: line, with: "")
            line = replace(#"^\*+|\*+$"#, in: line, with: "")
            // "…for a complete meal. Bow tie pasta 200 gram" → the part after the chatter.
            if let last = line.components(separatedBy: ". ").last, line.split(separator: " ").count > 12 {
                line = last
            }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:").union(.whitespaces))
            let filler = ["below", "here", "down below", "list"]
            guard line.count > 1, !filler.contains(line.lowercased()),
                  line.split(separator: " ").count <= 14 else { return nil }
            return line
        }
    }

    static func stepLines(_ text: String) -> [String] {
        let chunks: [String]
        if count(#"(?:^|\s)\d{1,2}[.)]\s"#, in: text) >= 2 {
            chunks = split(text, on: #"(?:^|\s+)\d{1,2}[.)]\s+"#)
        } else if text.contains("\n") {
            chunks = split(text, on: "\n")
        } else {
            chunks = split(text, on: #"(?<=[.!?])\s+"#)
        }
        return chunks.map { tidy($0) }.flatMap { RecipeImporter.splitSteps($0) }
    }

    /// Splits before each amount ("1/2 tbsp …"), but only in a chunk that starts with one,
    /// so "Bow tie pasta 200 gram" stays together.
    private static func splitAmounts(_ chunk: String) -> [String] {
        let trimmed = chunk.trimmingCharacters(in: .whitespaces)
        guard trimmed.first?.isNumber == true else { return [chunk] }
        return split(trimmed, on: #"\s+(?=\d+(?:[/.]\d+)?\s*"# + units + #"\.?\s)"#, caseInsensitive: true)
    }

    // MARK: Text helpers

    /// TikTok turns line breaks into double spaces; emoji often stand in for bullets.
    private static func lineBreaks(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let isEmoji = scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x2000 && !"#*0123456789".unicodeScalars.contains(scalar))
            if isEmoji || scalar.value == 0x200D || (0xFE00...0xFE0F).contains(scalar.value)
                || (0x1F3FB...0x1F3FF).contains(scalar.value) {
                result.append("\n")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        result = replace(#" {2,}"#, in: result, with: "\n")
        return replace(#"\s*\n\s*"#, in: result, with: "\n")
    }

    private static func tidy(_ text: String) -> String {
        replace(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstSentence(_ text: String) -> String {
        let first = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? text
        let words = first.split(separator: " ").prefix(8).joined(separator: " ")
        return words.trimmingCharacters(in: .whitespaces)
    }

    private static func firstLink(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s"”)]+"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let link = String(text[range])
        guard let url = URL(string: link), !RecipeImporter.isTikTok(url) else { return nil }
        return link
    }

    private static func replace(_ pattern: String, in text: String, with replacement: String,
                                caseInsensitive: Bool = false) -> String {
        text.replacingOccurrences(of: pattern, with: replacement,
                                  options: caseInsensitive ? [.regularExpression, .caseInsensitive] : .regularExpression)
    }

    private static func count(_ pattern: String, in text: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?
            .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
    }

    private static func split(_ text: String, on pattern: String, caseInsensitive: Bool = false) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? .caseInsensitive : [])
        else { return [text] }
        var pieces: [String] = []
        var start = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            pieces.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
        }
        pieces.append(String(text[start...]))
        return pieces.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
