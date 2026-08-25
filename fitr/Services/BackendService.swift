//
//  BackendService.swift
//  fitr
//
//  UNCOMPILED / UNVERIFIED. Written on Linux with no Swift toolchain, no
//  Xcode and no macOS available. It has never been type-checked or built.
//  Expect to fix small compile errors on first build. Nothing in the existing
//  app calls into this file yet, so adding it cannot change current behaviour.
//  It is purely additive until you wire it up.
//
//  Client for the fitr Flask backend (see backend/README.md for the API).
//
//  Why this exists: the app calls Gemini directly through FirebaseVertexAI
//  using model ids `gemini-3.7-flash` and `gemini-3.1-pro`. Pinning ids in
//  Swift means a new build every time Google retires one, which is how the
//  previous `gemini-2.0-flash` and `gemini-1.5-pro` ids went dead.
//  `FirebaseVertexAI` itself was removed from firebase-ios-sdk in 12.0.0
//  (replaced by `FirebaseAI`, since renamed to the `FirebaseAILogic` module).
//  Routing these calls through the backend means the model id, the API keys
//  and the SDK version all live server-side, where they can be changed
//  without shipping a new build.
//

import Foundation
import UIKit
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

// MARK: - Errors

enum BackendError: LocalizedError {
    case notConfigured
    case invalidURL
    case notAuthenticated
    case imageEncodingFailed
    case transport(Error)
    case http(status: Int, code: String, message: String)
    case decoding(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The fitr backend is not configured. Set FITR_BACKEND_URL."
        case .invalidURL:
            return "The backend URL is not valid."
        case .notAuthenticated:
            return "You need to be signed in to do that."
        case .imageEncodingFailed:
            return "Could not encode the image."
        case .transport(let error):
            return error.localizedDescription
        case .http(let status, _, let message):
            return message.isEmpty ? "Server error (\(status))." : message
        case .decoding:
            return "The server sent a response the app could not read."
        case .emptyResponse:
            return "The server sent an empty response."
        }
    }
}

// MARK: - Wire types

/// Mirrors the backend's clothing item JSON. Deliberately separate from the
/// Firestore-backed `ClothingItem` so that changing one cannot break the
/// other's decoding; use `asClothingItem()` to convert.
struct BackendClothingItem: Codable, Identifiable {
    let id: String
    let userId: String
    let name: String
    let type: String
    let color: String
    let imageURL: String
    let weatherTags: [String]
    let styleTags: [String]
    let dirty: Bool
    let contentHash: String?
    let hasEmbedding: Bool
    let createdAt: String?
    let similarity: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case color
        case imageURL = "image_url"
        case weatherTags = "weather_tags"
        case styleTags = "style_tags"
        case dirty
        case contentHash = "content_hash"
        case hasEmbedding = "has_embedding"
        case createdAt = "created_at"
        case similarity
    }

    /// Converts into the app's existing model. Unknown enum values fall back
    /// rather than throwing, so a backend that learns a new tag cannot break
    /// an older client.
    func asClothingItem() -> ClothingItem {
        ClothingItem(
            id: id,
            userId: userId,
            imageURL: imageURL,
            type: ClothingType(rawValue: type) ?? .other,
            color: color,
            name: name,
            createdAt: BackendService.parseDate(createdAt) ?? Date(),
            weatherTags: weatherTags.compactMap { WeatherTag(rawValue: $0) },
            styleTags: styleTags.compactMap { StyleTag(rawValue: $0) },
            dirty: dirty
        )
    }
}

struct BackendWeather: Codable {
    let temperature: Double
    let condition: String
    let description: String?
    let humidity: Int
    let windSpeed: Double
    let location: String
    let units: String?

    enum CodingKeys: String, CodingKey {
        case temperature, condition, description, humidity, location, units
        case windSpeed = "wind_speed"
    }

    func asWeather() -> Weather {
        Weather(
            temperature: temperature,
            condition: WeatherCondition(rawValue: condition) ?? .cloudy,
            humidity: humidity,
            windSpeed: windSpeed,
            location: location,
            date: Date()
        )
    }
}

struct BackendClassification: Codable {
    let type: String
    let typeConfidence: Double
    let color: String
    let colorConfidence: Double
    let styleTags: [String]
    let weatherTags: [String]
    let cacheTier: String?

