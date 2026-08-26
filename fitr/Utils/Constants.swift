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


/// API keys, resolved at run time rather than compiled into the binary.
///
/// `OPENWEATHERMAP_API_KEY` is only read when no backend is configured; with
/// `FITR_BACKEND_URL` set, weather goes through `/api/v1/weather` and the key
/// stays on the server. Set it in the scheme's environment variables for
/// local runs, or in Info.plist via an .xcconfig for distribution (see
/// `AppConfig`). Anything in Info.plist ships inside the .ipa and is readable
/// by anyone who downloads it.
struct APIKeys {
    static var openWeatherMapKey: String {
        AppConfig.openWeatherMapKey ?? ""
    }

    /// Lets callers show a clear "not configured" state instead of firing a
    /// request that OpenWeatherMap will reject with a 401.
    static var hasOpenWeatherMapKey: Bool {
        AppConfig.openWeatherMapKey != nil
    }
}

struct FirebaseCollections {
    static let users = "users"
    static let clothingItems = "clothingItems"
    static let outfits = "outfits"
}
