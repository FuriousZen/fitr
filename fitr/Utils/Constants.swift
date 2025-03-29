//
//  Constants.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI

struct AppColors {
    static let davyGrey = Color(hex: "4A5759")
    static let peachSnaps = Color(hex: "FFDAB9")
    static let moonMist = Color(hex: "D3D3D3")
    static let springRain = Color(hex: "8FBC8F")
    static let lightPink = Color(hex: "FFB6C1")
}


struct APIKeys {
    static let openWeatherMapKey = "YOUR_OPENWEATHERMAP_API_KEY"
}

struct APIEndpoints {
    static let baseURL = "YOUR_BACKEND_BASE_URL"
    static let weatherEndpoint = "/weather"
    static let outfitRecommendationEndpoint = "/outfit-recommendation"
    static let clothingClassificationEndpoint = "/classify-clothing"
}

struct FirebaseCollections {
    static let users = "users"
    static let clothingItems = "clothingItems"
    static let outfits = "outfits"
}
