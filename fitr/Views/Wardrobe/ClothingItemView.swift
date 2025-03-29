import SwiftUI
import Kingfisher

struct ClothingItemView: View {
    let item: ClothingItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { // Reduced spacing for a tighter layout
            KFImage(URL(string: item.imageURL))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 160) // Reduced image height
                .cornerRadius(12, corners: [.topLeft, .topRight])
                .clipped()
            
            VStack(alignment: .leading, spacing: 6) { // Reduced spacing here too
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(AppColors.davyGrey)
                    .lineLimit(1) // Ensures name is a single line
                
                Text(item.type.rawValue)
                    .font(.subheadline)
                    .foregroundColor(AppColors.davyGrey.opacity(0.8))
                    .lineLimit(1) // Limits to one line
                
                HStack(spacing: 6) { // Reduced spacing between items
                    Circle()
                        .fill(Color(hex: item.color))
                        .frame(width: 10, height: 10) // Smaller color circle
                    
                    Text(item.color)
                        .font(.caption)
                        .foregroundColor(AppColors.davyGrey.opacity(0.7))
                        .lineLimit(1) // Ensures color text stays on one line
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(item.weatherTags), id: \.self) { tag in
                            Text(tag.rawValue)
                                .font(.system(size: 9)) // Smaller font for tags
                                .padding(.horizontal, 6) // Reduced padding
                                .padding(.vertical, 3) // Reduced vertical padding
                                .background(AppColors.lightPink.opacity(0.3))
                                .foregroundColor(AppColors.davyGrey)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .padding(.horizontal, 8) // Reduced horizontal padding
            .padding(.bottom, 8) // Reduced bottom padding
        }
        .background(AppColors.moonMist.opacity(0.2))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .frame(maxWidth: .infinity) // Ensures it takes up available space
    }
}