    enum CodingKeys: String, CodingKey {
        case type, color
        case typeConfidence = "type_confidence"
        case colorConfidence = "color_confidence"
        case styleTags = "style_tags"
        case weatherTags = "weather_tags"
        case cacheTier = "cache_tier"
    }
}

struct BackendOutfitOption: Codable, Identifiable {
    let rank: Int
    let itemIds: [String]
    let description: String
    let items: [BackendClothingItem]?

    var id: Int { rank }

    enum CodingKeys: String, CodingKey {
        case rank, description, items
        case itemIds = "item_ids"
    }
}

struct BackendRecommendation: Codable, Identifiable {
    let id: String
    let userId: String
    let vibe: String
    let weather: BackendWeather
    let options: [BackendOutfitOption]
    /// "gemini", "heuristic", "gemini_empty_fallback" or "none". Worth
    /// surfacing in debug UI: it says whether the LLM actually ran.
    let generator: String
    let model: String?

    enum CodingKeys: String, CodingKey {
        case id, vibe, weather, options, generator, model
        case userId = "user_id"
    }

    /// The top-ranked option as the app's existing `Outfit` model.
    func asOutfit() -> Outfit? {
        guard let best = options.sorted(by: { $0.rank < $1.rank }).first else { return nil }
        let items = (best.items ?? []).map { $0.asClothingItem() }
        guard !items.isEmpty else { return nil }
        return Outfit(
            id: id,
            userId: userId,
            items: items,
            weather: weather.asWeather(),
            createdAt: Date(),
            description: best.description,
            vibe: vibe
        )
    }
}

struct BackendSearchResponse: Codable {
    let query: String
    let results: [BackendClothingItem]
}

private struct BackendItemEnvelope: Codable {
    let item: BackendClothingItem
}

private struct BackendItemsEnvelope: Codable {
    let items: [BackendClothingItem]
    let count: Int
}

private struct BackendWeatherEnvelope: Codable {
    let weather: BackendWeather
    let cached: Bool
}

private struct BackendErrorEnvelope: Codable {
    struct Payload: Codable {
        let code: String
        let message: String
    }
    let error: Payload
}

// MARK: - Service

final class BackendService {

