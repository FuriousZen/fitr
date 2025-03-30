import SwiftUI
import Kingfisher

struct ClothingItemView: View {
    let item: ClothingItem
    var onDelete: () -> Void
    var onMarkDirty: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url = URL(string: item.imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(AppColors.moonMist.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 120)
                            .clipped()
                            .cornerRadius(8)
                    case .failure:
                        Rectangle()
                            .fill(AppColors.moonMist.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(AppColors.davyGrey.opacity(0.6))
                            )
                    @unknown default:
                        Rectangle()
                            .fill(AppColors.moonMist.opacity(0.3))
                    }
                }
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(AppColors.moonMist.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "tshirt")
                            .foregroundColor(AppColors.davyGrey.opacity(0.6))
                    )
                    .cornerRadius(8)
            }
            
            // Item details
            Text(item.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(AppColors.davyGrey)
                .lineLimit(1)
            
            Text(item.color)
                .font(.caption2)
                .foregroundColor(AppColors.davyGrey.opacity(0.7))
                .lineLimit(1)
        }
        .padding(8)
        .background(Color.white.opacity(0.7))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                
                Label("Delete", systemImage: "trash")
            }
            Button(role: .destructive, action: onMarkDirty) {
                Label("Mark as dirty", systemImage: "exclamationmark.triangle")
            }
        }
    }
}
