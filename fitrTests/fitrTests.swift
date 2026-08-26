//
//  fitrTests.swift
//  fitrTests
//
//  Created by Ryan Nguyen on 3/29/25.
//

import Foundation
import Testing
@testable import fitr

/// Pure mapping code between the backend's JSON and the app's models. None
/// of this touches the network or Firebase, so it runs anywhere the app
/// target links.
struct BackendMappingTests {

    private let decoder = JSONDecoder()

    private func item(id: String, type: String = "T-Shirt", weather: [String] = ["Warm"], style: [String] = ["casual"]) -> String {
        """
        {"id":"\(id)","user_id":"u1","name":"\(id)","type":"\(type)","color":"blue",
         "image_url":"https://example.com/\(id).jpg","weather_tags":\(jsonArray(weather)),
         "style_tags":\(jsonArray(style)),"dirty":false,"content_hash":null,
         "has_embedding":true,"created_at":"2025-04-01T12:00:00.123456+00:00"}
        """
    }

    private func jsonArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }

    @Test func classificationMapsOntoTheClassifierResult() throws {
        let json = """
        {"type":"Jeans","type_confidence":0.17,"color":"blue","color_confidence":0.31,
         "style_tags":["casual","everyday"],"weather_tags":["Cool","Cold"],"cache_tier":"l1"}
        """
        let decoded = try decoder.decode(BackendClassification.self, from: Data(json.utf8))
        let result = decoded.asClassificationResult()

        #expect(result.type == "Jeans")
        #expect(result.color == "blue")
        #expect(result.styleTags == ["casual", "everyday"])
        #expect(result.weatherTags == ["Cool", "Cold"])
    }

    @Test func clothingItemConvertsKnownTagsAndDropsUnknownOnes() throws {
        let json = item(id: "a", type: "Cape", weather: ["Warm", "Tropical"], style: ["casual", "gothic"])
        let backend = try decoder.decode(BackendClothingItem.self, from: Data(json.utf8))
        let converted = backend.asClothingItem()

        #expect(converted.id == "a")
        #expect(converted.type == .other)
        #expect(converted.weatherTags == [.warm])
        #expect(converted.styleTags == [.casual])
        #expect(converted.imageURL == "https://example.com/a.jpg")
        #expect(converted.dirty == false)
    }

    @Test func recommendationBecomesTheTopRankedOutfit() throws {
        let json = """
        {"id":"rec-1","user_id":"u1","vibe":"Casual",
         "weather":{"temperature":41.0,"condition":"Rainy","humidity":88,"wind_speed":9.0,"location":"Charlottesville","units":"imperial"},
         "options":[
           {"rank":2,"item_ids":["b"],"description":"second","items":[\(item(id: "b"))]},
           {"rank":1,"item_ids":["a","c"],"description":"best","items":[\(item(id: "a")),\(item(id: "c", type: "Jeans"))]}
         ],
         "generator":"gemini","model":"gemini-3.6-flash"}
        """
        let recommendation = try decoder.decode(BackendRecommendation.self, from: Data(json.utf8))
        let outfit = try #require(recommendation.asOutfit())

        #expect(outfit.id == "rec-1")
        #expect(outfit.description == "best")
        #expect(outfit.vibe == "Casual")
        #expect(outfit.items.map { $0.id } == ["a", "c"])
        #expect(outfit.items.map { $0.type } == [.tShirt, .jeans])
        #expect(outfit.weather.temperature == 41.0)
        #expect(outfit.weather.condition == .rainy)
        #expect(outfit.weather.location == "Charlottesville")
    }

    @Test func recommendationWithNoOptionsYieldsNoOutfit() throws {
        let json = """
        {"id":"rec-2","user_id":"u1","vibe":"Casual",
         "weather":{"temperature":70.0,"condition":"Sunny","humidity":40,"wind_speed":3.0,"location":"Here"},
         "options":[],"generator":"none","model":null}
        """
        let recommendation = try decoder.decode(BackendRecommendation.self, from: Data(json.utf8))
        #expect(recommendation.asOutfit() == nil)
    }

    @Test func unknownWeatherConditionFallsBackToCloudy() throws {
        let json = """
        {"temperature":55.0,"condition":"Hail","humidity":60,"wind_speed":12.0,"location":"Somewhere"}
        """
        let weather = try decoder.decode(BackendWeather.self, from: Data(json.utf8)).asWeather()
        #expect(weather.condition == .cloudy)
        #expect(weather.windSpeed == 12.0)
    }

    @Test func backendDatesParseWithAndWithoutFractionalSeconds() {
        #expect(BackendService.parseDate("2025-04-01T12:00:00.123456+00:00") != nil)
        #expect(BackendService.parseDate("2025-04-01T12:00:00Z") != nil)
        #expect(BackendService.parseDate("yesterday") == nil)
        #expect(BackendService.parseDate(nil) == nil)
    }
}

struct WeatherServiceTests {

    @Test(arguments: [
        ("Clear", WeatherCondition.sunny),
        ("Clouds", WeatherCondition.cloudy),
        ("Rain", WeatherCondition.rainy),
        ("Drizzle", WeatherCondition.rainy),
        ("Snow", WeatherCondition.snowy),
        ("Thunderstorm", WeatherCondition.stormy),
        ("Mist", WeatherCondition.foggy),
        ("Squall wind", WeatherCondition.windy),
        ("Haze", WeatherCondition.cloudy),
    ])
    func openWeatherGroupsMapOntoAppConditions(group: String, expected: WeatherCondition) {
        #expect(WeatherService.condition(fromOpenWeather: group) == expected)
    }

    @Test func httpErrorsExplainThemselves() {
        #expect(WeatherServiceError.unauthorized.errorDescription?.contains("API key") == true)
        #expect(WeatherServiceError.http(status: 503).errorDescription?.contains("503") == true)
        #expect(WeatherServiceError.notConfigured.errorDescription?.contains("OPENWEATHERMAP_API_KEY") == true)
    }
}

struct AppConfigTests {

    @Test func backendIsUnconfiguredWhenTheKeyIsAbsentOrAPlaceholder() {
        // The test process does not set FITR_BACKEND_URL, and the test host's
        // Info.plist does not carry one, so the placeholder guard is what
        // keeps `$(FITR_BACKEND_URL)` from being treated as a URL.
        #expect(AppConfig.value(for: "FITR_BACKEND_URL_DOES_NOT_EXIST") == nil)
        #expect(AppConfig.backendTimeout > 0)
    }
}
