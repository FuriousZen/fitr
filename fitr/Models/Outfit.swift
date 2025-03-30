//
//  Outfit.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import Foundation

struct Outfit: Identifiable, Codable {
    var id: String
    var userId: String
    var items: [ClothingItem]
    var weather: Weather
    var createdAt: Date
    var description: String
    let vibe: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case items
        case weather
        case createdAt = "created_at"
        case description
        case vibe
    }
}


