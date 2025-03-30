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
            let docRef = db.collection(FirebaseCollections.clothingItems).document(item.id)
            try docRef.setData(from: item)
            completion(.success(item))
        } catch {
            completion(.failure(error))
        }
    }
    
    func getClothingItems(for userId: String, completion: @escaping (Result<[ClothingItem], Error>) -> Void) {
        db.collection(FirebaseCollections.clothingItems)
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
                    let items = try documents.compactMap { try $0.data(as: ClothingItem.self) }
                    completion(.success(items))
                } catch {
                    completion(.failure(error))
                }
            }
    }
    
    func deleteClothingItem(itemId: String, userId: String, imageURL: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Delete from Firestore
        db.collection(FirebaseCollections.clothingItems).document(itemId).delete { error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            // Extract image path from URL and delete from Storage
            if let url = URL(string: imageURL), let imagePath = url.path.components(separatedBy: "clothing_images/").last {
                let storageRef = self.storage.child("clothing_images/\(imagePath)")
                
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
