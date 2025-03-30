//
//  ToastView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//
import SwiftUI
// Toast View Component
struct ToastView: View {
    let message: String
    let isSuccess: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isSuccess ? AppColors.springRain : Color.red)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// Toast Modifier
struct ToastModifier: ViewModifier {
    @Binding var showToast: Bool
    let message: String
    let isSuccess: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            VStack {
                if showToast {
                    ToastView(message: message, isSuccess: isSuccess)
                        .padding(.top, 10)
                        .animation(.spring(), value: showToast)
                }
                Spacer()
            }
        }
    }
}


// Extension for easier use
extension View {
    func toast(isPresented: Binding<Bool>, message: String, isSuccess: Bool = true) -> some View {
        self.modifier(ToastModifier(showToast: isPresented, message: message, isSuccess: isSuccess))
    }
}
