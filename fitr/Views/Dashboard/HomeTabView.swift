//
//  HomeTabView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI

struct HomeTabView: View {
    @Binding var isLoading: Bool
    @Binding var weather: Weather?
    @Binding var outfit: Outfit?
    @Binding var isWardrobeEmpty: Bool
    @Binding var selectedVibe: String?
    @Binding var vibeSelectionAppeared: Bool
    @Binding var vibeButtonsAppeared: Bool
    @Binding var selectedVibeScale: CGFloat
    @Binding var errorMessage: String?
    @Binding var selectedTab: Int
    
    let vibes: [String]
    let getOutfitForVibe: (String) -> Void
    let vibeColor: (String) -> Color
    let vibeIcon: (String) -> String
    
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.davyGrey))
                        .padding(.top, 100)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        // Welcome section
                        welcomeSection
                        
                        if isWardrobeEmpty {
                            emptyWardrobeView
                        } else {
                            // Weather section
                            weatherSection
                            
                            // Vibe selection section
                            vibeSelectionSection
                            
                            // Outfit recommendation
                            outfitRecommendationSection
                        }
                        
                        // Quick actions
                        quickActionsSection
                        
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
    }
    
    // MARK: - View Components
    
    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Hello, \(authManager.currentUser?.name ?? "there")!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(AppColors.davyGrey)
            
            if !isWardrobeEmpty {
                Text("here's the weather!")
                    .font(.subheadline)
                    .foregroundColor(AppColors.davyGrey.opacity(0.8))
            }
        }
        .padding(.horizontal)
    }
    
    private var emptyWardrobeView: some View {
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
    }
    
    private var weatherSection: some View {
        Group {
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
        }
    }
    
    private var vibeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("What's your vibe for today?")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.davyGrey)
                .padding(.horizontal)
                .opacity(vibeSelectionAppeared ? 1 : 0)
                .offset(y: vibeSelectionAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: vibeSelectionAppeared)
            
            // Vibe cards in a horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(vibes.enumerated()), id: \.element) { index, vibe in
                        VibeButton(
                            vibe: vibe,
                            isSelected: selectedVibe == vibe,
                            vibeButtonsAppeared: vibeButtonsAppeared,
                            selectedVibeScale: selectedVibeScale,
                            index: index,
                            vibeColor: vibeColor,
                            vibeIcon: vibeIcon
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedVibe = vibe
                                selectedVibeScale = 0.95
                            }
                            
                            // Reset scale after brief animation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.spring()) {
                                    selectedVibeScale = 1.0
                                }
                            }
                            
                            getOutfitForVibe(vibe)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .padding(.vertical, 5)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.5))
                .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
        .onAppear {
            // Trigger animations when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    vibeSelectionAppeared = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation {
                        vibeButtonsAppeared = true
                    }
                }
            }
        }
    }
    
    private var outfitRecommendationSection: some View {
        Group {
            if let outfit = outfit {
                       OutfitRecommendationView(outfit: outfit)
                           .padding(.horizontal)
                           .transition(.opacity.combined(with: .move(edge: .bottom)))
                           // Use a UUID or timestamp as the animation value instead
                           .animation(.spring(), value: UUID())
                           // Or use a different animation approach:
                           // .animation(.spring(), value: selectedVibe)
            } else if selectedVibe != nil {
                VStack(spacing: 15) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: vibeColor(selectedVibe!)))
                        .scaleEffect(1.2)
                    
                    Text("Creating your \(selectedVibe?.lowercased() ?? "") outfit...")
                        .font(.subheadline)
                        .foregroundColor(AppColors.davyGrey.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.7))
                )
                .padding(.horizontal)
                .transition(.opacity)
                .animation(.easeInOut, value: selectedVibe)
            } else {
                Text("Select a vibe to get outfit recommendations")
                    .font(.subheadline)
                    .foregroundColor(AppColors.davyGrey.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    private var quickActionsSection: some View {
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
                
            }
            .padding(.horizontal)
        }
    }
}
