import Foundation
import MapKit
import SwiftUI
import UIKit

/// One match while you type a title in the Library: fills in the details when you tap it.
struct LookupResult: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var creator: String      // author, network or neighborhood
    var genre: String        // one of the app's genres when we can tell, else ""
    var year: String         // "2021", or "" for restaurants
    var coverURL: URL?

    // Recipes only.
    var ingredients: [String] = []
    var steps: [String] = []
    var link: String = ""
    var minutes: Int = 0
    var notes: String = ""   // e.g. what a TikTok cook wrote besides the recipe
}

/// Looks up books, shows, restaurants and recipes by name, using free services that need no account:
/// Open Library for books, TVmaze for TV shows, Apple Maps for restaurants and TheMealDB for recipes.
enum LibraryLookup {
    static func search(_ query: String, kind: LibraryKind) async throws -> [LookupResult] {
        switch kind {
        case .book: try await books(query)
        case .show: try await shows(query)
        case .restaurant: try await restaurants(query)
        case .recipe: try await recipes(query)
        }
    }

    // MARK: Recipes (TheMealDB)

    private struct MealResponse: Decodable {
        var meals: [[String: String?]]?
    }

    private static func recipes(_ query: String) async throws -> [LookupResult] {
        var url = URLComponents(string: "https://www.themealdb.com/api/json/v1/1/search.php")!
        url.queryItems = [.init(name: "s", value: query)]
        let response: MealResponse = try await fetch(url.url!)
        return (response.meals ?? []).prefix(6).map { meal in
            func field(_ key: String) -> String {
                ((meal[key] ?? nil) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // TheMealDB lists up to 20 ingredients, each with its own amount.
            let ingredients: [String] = (1...20).compactMap { index in
                let name = field("strIngredient\(index)")
                guard !name.isEmpty else { return nil }
                let amount = field("strMeasure\(index)")
                return amount.isEmpty ? name : "\(amount) \(name)"
            }
            let source = field("strSource")
            // "From": the site the recipe came from (bbcgoodfood.com), or TheMealDB itself.
            let site = URL(string: source)?.host?
                .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            return LookupResult(
                title: field("strMeal"),
                creator: site ?? "TheMealDB",
                genre: course(field("strCategory")),
                year: "",
                coverURL: URL(string: field("strMealThumb")),
                ingredients: ingredients,
                steps: RecipeImporter.splitSteps(field("strInstructions")),
                link: source
            )
        }
    }

    /// TheMealDB's categories ("Beef", "Dessert"…) mapped to the app's courses.
    private static func course(_ category: String) -> String {
        switch category {
        case "Breakfast": "Breakfast"
        case "Dessert": "Dessert"
        case "Side": "Side"
        case "Starter": "Snack"
        case "": ""
        default: "Dinner"
        }
    }

    // MARK: Books (Open Library)

    private struct BookResponse: Decodable {
        struct Doc: Decodable {
            var title: String
            var author_name: [String]?
            var cover_i: Int?
            var first_publish_year: Int?
            var subject: [String]?
        }
        var docs: [Doc]
    }

    private static func books(_ query: String) async throws -> [LookupResult] {
        var url = URLComponents(string: "https://openlibrary.org/search.json")!
        url.queryItems = [
            .init(name: "q", value: query),
            .init(name: "limit", value: "6"),
            .init(name: "fields", value: "title,author_name,cover_i,first_publish_year,subject"),
        ]
        let response: BookResponse = try await fetch(url.url!)
        return response.docs.map { doc in
            LookupResult(
                title: doc.title,
                creator: doc.author_name?.first ?? "",
                genre: bookGenre(doc.subject ?? []),
                year: doc.first_publish_year.map(String.init) ?? "",
                coverURL: doc.cover_i.map { URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg")! }
            )
        }
    }

    /// Open Library lists lots of loose "subjects"; pick the closest of the app's genres.
    /// More specific genres are checked first, so a fantasy novel isn't just "Fiction".
    private static func bookGenre(_ subjects: [String]) -> String {
        let text = subjects.joined(separator: "|").lowercased()
        let rules: [(String, [String])] = [
            ("Sci-fi & fantasy", ["science fiction", "fantasy"]),
            ("Mystery & thriller", ["mystery", "detective", "thriller", "suspense", "crime"]),
            ("Romance", ["romance", "love stories"]),
            ("Historical fiction", ["historical fiction"]),
            ("Memoir & biography", ["biography", "memoir", "autobiography"]),
            ("Self-help", ["self-help", "self-improvement", "personal growth"]),
            ("Poetry", ["poetry", "poems"]),
            ("Literary fiction", ["literary fiction"]),
            ("Fiction", ["fiction"]),
        ]
        return rules.first { _, words in words.contains { text.contains($0) } }?.0 ?? ""
    }

    // MARK: TV shows (TVmaze)

    private struct ShowResponse: Decodable {
        struct Show: Decodable {
            struct Channel: Decodable { var name: String }
            struct Images: Decodable { var medium: String? }
            var name: String
            var type: String?
            var genres: [String]?
            var premiered: String?
            var network: Channel?
            var webChannel: Channel?
            var image: Images?
        }
        var show: Show
    }

    private static func shows(_ query: String) async throws -> [LookupResult] {
        var url = URLComponents(string: "https://api.tvmaze.com/search/shows")!
        url.queryItems = [.init(name: "q", value: query)]
        let response: [ShowResponse] = try await fetch(url.url!)
        return response.prefix(6).map { item in
            let show = item.show
            return LookupResult(
                title: show.name,
                // Streaming shows list a "web channel" (Netflix); TV shows list a network (NBC).
                creator: show.webChannel?.name ?? show.network?.name ?? "",
                genre: showGenre(type: show.type ?? "", genres: show.genres ?? []),
                year: String((show.premiered ?? "").prefix(4)),
                coverURL: show.image?.medium.flatMap(URL.init(string:))
            )
        }
    }

    private static func showGenre(type: String, genres: [String]) -> String {
        // TVmaze puts these in "type" rather than genres.
        if ["Animation", "Reality", "Documentary"].contains(type) { return type }
        let rules: [(String, [String])] = [
            ("Sci-fi & fantasy", ["Science-Fiction", "Fantasy", "Supernatural"]),
            ("Crime", ["Crime", "Legal"]),
            ("Thriller", ["Thriller", "Espionage", "Mystery"]),
            ("Horror", ["Horror"]),
            ("Romance", ["Romance"]),
            ("Comedy", ["Comedy"]),
            ("Drama", ["Drama"]),
        ]
        return rules.first { _, words in words.contains { genres.contains($0) } }?.0 ?? ""
    }

    // MARK: Restaurants (Apple Maps)

    private static func restaurants(_ query: String) async throws -> [LookupResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .distillery, .nightlife, .foodMarket,
        ])
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(6).map { place in
            let name = place.name ?? query
            return LookupResult(
                title: name,
                creator: place.addressRepresentations?.cityName ?? place.address?.shortAddress ?? "",
                genre: cuisine(name: name, category: place.pointOfInterestCategory),
                year: "",
                coverURL: nil
            )
        }
    }

    /// Apple Maps only says "restaurant", so guess the cuisine from the kind of place and its name.
    private static func cuisine(name: String, category: MKPointOfInterestCategory?) -> String {
        if [.cafe, .bakery].contains(category) { return "Café & bakery" }
        if [.brewery, .winery, .distillery, .nightlife].contains(category) { return "Bar" }
        let text = name.lowercased()
        let rules: [(String, [String])] = [
            ("Japanese", ["sushi", "ramen", "izakaya", "japanese", "udon", "teriyaki"]),
            ("Italian", ["pizza", "pizzeria", "trattoria", "osteria", "italian", "pasta"]),
            ("Mexican", ["taco", "taqueria", "cantina", "mexican", "burrito"]),
            ("Thai", ["thai"]),
            ("Vietnamese", ["pho", "banh mi", "vietnamese"]),
            ("Chinese", ["dumpling", "szechuan", "sichuan", "dim sum", "chinese", "noodle house"]),
            ("Korean", ["korean", "bbq", "bibimbap"]),
            ("Indian", ["indian", "curry", "tandoor", "masala"]),
            ("Mediterranean", ["mediterranean", "greek", "falafel", "kebab", "olive"]),
            ("French", ["bistro", "brasserie", "french", "café de"]),
            ("Brunch", ["brunch", "pancake", "breakfast"]),
            ("Café & bakery", ["coffee", "café", "cafe", "bakery", "patisserie"]),
            ("Bar", ["bar", "pub", "tavern", "brewing"]),
            ("American", ["burger", "grill", "diner", "steakhouse", "bbq", "smokehouse"]),
        ]
        return rules.first { _, words in words.contains { text.contains($0) } }?.0 ?? ""
    }

    // MARK: Networking

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    static func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: Covers

/// Keeps downloaded covers in memory so they don't reload every time you scroll.
@MainActor
private final class CoverCache {
    static let shared = CoverCache()
    private let images = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? { images.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        // URLSession also keeps a copy on disk, so covers survive restarting the app.
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// A book cover, show poster or recipe photo, or a tile with an icon when there isn't one
/// (always, for restaurants).
struct CoverImage: View {
    let url: URL?
    let kind: LibraryKind
    var width: CGFloat = 42

    @State private var image: UIImage?

    /// Covers are taller than wide; restaurant tiles and recipe photos are square.
    private var height: CGFloat { kind == .restaurant || kind == .recipe ? width : width * 1.45 }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.sage
                Image(systemName: kind.emptyIcon)
                    .font(.system(size: width * 0.4))
                    .foregroundStyle(Theme.forest)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: width * 0.16, style: .continuous).stroke(Theme.hairline))
        .task(id: url) {
            guard let url else { image = nil; return }
            image = CoverCache.shared.image(for: url)
            if image == nil { image = await CoverCache.shared.load(url) }
        }
    }
}
