import Foundation

/// Reads a recipe from a web page you paste in.
///
/// Most recipe sites (NYT Cooking, Bon Appétit, AllRecipes, food blogs…) include the recipe
/// in a standard format meant for search engines (schema.org "Recipe", inside a
/// `<script type="application/ld+json">` tag). We read that, so it works on most sites
/// without knowing anything about them.
enum RecipeImporter {
    enum Failure: LocalizedError {
        case notALink, noRecipe
        var errorDescription: String? {
            switch self {
            case .notALink: "That doesn't look like a web link."
            case .noRecipe: "Couldn't find a recipe on that page. You can still fill it in yourself."
            }
        }
    }

    static func recipe(from text: String) async throws -> LookupResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http"),
              url.host != nil else { throw Failure.notALink }

        var request = URLRequest(url: url, timeoutInterval: 15)
        // Some sites turn away requests that don't look like a browser.
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
                         + "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let html = String(decoding: data, as: UTF8.self)

        // Short links (vm.tiktok.com/…) land on the video page, so check where we ended up.
        if isTikTok(url) || response.url.map(isTikTok) == true {
            return try await tikTok(html: html, link: trimmed)
        }

        guard var result = parse(html: html) else { throw Failure.noRecipe }
        result.link = trimmed
        // "From" is the site ("Serious Eats"), falling back to the author, then the web address.
        result.creator = siteName(html: html) ?? (result.creator.isEmpty ? prettyHost(url) : result.creator)
        return result
    }

    // MARK: Reading the page

    /// Finds the schema.org Recipe in the page's JSON-LD blocks.
    static func parse(html: String) -> LookupResult? {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let body = Range(match.range(at: 1), in: html),
                  let data = String(html[body]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let recipe = findRecipe(in: json) else { continue }
            return result(from: recipe)
        }
        return nil
    }

    /// The Recipe can be the whole block, inside a list, or inside "@graph".
    private static func findRecipe(in json: Any) -> [String: Any]? {
        if let list = json as? [Any] {
            for item in list { if let recipe = findRecipe(in: item) { return recipe } }
            return nil
        }
        guard let object = json as? [String: Any] else { return nil }
        if isRecipe(object["@type"]) { return object }
        if let graph = object["@graph"] { return findRecipe(in: graph) }
        if let main = object["mainEntity"] { return findRecipe(in: main) }
        return nil
    }

    private static func isRecipe(_ type: Any?) -> Bool {
        if let type = type as? String { return type == "Recipe" }
        if let types = type as? [String] { return types.contains("Recipe") }
        return false
    }

    private static func result(from recipe: [String: Any]) -> LookupResult {
        let ingredients = (recipe["recipeIngredient"] as? [Any] ?? recipe["ingredients"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { clean($0) }
            // Some sites (Budget Bytes) add a cost to each ingredient: "2 Tbsp butter ($0.28)".
            .map { $0.replacingOccurrences(of: #"\s*\(\s*\$[\d.,]+\s*\)\s*$"#, with: "",
                                           options: .regularExpression) }
            .filter { !$0.isEmpty }

        return LookupResult(
            title: clean(recipe["name"] as? String ?? ""),
            creator: name(of: recipe["author"]) ?? name(of: recipe["publisher"]) ?? "",
            genre: course(recipe["recipeCategory"]),
            year: "",
            coverURL: image(recipe["image"]),
            ingredients: ingredients,
            steps: steps(recipe["recipeInstructions"]),
            minutes: minutes(recipe["totalTime"] as? String)
                ?? ((minutes(recipe["prepTime"] as? String) ?? 0) + (minutes(recipe["cookTime"] as? String) ?? 0))
        )
    }

    // MARK: Fields

    /// Instructions come as one block of text, a list of strings, a list of steps,
    /// or sections that each have their own steps.
    private static func steps(_ value: Any?) -> [String] {
        if let text = value as? String { return splitSteps(clean(text)) }
        guard let list = value as? [Any] else { return [] }
        return list.flatMap { item -> [String] in
            if let text = item as? String { return [clean(text)] }
            guard let object = item as? [String: Any] else { return [] }
            if let inner = object["itemListElement"] { return steps(inner) }   // a section
            return [clean(object["text"] as? String ?? object["name"] as? String ?? "")]
        }
        .filter { !$0.isEmpty }
    }

    /// Splits one block of instructions into steps: by line, or by sentence for one long paragraph.
    static func splitSteps(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { line in
                // Drop "1." / "Step 1" style numbering; the app numbers steps itself.
                line.replacingOccurrences(of: #"^(step\s*)?\d+[.):]?\s+"#, with: "",
                                          options: [.regularExpression, .caseInsensitive])
            }
            .filter { $0.count > 2 }
        return lines
    }

    private static func image(_ value: Any?) -> URL? {
        if let text = value as? String { return URL(string: text) }
        if let list = value as? [Any] {
            for item in list { if let url = image(item) { return url } }
            return nil
        }
        if let object = value as? [String: Any] { return image(object["url"]) }
        return nil
    }

    private static func name(of value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return clean(text) }
        if let list = value as? [Any] {
            for item in list { if let found = name(of: item) { return found } }
            return nil
        }
        if let object = value as? [String: Any], let text = object["name"] as? String, !text.isEmpty {
            return clean(text)
        }
        return nil
    }

    /// The site's category ("Main Course", "Desserts"…) mapped to the app's courses.
    static func course(_ value: Any?) -> String {
        let text = ((value as? String) ?? (value as? [String])?.joined(separator: " ") ?? "").lowercased()
        let rules: [(String, [String])] = [
            ("Breakfast", ["breakfast", "brunch"]),
            ("Dessert", ["dessert", "sweet"]),
            ("Baking", ["baking", "bread", "cake", "cookie"]),
            ("Soup", ["soup", "stew"]),
            ("Salad", ["salad"]),
            ("Side", ["side"]),
            ("Snack", ["snack", "appetizer", "starter"]),
            ("Drinks", ["drink", "cocktail", "beverage", "smoothie"]),
            ("Lunch", ["lunch"]),
            ("Dinner", ["dinner", "main", "entree", "entrée"]),
        ]
        return rules.first { _, words in words.contains { text.contains($0) } }?.0 ?? ""
    }

    /// ISO 8601 durations like "PT1H30M" → 90.
    static func minutes(_ text: String?) -> Int? {
        guard let text, text.uppercased().hasPrefix("P") else { return nil }
        var total = 0, number = ""
        var inTime = false
        for char in text.uppercased().dropFirst() {
            if char.isNumber || char == "." { number.append(char); continue }
            let value = Double(number) ?? 0
            number = ""
            switch char {
            case "T": inTime = true
            case "D": total += Int(value * 24 * 60)
            case "H": total += Int(value * 60)
            case "M" where inTime: total += Int(value)
            default: break
            }
        }
        return total > 0 ? total : nil
    }

    // MARK: Helpers

    /// Removes HTML tags and turns "&amp;" etc. back into characters.
    private static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&apos;": "'",
                        "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#8217;": "’", "&#8211;": "–",
                        "&#8212;": "—", "&#8220;": "“", "&#8221;": "”", "&frac12;": "½", "&frac14;": "¼"]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The site's own name, from `<meta property="og:site_name" content="…">`.
    private static func siteName(html: String) -> String? {
        let pattern = #"<meta[^>]+property\s*=\s*["']og:site_name["'][^>]+content\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return clean(String(html[range]))
    }

    /// "www.seriouseats.com" → "seriouseats.com"
    private static func prettyHost(_ url: URL) -> String {
        (url.host ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
}
