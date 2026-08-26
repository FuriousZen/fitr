//
//  AppConfig.swift
//  fitr
//
//  Runtime configuration, resolved from (in order):
//
//    1. The process environment. Set these in the scheme's
//       Run > Arguments > Environment Variables for local development.
//    2. Info.plist. Set via build settings / an .xcconfig so that different
//       configurations (Debug/Release) can point at different backends.
//
//  Nothing here contains a secret. Keys and URLs are supplied at run time or
//  build time; none is committed. Prefer routing third-party calls through the
//  fitr backend rather than shipping keys in the app bundle at all: anything
//  in Info.plist or in a Swift string literal is readable by anyone who
//  downloads the .ipa.
//

import Foundation

enum AppConfig {

    // MARK: - Lookup

    /// Environment variable first, then Info.plist. Returns nil for absent or
    /// blank values, and for the placeholder strings kept in source control.
    static func value(for key: String) -> String? {
        if let raw = ProcessInfo.processInfo.environment[key], !isPlaceholder(raw) {
            return raw
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !isPlaceholder(raw) {
            return raw
        }
        return nil
    }

    private static func isPlaceholder(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        // Guard against a placeholder being shipped as if it were a real key.
        let placeholders: Set<String> = [
            "YOUR_API_KEY_HERE",
            "YOUR_BACKEND_URL_HERE",
            "$(FITR_BACKEND_URL)",
            "$(OPENWEATHERMAP_API_KEY)"
        ]
        return placeholders.contains(trimmed)
    }

    // MARK: - Keys

    /// Base URL of the fitr Flask backend, e.g. `http://192.168.1.10:8000`.
    /// When this is nil the services fall back to calling Gemini and
    /// OpenWeatherMap from the device; `BackendService.isConfigured` reflects
    /// that.
    static var backendBaseURL: URL? {
        guard let raw = value(for: "FITR_BACKEND_URL") else { return nil }
        return URL(string: raw)
    }

    /// Only needed when no backend is configured and the app calls
    /// OpenWeatherMap directly. With a backend the key lives on the server
    /// and this should be left unset.
    static var openWeatherMapKey: String? {
        value(for: "OPENWEATHERMAP_API_KEY")
    }

    /// Seconds before a backend request is abandoned.
    static var backendTimeout: TimeInterval {
        guard let raw = value(for: "FITR_BACKEND_TIMEOUT"),
              let parsed = TimeInterval(raw) else { return 30 }
        return parsed
    }

    /// A short summary for a debug screen. Never prints secret values.
    static var debugDescription: String {
        """
        backendBaseURL: \(backendBaseURL?.absoluteString ?? "unset")
        openWeatherMapKey: \(openWeatherMapKey == nil ? "unset" : "set (hidden)")
        backendTimeout: \(backendTimeout)s
        """
    }
}
