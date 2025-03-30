//
//  VibeButton.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI

struct VibeButton: View {
    let vibe: String
    let isSelected: Bool
    let vibeButtonsAppeared: Bool
    let selectedVibeScale: CGFloat
    let index: Int
    let vibeColor: (String) -> Color
    let vibeIcon: (String) -> String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [vibeColor(vibe), vibeColor(vibe).opacity(0.7)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                        .shadow(color: vibeColor(vibe).opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: vibeIcon(vibe))
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text(vibe)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? vibeColor(vibe) : AppColors.davyGrey)
            }
            .frame(width: 100, height: 120)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(
                        color: isSelected ?
                            vibeColor(vibe).opacity(0.2) :
                            Color.black.opacity(0.05),
                        radius: isSelected ? 10 : 5,
                        x: 0,
                        y: isSelected ? 5 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ?
                            vibeColor(vibe) :
                            Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isSelected ? selectedVibeScale : 1.0)
            .opacity(vibeButtonsAppeared ? 1 : 0)
            .offset(y: vibeButtonsAppeared ? 0 : 30)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.7)
                    .delay(0.2 + Double(index) * 0.1),
                value: vibeButtonsAppeared
            )
        }
    }
}