    static let shared = BackendService()

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = AppConfig.backendTimeout
            configuration.waitsForConnectivity = true
            self.session = URLSession(configuration: configuration)
        }
    }

    /// False when FITR_BACKEND_URL is unset. Callers should fall back to the
    /// existing Firebase/Gemini path rather than showing an error.
    var isConfigured: Bool { AppConfig.backendBaseURL != nil }

    // MARK: Dates

    /// The backend emits `datetime.isoformat()`, which includes fractional
    /// seconds. `ISO8601DateFormatter` rejects those unless
    /// `.withFractionalSeconds` is set, so try both spellings.
    static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    // MARK: Requests

    private func makeRequest(
        path: String,
        method: String,
        query: [URLQueryItem] = []
    ) async throws -> URLRequest {
        guard let base = AppConfig.backendBaseURL else { throw BackendError.notConfigured }
        guard var components = URLComponents(
            url: base.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw BackendError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BackendError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await attachIdentity(to: &request)
        return request
    }

    /// Sends a Firebase ID token when one is available (the backend's
    /// `FITR_AUTH_MODE=firebase`), and the raw uid otherwise (`header` mode,
    /// development only).
    private func attachIdentity(to request: inout URLRequest) async throws {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else { throw BackendError.notAuthenticated }
        request.setValue(user.uid, forHTTPHeaderField: "X-User-Id")
        if let token = try? await user.getIDToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #endif
    }

    private func perform<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let envelope = try? decoder.decode(BackendErrorEnvelope.self, from: data) {
                throw BackendError.http(
                    status: http.statusCode,
                    code: envelope.error.code,
                    message: envelope.error.message
                )
            }
            throw BackendError.http(status: http.statusCode, code: "http_error", message: "")
        }

        if data.isEmpty { throw BackendError.emptyResponse }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BackendError.decoding(error)
        }
    }

    private func performJSON<T: Decodable>(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        query: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        var request = try await makeRequest(path: path, method: method, query: query)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request, as: T.self)
    }

    /// Builds a multipart/form-data body. `UIImage` is JPEG-encoded at the
    /// same 0.7 quality `FirebaseService.uploadClothingImage` uses, so the
    /// bytes, and therefore the backend's content-addressed cache key, match
    /// what gets uploaded to Storage.
    private func multipartRequest(
        path: String,
        image: UIImage,
        fields: [String: String]
    ) async throws -> URLRequest {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw BackendError.imageEncodingFailed
        }
        var request = try await makeRequest(path: path, method: "POST")
        let boundary = "fitr-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) { body.append(data) }
        }
        for (key, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"item.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")

        request.httpBody = body
        return request
    }

    // MARK: - Wardrobe

    func createItem(
        image: UIImage?,
        name: String,
        type: ClothingType,
        color: String,
        weatherTags: [WeatherTag],
        styleTags: [StyleTag],
        imageURL: String = "",
        id: String? = nil
    ) async throws -> BackendClothingItem {
        var fields: [String: String] = [
            "name": name,
            "type": type.rawValue,
            "color": color,
            "image_url": imageURL,
            "weather_tags": weatherTags.map { $0.rawValue }.joined(separator: ","),
            "style_tags": styleTags.map { $0.rawValue }.joined(separator: ",")
        ]
        if let id { fields["id"] = id }

        if let image {
            let request = try await multipartRequest(
                path: "api/v1/wardrobe/items", image: image, fields: fields
            )
            return try await perform(request, as: BackendItemEnvelope.self).item
        }
        let envelope: BackendItemEnvelope = try await performJSON(
            path: "api/v1/wardrobe/items",
            method: "POST",
            body: fields,
            as: BackendItemEnvelope.self
        )
        return envelope.item
    }

    func fetchItems(dirty: Bool? = nil) async throws -> [BackendClothingItem] {
        var query: [URLQueryItem] = []
        if let dirty { query.append(URLQueryItem(name: "dirty", value: dirty ? "true" : "false")) }
        let envelope: BackendItemsEnvelope = try await performJSON(
            path: "api/v1/wardrobe/items", method: "GET", query: query,
            as: BackendItemsEnvelope.self
        )
        return envelope.items
    }

    func setDirty(itemId: String, dirty: Bool) async throws -> BackendClothingItem {
        let envelope: BackendItemEnvelope = try await performJSON(
            path: "api/v1/wardrobe/items/\(itemId)",
            method: "PATCH",
            body: ["dirty": dirty],
            as: BackendItemEnvelope.self
        )
        return envelope.item
    }

    func deleteItem(itemId: String) async throws {
        struct Deleted: Codable { let deleted: String }
        _ = try await performJSON(
            path: "api/v1/wardrobe/items/\(itemId)", method: "DELETE", as: Deleted.self
        )
    }

    func washItems(itemIds: [String]) async throws -> [String] {
        struct Washed: Codable { let washed: [String]; let count: Int }
        return try await performJSON(
            path: "api/v1/wardrobe/wash",
            method: "POST",
            body: ["item_ids": itemIds],
            as: Washed.self
        ).washed
    }

    /// Natural-language wardrobe search, ranked by CLIP similarity.
    func search(query: String, limit: Int = 10) async throws -> [BackendClothingItem] {
        try await performJSON(
            path: "api/v1/wardrobe/search",
            method: "POST",
            body: ["query": query, "k": limit],
            as: BackendSearchResponse.self
        ).results
    }

    func similarItems(to itemId: String, limit: Int = 5) async throws -> [BackendClothingItem] {
        struct Similar: Codable { let results: [BackendClothingItem] }
        return try await performJSON(
            path: "api/v1/wardrobe/items/\(itemId)/similar",
            method: "GET",
            query: [URLQueryItem(name: "k", value: String(limit))],
            as: Similar.self
        ).results
    }

    // MARK: - Vision

    /// CLIP zero-shot classification. Replaces the Gemini call in
    /// `ClothingClassifier`, and is served from cache for a repeated image.
    func classify(image: UIImage) async throws -> BackendClassification {
        let request = try await multipartRequest(
            path: "api/v1/vision/classify", image: image, fields: [:]
        )
        return try await perform(request, as: BackendClassification.self)
    }

    // MARK: - Weather

    func weather(latitude: Double, longitude: Double) async throws -> BackendWeather {
        try await performJSON(
            path: "api/v1/weather",
            method: "GET",
            query: [
                URLQueryItem(name: "lat", value: String(latitude)),
                URLQueryItem(name: "lon", value: String(longitude))
            ],
            as: BackendWeatherEnvelope.self
        ).weather
    }

    func weather(city: String) async throws -> BackendWeather {
        try await performJSON(
            path: "api/v1/weather",
            method: "GET",
            query: [URLQueryItem(name: "q", value: city)],
            as: BackendWeatherEnvelope.self
        ).weather
    }

    // MARK: - Recommendations

    /// Ask the backend for ranked outfits. Supply either coordinates or an
    /// already-fetched `Weather`; with coordinates the backend fetches the
    /// weather itself, which keeps the OpenWeatherMap key off the device.
    func recommend(
        vibe: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: Weather? = nil,
        numberOfOptions: Int = 3
    ) async throws -> BackendRecommendation {
        var body: [String: Any] = ["vibe": vibe, "num_options": numberOfOptions]
        if let weather {
            body["weather"] = [
                "temperature": weather.temperature,
                "condition": weather.condition.rawValue,
                "humidity": weather.humidity,
                "wind_speed": weather.windSpeed,
                "location": weather.location,
                "units": "imperial"
            ]
        } else if let latitude, let longitude {
            body["lat"] = latitude
            body["lon"] = longitude
        }
        return try await performJSON(
            path: "api/v1/recommendations",
            method: "POST",
            body: body,
            as: BackendRecommendation.self
        )
    }

    /// Report whether the user wore one of the options.
    ///
    /// This is what makes a top-k acceptance rate measurable. `rank` is the
    /// 1-based position of the option they chose. Call it from wherever the
    /// user accepts or dismisses an outfit.
    func submitFeedback(
        recommendationId: String,
        accepted: Bool,
        rank: Int? = nil,
        note: String? = nil
    ) async throws {
        struct FeedbackEnvelope: Codable {
            struct Feedback: Codable { let accepted: Bool }
            let feedback: Feedback
        }
        var body: [String: Any] = ["accepted": accepted]
        if let rank { body["accepted_rank"] = rank }
        if let note { body["note"] = note }
        _ = try await performJSON(
            path: "api/v1/recommendations/\(recommendationId)/feedback",
            method: "POST",
            body: body,
            as: FeedbackEnvelope.self
        )
    }

    // MARK: - Health

    func isReachable() async -> Bool {
        guard let base = AppConfig.backendBaseURL else { return false }
        var request = URLRequest(url: base.appendingPathComponent("healthz"))
        request.timeoutInterval = 5
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}

