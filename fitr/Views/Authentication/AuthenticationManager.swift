//
//  AuthenticationManager.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import SwiftUI
import Auth0
import Firebase
import FirebaseAuth

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var error: Error?
    
    init() {
        checkAuthenticationState()
    }
    
    func checkAuthenticationState() {
        if let user = Auth.auth().currentUser {
            self.isAuthenticated = true
            fetchUserData(userId: user.uid)
        } else {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
    
    func loginWithAuth0() {
        isLoading = true
        
        Auth0
            .webAuth()
            .scope("openid profile email")
            .audience("https://your-api-identifier/")
            .start { result in
                self.isLoading = false
                
                switch result {
                case .success(let credentials):
                    // Get user info from Auth0
                    Auth0
                        .authentication()
                        .userInfo(withAccessToken: credentials.accessToken)
                        .start { result in
                            switch result {
                            case .success(let profile):
                                // Create Firebase credential
                                let credential = OAuthProvider.credential(
                                    providerID: AuthProviderID.email,
                                    idToken: credentials.idToken,
                                    accessToken: credentials.accessToken
                                )
                                
                                // Sign in to Firebase
                                Auth.auth().signIn(with: credential) { authResult, error in
                                    if let error = error {
                                        self.error = error
                                        return
                                    }
                                    
                                    if let authResult = authResult {
                                        // Create or update user in Firestore
                                        let user = User(
                                            id: authResult.user.uid,
                                            email: profile.email ?? "",
                                            name: profile.name ?? "",
                                            profileImageURL: profile.picture?.absoluteString
                                        )
                                        
                                        self.saveUserToFirestore(user: user)
                                    }
                                }
                            case .failure(let error):
                                self.error = error
                            }
                        }
                case .failure(let error):
                    self.error = error
                }
            }
    }
    
    func loginWithApple() {
        // Implementation for Apple Sign In
        // This would use ASAuthorizationAppleIDProvider and ASAuthorizationAppleIDRequest
    }
    
    func loginWithEmailPassword(email: String, password: String) {
        isLoading = true
        
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            self.isLoading = false
            
            if let error = error {
                self.error = error
                return
            }
            
            if let authResult = authResult {
                self.fetchUserData(userId: authResult.user.uid)
            }
        }
    }
    
    func signUp(email: String, password: String, name: String) {
        isLoading = true
        
        Auth.auth().createUser(withEmail: email, password: password) { authResult, error in
            self.isLoading = false
            
            if let error = error {
                self.error = error
                return
            }
            
            if let authResult = authResult {
                let user = User(
                    id: authResult.user.uid,
                    email: email,
                    name: name,
                    profileImageURL: nil
                )
                
                self.saveUserToFirestore(user: user)
            }
        }
    }
    
    func logout() {
        do {
            try Auth.auth().signOut()
            
            // Also clear Auth0 session
            Auth0
                .webAuth()
                .clearSession { _ in
                    DispatchQueue.main.async {
                        self.isAuthenticated = false
                        self.currentUser = nil
                    }
                }
        } catch {
            self.error = error
        }
    }
    
    private func saveUserToFirestore(user: User) {
        let db = Firestore.firestore()
        
        do {
            try db.collection(FirebaseCollections.users).document(user.id).setData(from: user)
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            self.error = error
        }
    }
    
    private func fetchUserData(userId: String) {
        let db = Firestore.firestore()
        
        db.collection(FirebaseCollections.users).document(userId).getDocument { document, error in
            if let error = error {
                self.error = error
                return
            }
            
            if let document = document, document.exists {
                do {
                    self.currentUser = try document.data(as: User.self)
                } catch {
                    self.error = error
                }
            }
        }
    }
}
