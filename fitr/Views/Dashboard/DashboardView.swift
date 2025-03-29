//
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

@State private var weather: Weather?
@State private var outfit: Outfit?
@State private var clothingItems: [ClothingItem] = []
@State private var isLoading = true
@State private var errorMessage: String?
@State private var isWardrobeEmpty = false
@State private var selectedTab = 0
    
// Location retry tracking
@State private var locationRetryCount = 0
private let maxLocationRetries = 3

    var body: some View {
        if authManager.isLoading {
            // Show loading screen while auth state is being restored
            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.davyGrey))
                Text("Loading your profile...")
                    .font(.headline)
                    .foregroundColor(AppColors.davyGrey)
                    .padding(.top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.peachSnaps.opacity(0.1).ignoresSafeArea())
        } else {
            TabView(selection: $selectedTab) {
                // Home Tab
                ScrollView {
                    VStack(spacing: 20) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.davyGrey))
                                .padding(.top, 100)
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                // Welcome section
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Hello, \(authManager.currentUser?.name ?? "there")!")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.davyGrey)
                                    
                                    if !isWardrobeEmpty {
                                        Text("Here's your outfit for today")
                                            .font(.subheadline)
                                            .foregroundColor(AppColors.davyGrey.opacity(0.8))
                                    }
                                }
                                .padding(.horizontal)
                                
                                if isWardrobeEmpty {
                                    // Empty wardrobe welcome view
                                    VStack(spacing: 25) {
                                        // Illustration or icon
                                        Image(systemName: "tshirt.fill")
                                            .font(.system(size: 60))
                                            .foregroundColor(AppColors.springRain)
                                            .padding()
                                            .background(
                                                Circle()
                                                    .fill(AppColors.moonMist.opacity(0.3))
                                                    .frame(width: 120, height: 120)
                                            )
                                        
                                        // Welcome message
                                        VStack(spacing: 8) {
                                            HStack(spacing: 2) {
                                                Text("Welcome to ")
                                                    .font(.title2)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(AppColors.davyGrey)
                                                
                                                Text("fitr")
                                                    .font(.system(.title2, design: .rounded))
                                                    .fontWeight(.black)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        LinearGradient(
                                                            gradient: Gradient(colors: [AppColors.springRain, AppColors.springRain.opacity(0.7)]),
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                        .clipShape(Capsule())
                                                    )
                                                    .shadow(color: AppColors.springRain.opacity(0.4), radius: 3, x: 0, y: 2)
                                                
                                                Text("!")
                                                    .font(.title2)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(AppColors.davyGrey)
                                            }
                                            
                                            Text("Let's build your virtual wardrobe")
                                                .font(.body)
                                                .foregroundColor(AppColors.davyGrey.opacity(0.8))
                                                .multilineTextAlignment(.center)
                                        }
                                        
                                        // Call to action
                                        Button(action: {
                                            selectedTab = 1  // Switch to wardrobe tab
                                        }) {
                                            HStack {
                                                Image(systemName: "plus.circle.fill")
                                                Text("Add Your First Item")
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 24)
                                            .background(AppColors.springRain)
                                            .foregroundColor(.white)
                                            .cornerRadius(25)
                                            .shadow(color: AppColors.springRain.opacity(0.3), radius: 10, x: 0, y: 5)
                                        }
                                        .padding(.top, 10)
                                        
                                        // Optional tip
                                        Text("Tip: Add a few items to get personalized outfit recommendations")
                                            .font(.caption)
                                            .foregroundColor(AppColors.davyGrey.opacity(0.6))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 40)
                                            .padding(.top, 10)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                    .padding(.horizontal, 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.white)
                                            .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 5)
                                    )
                                    .padding(.horizontal)
                                } else {
                                    // Weather section
                                    if let weather = weather {
                                        WeatherView(weather: weather)
                                            .padding(.horizontal)
                                    } else {
                                        Text("Weather data unavailable")
                                            .font(.headline)
                                            .foregroundColor(AppColors.davyGrey.opacity(0.6))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding()
                                    }
                                    
                                    // Outfit recommendation
                                    if let outfit = outfit {
                                        OutfitRecommendationView(outfit: outfit)
                                            .padding(.horizontal)
                                    } else {
                                        Text("Outfit recommendation unavailable")
                                            .font(.headline)
                                            .foregroundColor(AppColors.davyGrey.opacity(0.6))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding()
                                    }
                                }
                                
                                // Quick actions
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Quick Actions")
                                        .font(.headline)
                                        .foregroundColor(AppColors.davyGrey)
                                        .padding(.horizontal)
                                    
                                    HStack(spacing: 15) {
                                        QuickActionButton(
                                            icon: "camera.fill",
                                            title: "Add Clothing",
                                            color: AppColors.springRain
                                        ) {
                                            selectedTab = 1
                                        }
                                        
                                        QuickActionButton(
                                            icon: "arrow.clockwise",
                                            title: "Refresh",
                                            color: AppColors.lightPink
                                        ) {
                                            refreshData()
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                
                                if let errorMessage = errorMessage, !isWardrobeEmpty {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding()
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .background(AppColors.peachSnaps.opacity(0.1).ignoresSafeArea())
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
                
                // Wardrobe Tab
                WardrobeView()
                    .environmentObject(authManager)
                    .tabItem {
                        Label("Wardrobe", systemImage: "tshirt.fill")
                    }
                    .tag(1)
                
                // Profile Tab
                ProfileView()
                    .environmentObject(authManager)
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
                    .tag(2)
            }
            .accentColor(AppColors.davyGrey)
            .onAppear {
                loadData()
            }
        }
    }

    private func loadData() {
        isLoading = true
        errorMessage = nil
        isWardrobeEmpty = false
        locationRetryCount = 0
        
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "User not authenticated"
            isLoading = false
            return
        }
        
        // Load clothing items first
        FirebaseService.shared.getClothingItems(for: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let items):
                    self.clothingItems = items
                    self.isWardrobeEmpty = items.isEmpty
                    
                    if !items.isEmpty {
                        self.loadWeatherData()
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
        // If we've exceeded retry attempts, use default weather
        guard locationRetryCount < maxLocationRetries else {
            self.useDefaultWeather()
            return
        }
        
        locationRetryCount += 1
        
        // If we have location, fetch weather immediately
        if let location = locationManager.location {
            fetchWeather(for: location)
        }
        // Otherwise request location and try again after delay
        else {
            locationManager.requestLocation()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.loadWeatherData()
            }
        }
    }
    
    private func fetchWeather(for location: CLLocation) {
        WeatherService.shared.getWeather(for: location) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let weather):
                    self.weather = weather
                    self.getOutfitRecommendation(weather: weather)
                case .failure(let error):
                    // If weather API fails, try with default weather
                    self.errorMessage = "Weather service unavailable. Using default recommendation."
                    self.useDefaultWeather()
                }
            }
        }
    }
    
    private func useDefaultWeather() {
        // Create default weather (moderate temperature)
        let defaultWeather = Weather(
            temperature: 20.0,
            condition: .cloudy,
            humidity: 50,
            windSpeed: 10,
            location: "Default Location",
            date: Date()
        )
        
        self.weather = defaultWeather
        self.getOutfitRecommendation(weather: defaultWeather)
    }
    
    private func getOutfitRecommendation(weather: Weather) {
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "User not authenticated"
            isLoading = false
            return
        }
        
        OutfitService.shared.getOutfitRecommendation(
            userId: userId,
            weather: weather,
            clothingItems: clothingItems
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let outfit):
                    self.outfit = outfit
                case .failure(let error):
                    self.errorMessage = "Outfit recommendation failed: \(error.localizedDescription)"
                }
            }
        }
    }

private func refreshData() {
    loadData()
}
}

struct QuickActionButton: View {
let icon: String
let title: String
let color: Color
let action: () -> Void

var body: some View {
    Button(action: action) {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(color)
        .cornerRadius(12)
    }
}
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
private let locationManager = CLLocationManager()
@Published var location: CLLocation?

override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    locationManager.requestWhenInUseAuthorization()
    locationManager.startUpdatingLocation()
}

func requestLocation() {
    locationManager.requestLocation()
}

func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let location = locations.last {
        self.location = location
        locationManager.stopUpdatingLocation()
    }
}

func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("Location manager failed with error: \(error.localizedDescription)")
}
}
