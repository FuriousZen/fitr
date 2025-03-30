//
//  FirebaseService.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import Firebase
import FirebaseFirestore
import FirebaseStorage
import UIKit

class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage().reference()
    
    // MARK: - Clothing Items
    
    func uploadClothingImage(image: UIImage, userId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            completion(.failure(NSError(domain: "FirebaseService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])))
            return
        }
        
        let imageName = UUID().uuidString
        let imageRef = storage.child("clothing_images/\(userId)/\(imageName).jpg")
        
        imageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            imageRef.downloadURL { url, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                if let url = url {
                    completion(.success(url.absoluteString))
                } else {
                    completion(.failure(NSError(domain: "FirebaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"])))
                }
            }
        }
    }
    
    func saveClothingItem(item: ClothingItem, completion: @escaping (Result<ClothingItem, Error>) -> Void) {
        do {
            let docRef = db.collection("users").document(item.userId).collection("clothingItems").document(item.id)
            try docRef.setData(from: item)
            completion(.success(item))
        } catch {
            completion(.failure(error))
        }
    }
    
    func getClothingItems(for userId: String, completion: @escaping (Result<[ClothingItem], Error>) -> Void) {
        db.collection("users").document(userId).collection("clothingItems")
            .order(by: "created_at", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let items = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: ClothingItem.self)
                } ?? []
                completion(.success(items))
            }
    }
    
    func getCleanClothingItems(for userId: String, completion: @escaping (Result<[ClothingItem], Error>) -> Void) {
        db.collection("users").document(userId).collection("clothingItems")
            .whereField("dirty", isEqualTo: false)
            .order(by: "created_at", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let items = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: ClothingItem.self)
                } ?? []
                completion(.success(items))
            }
    }
    
    func getLaundryItems(for userId: String, completion: @escaping (Result<[ClothingItem], Error>) -> Void) {
        db.collection("users").document(userId).collection("clothingItems")
            .whereField("dirty", isEqualTo: true)
            .order(by: "created_at", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let items = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: ClothingItem.self)
                } ?? []
                completion(.success(items))
            }
    }
    
    func deleteClothingItem(item: ClothingItem, completion: @escaping (Result<Void, Error>) -> Void) {
        // Delete from Firestore
        db.collection("users").document(item.userId).collection("clothingItems").document(item.id).delete { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Delete image from Storage if URL exists
            if !item.imageURL.isEmpty {
                let storageRef = self.storage.storage.reference(forURL: item.imageURL)
                storageRef.delete { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            } else {
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Laundry Management
    
    func markItemAsDirty(item: ClothingItem, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            // Create a copy with updated dirty status
            var dirtyItem = item
            dirtyItem.dirty = true
            
            // Update the item in the clothingItems collection
            let itemRef = db.collection("users").document(item.userId)
                .collection("clothingItems").document(item.id)
            
            try itemRef.setData(from: dirtyItem)
            
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    func washItems(items: [ClothingItem], completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let batch = db.batch()
            
            for var item in items {
                item.dirty = false
                
                // Update the item in the clothingItems collection
                let itemRef = db.collection("users").document(item.userId)
                    .collection("clothingItems").document(item.id)
                
                try batch.setData(from: item, forDocument: itemRef)
            }
            
            batch.commit { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Outfits
    
    func saveOutfit(outfit: Outfit, completion: @escaping (Result<Outfit, Error>) -> Void) {
        do {
            let docRef = db.collection(FirebaseCollections.outfits).document(outfit.id)
            try docRef.setData(from: outfit)
            completion(.success(outfit))
        } catch {
            completion(.failure(error))
        }
    }
    
    func getOutfits(for userId: String, completion: @escaping (Result<[Outfit], Error>) -> Void) {
        db.collection(FirebaseCollections.outfits)
            .whereField("user_id", isEqualTo: userId)
            .order(by: "created_at", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                do {
                    let outfits = try documents.compactMap { try $0.data(as: Outfit.self) }
                    completion(.success(outfits))
                } catch {
                    completion(.failure(error))
                }
            }
    }
    
    func updateUserLocation(userId: String, location: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let db = Firestore.firestore()
        db.collection("users").document(userId).updateData([
            "location": location
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}
