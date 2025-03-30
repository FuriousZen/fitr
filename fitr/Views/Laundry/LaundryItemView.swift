//
//  LaundryItemView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/30/25.
//
import SwiftUI
import Kingfisher

struct LaundryItemView: View {
    let item: ClothingItem
    let isEditing: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onWash: () -> Void
    
    @State private var showActionSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Item image
                KFImage(URL(string: item.imageURL))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .cornerRadius(8)
                    .clipped()
                
                // Selection indicator or action button
                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? AppColors.springRain : .white)
                        .background(
                            Circle()
                                .fill(isSelected ? .white : Color.black.opacity(0.6))
                                .frame(width: 24, height: 24)
                        )
                        .padding(6)
                } else {
                    Button(action: {
                        showActionSheet = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(6)
                }
            }
            
            Text(item.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Text(item.type.rawValue)
                .font(.caption)
                .foregroundColor(AppColors.davyGrey.opacity(0.7))
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                onToggleSelection()
            } else {
                showActionSheet = true
            }
        }
        .actionSheet(isPresented: $showActionSheet) {
            ActionSheet(
                title: Text(item.name),
                buttons: [
                    .default(Text("Wash and Return to Wardrobe")) {
                        onWash()
                    },
                    .cancel()
                ]
            )
        }
    }
}
