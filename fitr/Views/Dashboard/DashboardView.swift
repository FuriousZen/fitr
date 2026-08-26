//  DashboardView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI
import CoreLocation

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var locationManager = LocationManager()
    
    @State private var wardrobeLastUpdated = Date()
    
    @State private var weather: Weather?
    @State private var outfit: Outfit?
    @State private var clothingItems: [ClothingItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isWardrobeEmpty = false
    @State private var selectedTab = 0
    @State private var selectedVibe: String?
    @State private var vibeSelectionAppeared = false
    
    @State private var vibeButtonsAppeared = false
    @State private var selectedVibeScale: CGFloat = 1.0
    
    /// True while the dashboard is waiting on Core Location before it can
    /// fetch weather; cleared once a fix, a denial or an error arrives.
    @State private var awaitingLocation = false
    
    private let vibes = ["Casual", "Formal", "Athletic", "Cozy", "Night Out"]
    
    /// Used only when the user has declined location access. The copy shown
    /// alongside the weather card says so.
    private let fallbackCity = "Charlottesville,VA,US"
    private let fallbackCityLabel = "Charlottesville, VA"
    
    var body: some View {
        if authManager.isLoading {
            LoadingView()
        } else {
            MainTabView(
                selectedTab: $selectedTab,
                isLoading: $isLoading,
                weather: $weather,
                outfit: $outfit,
                isWardrobeEmpty: $isWardrobeEmpty,
                selectedVibe: $selectedVibe,
                vibeSelectionAppeared: $vibeSelectionAppeared,
                vibeButtonsAppeared: $vibeButtonsAppeared,
                selectedVibeScale: $selectedVibeScale,
                errorMessage: $errorMessage,
                vibes: vibes,
                loadData: loadData,
                getOutfitForVibe: getOutfitForVibe,
                vibeColor: vibeColor,
                vibeIcon: vibeIcon
            )
            .environmentObject(authManager)
            .onAppear {
                loadData()
            }
            .onReceive(locationManager.$location) { location in
                guard awaitingLocation, let location = location else { return }
                awaitingLocation = false
                fetchWeather(for: location.coordinate)
            }
            .onReceive(locationManager.$authorizationStatus) { status in
                guard awaitingLocation else { return }
                if status == .denied || status == .restricted {
                    awaitingLocation = false
                    fetchWeatherForFallbackCity()
                }
            }
            .onReceive(locationManager.$locationError) { error in
                guard awaitingLocation, error != nil else { return }
                awaitingLocation = false
                errorMessage = "Could not determine your location. Showing weather for \(fallbackCityLabel)."
                fetchWeatherForFallbackCity()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WardrobeUpdated"))) { notification in

                if let operation = notification.userInfo?["operation"] as? String {
                    switch operation {
                    case "markDirty":
                        if let itemId = notification.userInfo?["itemId"] as? String {
                            updateOutfitAfterMarkingItemDirty(itemId: itemId)
                        }
                        wardrobeLastUpdated = Date()
                        
                    default:
                        wardrobeLastUpdated = Date()
                        loadData()
                    }
                } else {
                    wardrobeLastUpdated = Date()
                    loadData()
                }
            }
        }
    }
    
    private func loadData() {
        isLoading = true
        errorMessage = nil
        isWardrobeEmpty = false
         selectedVibe = nil
         outfit = nil
         vibeSelectionAppeared = false
         vibeButtonsAppeared = false
        
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "User not authenticated"
            isLoading = false
            return
        }
        
        FirebaseService.shared.getClothingItems(for: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let items):
                    self.clothingItems = items
                    self.isWardrobeEmpty = items.isEmpty
                    
                    if !items.isEmpty {
                      if self.weather == nil {
                          self.loadWeatherData()
                      } else {
                          if self.outfit == nil && self.selectedVibe != nil {
                              self.getOutfitForVibe(vibe: self.selectedVibe!)
                          }
                          self.isLoading = false
                      }
                  } else {
                      self.isLoading = false
                  }
                    
                case .failure(let error):
                    self.errorMessage = "Failed to load wardrobe: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    /// Weather for wherever the device is. The device's coordinates drive
    /// the lookup; the fixed city is used only when location access has been
    /// denied, and the UI says so.
    private func loadWeatherData() {
        isLoading = true
        
        if let location = locationManager.location {
            fetchWeather(for: location.coordinate)
            return
        }
        
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            fetchWeatherForFallbackCity()
        default:
            awaitingLocation = true
            locationManager.requestLocation()
        }
    }
    
    private func fetchWeather(for coordinate: CLLocationCoordinate2D) {
        if BackendService.shared.isConfigured {
            Task {
                do {
                    let weather = try await BackendService.shared.weather(
                        latitude: coordinate.latitude, longitude: coordinate.longitude
                    ).asWeather()
                    await MainActor.run { self.handleWeather(.success(weather)) }
                } catch {
                    await MainActor.run { self.handleWeather(.failure(error)) }
                }
            }
            return
        }
        WeatherService.shared.getWeather(latitude: coordinate.latitude, longitude: coordinate.longitude) { result in
            DispatchQueue.main.async { self.handleWeather(result) }
        }
    }
    
    private func fetchWeatherForFallbackCity() {
        if errorMessage == nil {
            errorMessage = "Location access is off, so this is the weather for \(fallbackCityLabel). Allow location access in Settings for your local forecast."
        }
        if BackendService.shared.isConfigured {
            Task {
                do {
                    let weather = try await BackendService.shared.weather(city: fallbackCity).asWeather()
                    await MainActor.run { self.handleWeather(.success(weather)) }
                } catch {
                    await MainActor.run { self.handleWeather(.failure(error)) }
                }
            }
            return
        }
        WeatherService.shared.getWeather(city: fallbackCity) { result in
            DispatchQueue.main.async { self.handleWeather(result) }
        }
    }
    
    private func handleWeather(_ result: Result<Weather, Error>) {
        switch result {
        case .success(let weather):
            self.weather = weather
            self.isLoading = false
        case .failure(let error):
            self.errorMessage = "Weather unavailable (\(error.localizedDescription)). Recommending for a mild, cloudy day instead."
            self.useDefaultWeather()
        }
    }

    /// Imperial, to match the `units=imperial` requests and the °F the views
    /// render: 68 °F is the 20 °C "mild day" the outfit rules treat as neutral.
    private func useDefaultWeather() {
        let defaultWeather = Weather(
            temperature: 68.0,
            condition: .cloudy,
            humidity: 50,
            windSpeed: 10,
            location: "Unknown location",
            date: Date()
        )
        
        self.weather = defaultWeather
        self.isLoading = false
    }
    
    private func vibeIcon(for vibe: String) -> String {
        switch vibe {
        case "Casual": return "tshirt"
        case "Formal": return "briefcase"
        case "Athletic": return "figure.run"
        case "Cozy": return "house"
        case "Night Out": return "moon.stars"
        default: return "tshirt"
        }
    }
    
    private func vibeColor(for vibe: String) -> Color {
        switch vibe {
        case "Casual": return AppColors.springRain
        case "Formal": return AppColors.davyGrey
        case "Athletic": return Color.blue
        case "Cozy": return AppColors.lightPink
        case "Night Out": return Color.purple
        default: return AppColors.springRain
        }
    }
    
    private func getOutfitForVibe(vibe: String) {
        guard let userId = authManager.currentUser?.id, let weather = weather else {
            errorMessage = "Cannot generate outfit recommendation"
            return
        }
        
        outfit = nil
        
        OutfitService.shared.getOutfitRecommendation(
            userId: userId,
            vibe: vibe,
            weather: weather,
            clothingItems: clothingItems
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let outfit):
                    self.outfit = outfit
                case .failure(let error):
                    self.errorMessage = "Outfit recommendation failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func updateOutfitAfterMarkingItemDirty(itemId: String) {
        if var currentOutfit = outfit {
            currentOutfit.items.removeAll(where: { $0.id == itemId })
            outfit = currentOutfit
        }
        
        clothingItems.removeAll(where: { $0.id == itemId })
    }
}



