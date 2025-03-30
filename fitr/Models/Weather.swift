//
//  Weather.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import Foundation

struct Weather: Codable, Equatable {
    var temperature: Double
    var condition: WeatherCondition
    var humidity: Int
    var windSpeed: Double
    var location: String
    var date: Date
    
    enum CodingKeys: String, CodingKey {
        case temperature
        case condition
        case humidity
        case windSpeed = "wind_speed"
        case location
        case date
    }
}

enum WeatherCondition: String, Codable {
    case sunny = "Sunny"
    case cloudy = "Cloudy"
    case rainy = "Rainy"
    case snowy = "Snowy"
    case stormy = "Stormy"
    case windy = "Windy"
    case foggy = "Foggy"
}
