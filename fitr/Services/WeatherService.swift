import Foundation
import CoreLocation

enum WeatherServiceError: LocalizedError {
    case notConfigured
    case invalidURL
    case noData
    case unauthorized
    case http(status: Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenWeatherMap is not configured. Set OPENWEATHERMAP_API_KEY or FITR_BACKEND_URL."
        case .invalidURL:
            return "Invalid weather URL"
        case .noData:
            return "No data received"
        case .unauthorized:
            return "OpenWeatherMap rejected the API key"
        case .http(let status):
            return "Weather service returned HTTP \(status)"
        }
    }
}

/// Direct OpenWeatherMap client, used only when no backend is configured.
/// With `FITR_BACKEND_URL` set the app calls `BackendService.weather` instead
/// and the API key stays on the server.
class WeatherService {
    static let shared = WeatherService()
    
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    private var cachedWeather: Weather?
    private var cachedQuery: [URLQueryItem] = []
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 3600
    
    func getWeather(latitude: Double, longitude: Double, completion: @escaping (Result<Weather, Error>) -> Void) {
        fetch(query: [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude))
        ], completion: completion)
    }
    
    func getWeather(city: String, completion: @escaping (Result<Weather, Error>) -> Void) {
        fetch(query: [URLQueryItem(name: "q", value: city)], completion: completion)
    }
    
    private func fetch(query: [URLQueryItem], completion: @escaping (Result<Weather, Error>) -> Void) {
        if let cachedWeather = cachedWeather,
           let cacheTimestamp = cacheTimestamp,
           cachedQuery == query,
           Date().timeIntervalSince(cacheTimestamp) < cacheValidityDuration {
            completion(.success(cachedWeather))
            return
        }
        
        guard APIKeys.hasOpenWeatherMapKey else {
            completion(.failure(WeatherServiceError.notConfigured))
            return
        }
        
        var components = URLComponents(string: baseURL)
        components?.queryItems = query + [
            URLQueryItem(name: "units", value: "imperial"),
            URLQueryItem(name: "appid", value: APIKeys.openWeatherMapKey)
        ]
        
        guard let url = components?.url else {
            completion(.failure(WeatherServiceError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(http.statusCode == 401 ? WeatherServiceError.unauthorized : WeatherServiceError.http(status: http.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(WeatherServiceError.noData))
                return
            }
            
            do {
                let weatherResponse = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
                
                let weather = Weather(
                    temperature: weatherResponse.main.temp,
                    condition: WeatherService.condition(fromOpenWeather: weatherResponse.weather.first?.main ?? ""),
                    humidity: weatherResponse.main.humidity,
                    windSpeed: weatherResponse.wind.speed,
                    location: weatherResponse.name,
                    date: Date()
                )
                self.cachedWeather = weather
                self.cachedQuery = query
                self.cacheTimestamp = Date()
                
                completion(.success(weather))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    /// Maps OpenWeatherMap's `weather[0].main` group onto the app's conditions.
    static func condition(fromOpenWeather condition: String) -> WeatherCondition {
        switch condition.lowercased() {
        case "clear":
            return .sunny
        case "clouds":
            return .cloudy
        case "rain", "drizzle":
            return .rainy
        case "snow":
            return .snowy
        case "thunderstorm":
            return .stormy
        case "mist", "fog":
            return .foggy
        default:
            if condition.lowercased().contains("wind") {
                return .windy
            } else {
                return .cloudy
            }
        }
    }
}

// models for OpenWeatherMap API response
struct OpenWeatherResponse: Codable {
    let weather: [WeatherInfo]
    let main: MainInfo
    let wind: WindInfo
    let name: String
}

struct WeatherInfo: Codable {
    let main: String
    let description: String
}

struct MainInfo: Codable {
    let temp: Double
    let humidity: Int
}

struct WindInfo: Codable {
    let speed: Double
}