// MARK: - Completion-handler bridge

/// The existing services are completion-handler based. These wrappers let call
/// sites adopt the backend without being rewritten for async/await.
///
/// Deliberately given distinct names rather than overloading the async methods
/// with a trailing `completion:`. Overload sets that differ only by a defaulted
/// argument are an easy way to get an "ambiguous use of" error, and this file
/// has not been compiled. Distinct names remove the risk entirely.
extension BackendService {

    func classifyImage(
        _ image: UIImage,
        completion: @escaping (Result<BackendClassification, Error>) -> Void
    ) {
        Task {
            do {
                let result = try await self.classify(image: image)
                await MainActor.run { completion(.success(result)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func recommendOutfits(
        vibe: String,
        weather: Weather,
        numberOfOptions: Int = 3,
        completion: @escaping (Result<BackendRecommendation, Error>) -> Void
    ) {
        Task {
            do {
                let result = try await self.recommend(
                    vibe: vibe,
                    latitude: nil,
                    longitude: nil,
                    weather: weather,
                    numberOfOptions: numberOfOptions
                )
                await MainActor.run { completion(.success(result)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func loadItems(
        dirty: Bool? = nil,
        completion: @escaping (Result<[ClothingItem], Error>) -> Void
    ) {
        Task {
            do {
                let items = try await self.fetchItems(dirty: dirty).map { $0.asClothingItem() }
                await MainActor.run { completion(.success(items)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    func submitFeedback(
        recommendationId: String,
        accepted: Bool,
        rank: Int? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        Task {
            do {
                try await self.submitFeedback(
                    recommendationId: recommendationId, accepted: accepted, rank: rank, note: nil
                )
                await MainActor.run { completion(.success(())) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
}
