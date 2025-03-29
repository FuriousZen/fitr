//  LoginView.swift

//  fitr

//

//  Created by Ryan Nguyen on 3/29/25.

//

import SwiftUI

struct LoginView: View {

    @EnvironmentObject var authManager: AuthenticationManager

    @State private var email = ""

    @State private var password = ""

    @State private var name = ""

    @State private var isSignUp = false

    

    var body: some View {

        ZStack {

            // Background gradient

            LinearGradient(

                gradient: Gradient(colors: [AppColors.peachSnaps, AppColors.lightPink.opacity(0.7)]),

                startPoint: .topLeading,

                endPoint: .bottomTrailing

            )

            .ignoresSafeArea()

            

            VStack(spacing: 30) {

                // Logo and app name

                VStack(spacing: 10) {

                    Image(systemName: "tshirt.fill")

                        .resizable()

                        .scaledToFit()

                        .frame(width: 80, height: 80)

                        .foregroundColor(AppColors.davyGrey)

                    

                    Text("fitr")

                        .font(.system(size: 40, weight: .bold, design: .rounded))

                        .foregroundColor(AppColors.davyGrey)

                    

                    Text("Your AI Wardrobe Assistant")

                        .font(.subheadline)

                        .foregroundColor(AppColors.davyGrey.opacity(0.8))

                }

                .padding(.bottom, 20)

                

                // Login/Signup form

                VStack(spacing: 20) {

                    if isSignUp {

                        TextField("Name", text: $name)

                            .textFieldStyle(RoundedTextFieldStyle())

                    }

                    

                    TextField("Email", text: $email)

                        .textFieldStyle(RoundedTextFieldStyle())

                        .keyboardType(.emailAddress)

                        .autocapitalization(.none)

                    

                    SecureField("Password", text: $password)

                        .textFieldStyle(RoundedTextFieldStyle())

                    

                    if authManager.isLoading {

                        ProgressView()

                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.davyGrey))

                    } else {

                        Button(action: {

                            if isSignUp {

                                authManager.signUp(email: email, password: password, name: name)

                            } else {

                                authManager.loginWithEmailPassword(email: email, password: password)

                            }

                        }) {

                            Text(isSignUp ? "Sign Up" : "Login")

                                .frame(maxWidth: .infinity)

                        }

                        .primaryButtonStyle()

                    }

                    

                    Button(action: {

                        isSignUp.toggle()

                    }) {

                        Text(isSignUp ? "Already have an account? Login" : "Don't have an account? Sign Up")

                            .font(.footnote)

                            .foregroundColor(AppColors.davyGrey)

                    }

                }

                .padding(.horizontal, 30)


                if let error = authManager.error {
                    let errorMessage = error.localizedDescription
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 10)
                        .multilineTextAlignment(.center)
                        .opacity(errorMessage.isEmpty ? 0 : 1) // Fade-in effect when error appears
                        .scaleEffect(errorMessage.isEmpty ? 1 : 1.1) // Subtle scaling effect
                        .animation(.easeInOut(duration: 0.3), value: errorMessage) // Animate changes
                        .transition(.opacity) // Smooth transition for appearing/disappearing error
                }


            }

            .padding(.vertical, 50)

        }

    }

}

struct RoundedTextFieldStyle: TextFieldStyle {

    func _body(configuration: TextField<Self._Label>) -> some View {

        configuration

            .padding()

            .background(AppColors.moonMist.opacity(0.3))

            .cornerRadius(10)

            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)

    }

}

