//  Dash.swift
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
    
    @State private var locationRetryCount = 0
    private let maxLocationRetries = 3
    
    private let vibes = ["Casual", "Formal", "Athletic", "Cozy", "Night Out"]
    
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
        locationRetryCount = 0
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
    
    private func loadWeatherData() {
        isLoading = true
            WeatherService.shared.getWeatherForCharlottesville { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let weather):
                    self.weather = weather
                    self.isLoading = false
                case .failure(let error):
                    print("Weather error: \(error.localizedDescription)")
                    self.errorMessage = "Weather service unavailable. Using default recommendation."
                    self.useDefaultWeather()
                }
            }
        }
    }

    private func useDefaultWeather() {
        let defaultWeather = Weather(
            temperature: 20.0,
            condition: .cloudy,
            humidity: 50,
            windSpeed: 10,
            location: "Default Location",
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



