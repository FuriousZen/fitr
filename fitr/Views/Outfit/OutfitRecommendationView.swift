//
//  OutfitRecommendationView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI
import Kingfisher

struct OutfitRecommendationView: View {
    let outfit: Outfit
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isSuccessToast = true
    @State private var markedItems = Set<String>()
    @State private var animatingItemId: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Today's Outfit")
                .font(.headline)
                .foregroundColor(AppColors.davyGrey)
            
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
                                
                                if !markedItems.contains(item.id) {
                                    Button(action: { markAsDirty(item) }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "basket")
                                                .font(.system(size: 10))
                                            Text("Mark Dirty")
                                                .font(.caption2)
                                        }
                                        .padding(4)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.red.opacity(0.2))
                                        .foregroundColor(.red)
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                } else {
                                    Text("In Laundry")
                                        .font(.caption2)
                                        .padding(4)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.gray.opacity(0.2))
                                        .foregroundColor(Color.gray)
                                        .cornerRadius(4)
                                }
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
        .toast(isPresented: $showToast, message: toastMessage, isSuccess: isSuccessToast)
    }
    
    private func markAsDirty(_ item: ClothingItem) {
        // Start animation
        animatingItemId = item.id
        
        // Call Firebase service
        FirebaseService.shared.markItemAsDirty(item: item) { result in
            DispatchQueue.main.async {
                // Stop animation
                animatingItemId = nil
                
                switch result {
                case .success:
                    // Add to marked items set
                    markedItems.insert(item.id)
                    
                    // Show success toast
                    toastMessage = "\(item.name) added to laundry basket"
                    isSuccessToast = true
                    showToast = true
                    
                    // Hide toast after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showToast = false
                    }
                    
                    // Notify that the wardrobe has been updated
                    NotificationCenter.default.post(
                        name: Notification.Name("WardrobeUpdated"),
                        object: nil,
                        userInfo: ["operation": "update"]
                    )
                    
                case .failure(let error):
                    // Show error toast
                    toastMessage = "Failed to update: \(error.localizedDescription)"
                    isSuccessToast = false
                    showToast = true
                    
                    // Hide toast after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showToast = false
                    }
                }
            }
        }
    }
}
