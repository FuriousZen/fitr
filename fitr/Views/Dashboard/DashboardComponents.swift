//
//  DashboardComponents.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI

// Loading View
struct LoadingView: View {
    var body: some View {
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
    }
}

// Main Tab View
struct MainTabView: View {
    @Binding var selectedTab: Int
    @Binding var isLoading: Bool
    @Binding var weather: Weather?
    @Binding var outfit: Outfit?
    @Binding var isWardrobeEmpty: Bool
    @Binding var selectedVibe: String?
    @Binding var vibeSelectionAppeared: Bool
    @Binding var vibeButtonsAppeared: Bool
    @Binding var selectedVibeScale: CGFloat
    @Binding var errorMessage: String?
    
    let vibes: [String]
    let loadData: () -> Void
    let getOutfitForVibe: (String) -> Void
    let vibeColor: (String) -> Color
    let vibeIcon: (String) -> String
    
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            HomeTabView(
                isLoading: $isLoading,
                weather: $weather,
                outfit: $outfit,
                isWardrobeEmpty: $isWardrobeEmpty,
                selectedVibe: $selectedVibe,
                vibeSelectionAppeared: $vibeSelectionAppeared,
                vibeButtonsAppeared: $vibeButtonsAppeared,
                selectedVibeScale: $selectedVibeScale,
                errorMessage: $errorMessage,
                selectedTab: $selectedTab,
                vibes: vibes,
                getOutfitForVibe: getOutfitForVibe,
                vibeColor: vibeColor,
                vibeIcon: vibeIcon
            )
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
            LaundryView()
                          .tabItem {
                              Label("Laundry", systemImage: "basket.fill")
                          }
                          .tag(2)
            
            // Profile Tab
            ProfileView()
                .environmentObject(authManager)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .accentColor(AppColors.davyGrey)
    }
}

// Quick Action Button
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
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [color, color.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(color: color.opacity(0.3), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(), value: configuration.isPressed)
    }
}
