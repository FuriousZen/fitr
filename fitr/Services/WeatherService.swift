import Foundation
import CoreLocation

class WeatherService {
    static let shared = WeatherService()
    
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    private var cachedWeather: Weather?
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 3600 // 1 hour
    
    // Method to get weather for Charlottesville, VA
    func getWeatherForCharlottesville(completion: @escaping (Result<Weather, Error>) -> Void) {
        // Check if we have valid cached weather data
        if let cachedWeather = cachedWeather,
           let cacheTimestamp = cacheTimestamp,
           Date().timeIntervalSince(cacheTimestamp) < cacheValidityDuration {
            completion(.success(cachedWeather))
            return
        }
        
        // Otherwise fetch from API using city name
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "q", value: "Charlottesville,VA,US"),
            URLQueryItem(name: "units", value: "imperial"),
            URLQueryItem(name: "appid", value: APIKeys.openWeatherMapKey)
        ]
        
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "WeatherService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "WeatherService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                let weatherResponse = try JSONDecoder().decode(OpenWeatherResponse.self, from: data)
                
                // Convert to our Weather model
                let weather = Weather(
                    temperature: weatherResponse.main.temp,
                    condition: self.mapWeatherCondition(weatherResponse.weather.first?.main ?? ""),
                    humidity: weatherResponse.main.humidity,
                    windSpeed: weatherResponse.wind.speed,
                    location: weatherResponse.name,
                    date: Date()
                )
                print(weather)
                // Cache the result
                self.cachedWeather = weather
                self.cacheTimestamp = Date()
                
                completion(.success(weather))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    
    private func mapWeatherCondition(_ condition: String) -> WeatherCondition {
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
                return .cloudy // Default fallback
            }
        }
    }
}

// Models for OpenWeatherMap API response
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
