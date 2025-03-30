//  AuthenticationManager.swift

//  fitr

//

//  Created by Ryan Nguyen on 3/29/25.

//
// In AuthenticationManager.swift

import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

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

            isLoading = true
            
            fetchUserData(userId: user.uid) { success in
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isAuthenticated = success
                    
                    if !success {
                        try? Auth.auth().signOut()
                        self.isAuthenticated = false
                        self.currentUser = nil
                    }
                }
            }
        } else {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }

    func loginWithEmailPassword(email: String, password: String) {
        isLoading = true
        error = nil
        
        Auth.auth().signIn(withEmail: email, password: password) { authResult, error in
            self.isLoading = false
            
            if let error = error as NSError? {
                if error.domain == AuthErrorDomain {
                    switch error.code {
                    case AuthErrorCode.invalidCredential.rawValue,
                         AuthErrorCode.wrongPassword.rawValue,
                         AuthErrorCode.userNotFound.rawValue,
                         AuthErrorCode.invalidEmail.rawValue:
                        self.error = NSError(
                            domain: "app.fitr",
                            code: error.code,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid email or password"]
                        )
                    default:
                        self.error = error
                    }
                }
                return
            }
            
            if let authResult = authResult {
                self.fetchUserData(userId: authResult.user.uid) { success in
                    DispatchQueue.main.async {
                        self.isAuthenticated = success
                    }
                }
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
            DispatchQueue.main.async {
                self.isAuthenticated = false
                self.currentUser = nil
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
    
    private func fetchUserData(userId: String, completion: @escaping (Bool) -> Void = {_ in}) {
        let db = Firestore.firestore()
        
        db.collection(FirebaseCollections.users).document(userId).getDocument { document, error in
            if let error = error {
                self.error = error
                completion(false)
                return
            }
            
            if let document = document, document.exists {
                do {
                    self.currentUser = try document.data(as: User.self)
                    print("fetched user data successful!", self.currentUser)
                    completion(true)
                } catch {
                    self.error = error
                    completion(false)
                }
            } else {
                completion(false)
            }
        }
    }
}
