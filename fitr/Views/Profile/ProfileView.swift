//
//  ProfileView.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI
import Kingfisher

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showingLogoutAlert = false
    @State private var showingEditProfile = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 25) {
                    VStack(spacing: 15) {
                        if let profileImageURL = authManager.currentUser?.profileImageURL,
                           let url = URL(string: profileImageURL) {
                            KFImage(url)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .foregroundColor(AppColors.davyGrey.opacity(0.7))
                        }
                        
                        Text(authManager.currentUser?.name ?? "User")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.davyGrey)
                        
                        Text(authManager.currentUser?.email ?? "")
                            .font(.subheadline)
                            .foregroundColor(AppColors.davyGrey.opacity(0.7))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(AppColors.peachSnaps.opacity(0.2))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    VStack(spacing: 5) {
                        SettingsSectionHeader(title: "Account")
                        
                        SettingsItem(icon: "person.fill", title: "Edit Profile") {
                            showingEditProfile = true
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(spacing: 5) {
                        SettingsSectionHeader(title: "App")
                        
                        SettingsItem(icon: "info.circle.fill", title: "About") {
                            showingAbout = true
                        }
                    }
                    .padding(.horizontal)
                    
                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                                .foregroundColor(.red)
                            
                            Text("Logout")
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .alert(isPresented: $showingLogoutAlert) {
                        Alert(
                            title: Text("Logout"),
                            message: Text("Are you sure you want to logout?"),
                            primaryButton: .destructive(Text("Logout")) {
                                authManager.logout()
                            },
                            secondaryButton: .cancel()
                        )
                    }
                }
                .padding(.vertical)
            }
            .background(AppColors.moonMist.opacity(0.1).ignoresSafeArea())
            .navigationTitle("Profile")
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
                    .environmentObject(authManager)
            }
            .alert("About fitr", isPresented: $showingAbout) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(aboutText)
            }
        }
    }
    
    private var aboutText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let source = BackendService.shared.isConfigured
            ? "Recommendations come from the fitr backend (CLIP + Gemini)."
            : "Recommendations come from Gemini on this device."
        return "Version \(version) (\(build)).\n\(source)"
    }
}

/// Edits the fields the profile document actually holds. The email is shown
/// but not editable here, since changing it means re-verifying with Firebase
/// Auth as well as rewriting the profile.
struct EditProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.presentationMode) var presentationMode
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Name")) {
                    TextField("Name", text: $name)
                        .disabled(isSaving)
                }
                
                Section(header: Text("Email")) {
                    Text(authManager.currentUser?.email ?? "")
                        .foregroundColor(.secondary)
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(isSaving ? "Saving..." : "Save") {
                    save()
                }
                .disabled(isSaving || trimmedName.isEmpty || trimmedName == authManager.currentUser?.name)
            )
            .onAppear {
                name = authManager.currentUser?.name ?? ""
            }
        }
    }
    
    private func save() {
        isSaving = true
        errorMessage = nil
        authManager.updateProfile(name: trimmedName) { result in
            isSaving = false
            switch result {
            case .success:
                presentationMode.wrappedValue.dismiss()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.davyGrey)
            
            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 5)
    }
}

struct SettingsItem: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.davyGrey)
                    .frame(width: 30)
                
                Text(title)
                    .foregroundColor(AppColors.davyGrey)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.davyGrey.opacity(0.5))
            }
            .padding()
            .background(AppColors.moonMist.opacity(0.2))
            .cornerRadius(10)
        }
        .padding(.vertical, 3)
    }
}
