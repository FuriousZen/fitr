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
/// UNCOMPILED / UNVERIFIED. Changed on Linux with no Swift toolchain
/// available. `openWeatherMapKey` went from a stored `let` to a computed
/// `var`; reads are source-compatible, so `WeatherService` needs no change.
///
/// Set `OPENWEATHERMAP_API_KEY` in the scheme's environment variables for
/// local runs, or in Info.plist via an .xcconfig for distribution. See
/// `AppConfig`.
///
/// Note that anything in Info.plist ships inside the .ipa and is readable by
/// anyone who downloads it. The durable fix is to stop calling OpenWeatherMap
/// from the device at all and use the backend's `/api/v1/weather`, which keeps
/// the key server-side. See `BackendService.weather(latitude:longitude:)`.
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
