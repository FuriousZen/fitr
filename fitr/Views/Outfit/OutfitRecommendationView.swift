//
//  OutfitRecommendationView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI
import Kingfisher

struct OutfitRecommendationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var outfit: Outfit?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isSuccessToast = true
    @State private var markedItems = Set<String>()
    @State private var animatingItemId: String? = nil
    
    let weather: Weather
    let vibe: String
    
    var body: some View {
        VStack {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if let outfit = outfit {
                outfitView(outfit: outfit)
            }
        }
        .onAppear{
            if outfit == nil {
                   loadOutfitRecommendation()
               }
        }
        .toast(isPresented: $showToast, message: toastMessage, isSuccess: isSuccessToast)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Creating your \(vibe) outfit...")
                .font(.headline)
                .foregroundColor(AppColors.davyGrey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Unable to create outfit")
                .font(.headline)
                .foregroundColor(AppColors.davyGrey)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(AppColors.davyGrey.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: loadOutfitRecommendation) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .padding()
                .background(AppColors.springRain)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
    
    private func outfitView(outfit: Outfit) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Outfit header
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("\(vibe) Outfit")
                            .font(.headline)
                            .foregroundColor(AppColors.davyGrey)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer")
                                .font(.caption)
                            Text("\(Int(weather.temperature))°F")
                                .font(.caption)
                            Image(systemName: weatherIcon(for: weather.condition))
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.moonMist.opacity(0.3))
                        .cornerRadius(12)
                    }
                    
                    Text(outfit.description)
                        .font(.subheadline)
                        .foregroundColor(AppColors.davyGrey.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 5)
                    
                    if outfit.items.isEmpty {
                        Text("No items available for recommendation")
                            .font(.subheadline)
                            .foregroundColor(AppColors.davyGrey.opacity(0.6))
                            .padding()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                ForEach(outfit.items) { item in
                                    VStack(spacing: 8) {
                                        ZStack {
                                            KFImage(URL(string: item.imageURL))
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 120, height: 150)
                                                .cornerRadius(10)
                                                .scaleEffect(animatingItemId == item.id ? 0.9 : 1.0)
                                                .opacity(markedItems.contains(item.id) ? 0.6 : 1.0)
                                            
                                            if markedItems.contains(item.id) {
                                                Image(systemName: "basket.fill")
                                                    .font(.system(size: 30))
                                                    .foregroundColor(.white)
                                                    .padding(8)
                                                    .background(Circle().fill(Color.red.opacity(0.7)))
                                            }
                                        }
                                        .animation(.spring(response: 0.3), value: animatingItemId)
                                        .animation(.easeInOut, value: markedItems)
                                        
                                        Text(item.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(AppColors.davyGrey)
                                            .lineLimit(1)
                                        
                                        Text(item.type.rawValue)
                                            .font(.caption)
                                            .foregroundColor(AppColors.davyGrey.opacity(0.7))
                                    }
                                    .frame(width: 120)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                .padding()
                .background(AppColors.lightPink.opacity(0.15))
                .cornerRadius(15)
                
                Text("Outfit Details")
                    .font(.headline)
                    .foregroundColor(AppColors.davyGrey)
                    .padding(.horizontal)
                
                ForEach(outfit.items) { item in
                    itemCard(item: item)
                }
            }
            .padding()
        }
    }
    
    private func itemCard(item: ClothingItem) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                // Item image
                KFImage(URL(string: item.imageURL))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(AppColors.davyGrey)
                    
                    Text(item.type.rawValue)
                        .font(.subheadline)
                        .foregroundColor(AppColors.davyGrey.opacity(0.8))
                    
                    Text(item.color)
                        .font(.caption)
                        .foregroundColor(AppColors.davyGrey.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 8) {
                    if !markedItems.contains(item.id) {
                        Button(action: { markAsDirty(item) }) {
                            VStack(spacing: 4) {
                                Image(systemName: "basket")
                                    .font(.system(size: 16))
                                Text("Dirty")
                                    .font(.caption2)
                            }
                            .foregroundColor(.red)
                            .frame(width: 50)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    Button(action: {
                        swap(item)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.2.circlepath")
                                .font(.system(size: 16))
                            Text("Swap")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                        .frame(width: 50)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
            
            HStack(spacing: 6) {
                ForEach(item.weatherTags.prefix(2), id: \.self) { tag in
                    Text(tag.rawValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.moonMist.opacity(0.3))
                        .cornerRadius(4)
                }
                
                ForEach(item.styleTags.prefix(1), id: \.self) { tag in
                    Text(tag.rawValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.springRain.opacity(0.3))
                        .cornerRadius(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func loadOutfitRecommendation() {
        print("loading new outfit")
        isLoading = true
        errorMessage = nil
        
        guard let userId = authManager.currentUser?.id else {
            isLoading = false
            errorMessage = "User not authenticated"
            return
        }
        
        FirebaseService.shared.getCleanClothingItems(for: userId) { result in
            switch result {
            case .success(let clothingItems):
                OutfitService.shared.getOutfitRecommendation(
                    userId: userId,
                    vibe: vibe,
                    weather: weather,
                    clothingItems: clothingItems
                ) { outfitResult in
                    DispatchQueue.main.async {
                        isLoading = false
                        switch outfitResult {
                        case .success(let outfit):
                            self.outfit = outfit
                        case .failure(let error):
                            self.errorMessage = "Couldn't create outfit: \(error.localizedDescription)"
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = "Failed to load wardrobe: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func markAsDirty(_ item: ClothingItem) {
        animatingItemId = item.id
        
        FirebaseService.shared.markItemAsDirty(item: item) { result in
            DispatchQueue.main.async {
                animatingItemId = nil
                
                switch result {
                case .success:
                    markedItems.insert(item.id)
                    toastMessage = "\(item.name) added to laundry basket"
                    isSuccessToast = true
                    showToast = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showToast = false
                    }
                    
                    if var currentOutfit = self.outfit {
                        currentOutfit.items.removeAll(where: { $0.id == item.id })
                        self.outfit = currentOutfit
                    }
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("WardrobeUpdated"),
                        object: nil,
                        userInfo: ["operation": "markDirty", "itemId": item.id]
                    )
                    
                case .failure(let error):
                    toastMessage = "Failed to update: \(error.localizedDescription)"
                    isSuccessToast = false
                    showToast = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showToast = false
                    }
                }
            }
        }
    }
    
    private func swap(_ item: ClothingItem) {
        animatingItemId = item.id
        
        FirebaseService.shared.swapItem(item: item) { result in
            DispatchQueue.main.async {
                animatingItemId = nil
                switch result {
                case .success(let newItem):
                    if var currentOutfit = self.outfit {
                        if let index = currentOutfit.items.firstIndex(where: { $0.id == item.id }) {
                            currentOutfit.items[index] = newItem
                            self.outfit = currentOutfit
                        }
                    }
                    toastMessage = "\(item.name) swapped successfully"
                    isSuccessToast = true
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showToast = false
                    }
                case .failure(let error):
                    toastMessage = "Failed to swap item: \(error.localizedDescription)"
                    isSuccessToast = false
                    showToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showToast = false
                    }
                }
            }
        }
    }
    
    private func weatherIcon(for condition: WeatherCondition) -> String {
        switch condition {
        case .sunny:
            return "sun.max.fill"
        case .cloudy:
            return "cloud.fill"
        case .rainy:
            return "cloud.rain.fill"
        case .snowy:
            return "cloud.snow.fill"
        case .stormy:
            return "cloud.bolt.fill"
        case .windy:
            return "wind"
        case .foggy:
            return "cloud.fog.fill"
        }
    }
}
