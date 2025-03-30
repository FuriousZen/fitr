//  OutfitService.swift
//  fitr
//
//  Created by Ryan Nguyen on 3/29/25.
//

import Foundation
import FirebaseVertexAI

class OutfitService {
    static let shared = OutfitService()
    private let vertexAI = VertexAI.vertexAI()
    private var generativeModel: GenerativeModel?
    
    init() {
        setupVertexAIModel()
    }
    
    private func setupVertexAIModel() {
        // Define a response schema that returns just the item IDs and description
        let outfitSchema = Schema.object(
            properties: [
                "selectedItemIds": Schema.array(
                    items: .string()
                ),
                "description": Schema.string()
            ]
        )
        
        // Initialize the generative model with the schema
        generativeModel = vertexAI.generativeModel(
            modelName: "gemini-1.5-pro",
            generationConfig: GenerationConfig(
                temperature: 0.7,
                responseMIMEType: "application/json",
                responseSchema: outfitSchema
            )
        )
    }
    
    func getOutfitRecommendation(userId: String, vibe: String, weather: Weather, clothingItems: [ClothingItem], completion: @escaping (Result<Outfit, Error>) -> Void) {
        // Filter out dirty items
        let cleanItems = clothingItems.filter { !$0.dirty }
        
        if cleanItems.isEmpty {
            completion(.failure(NSError(domain: "OutfitService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No clean clothing items available"])))
            return
        }
        if cleanItems.count == 1 {
            completion(.failure(NSError(domain: "OutfitService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Not enough clean clothing items to create an outfit"])))
            return
        }
        
        // Generate outfit with AI
        generateOutfitWithAI(userId: userId, vibe: vibe, weather: weather, clothingItems: cleanItems) { result in
            completion(result)
        }
    }
    private func generateOutfitWithAI(userId: String, vibe: String, weather: Weather, clothingItems: [ClothingItem], completion: @escaping (Result<Outfit, Error>) -> Void) {
        guard let model = generativeModel else {
            completion(.failure(NSError(domain: "OutfitService", code: 3, userInfo: [NSLocalizedDescriptionKey: "AI model not initialized"])))
            return
        }
        
        // Create a structured prompt for the AI
        let content = createStructuredPrompt(vibe: vibe, weather: weather, clothingItems: clothingItems)
        
        Task {
            do {
                let response = try await model.generateContent(content)
                
                if let jsonString = response.text,
                   let jsonData = jsonString.data(using: .utf8) {
                    
                    // Parse the AI response
                    let decoder = JSONDecoder()
                    let aiResponse = try decoder.decode(OutfitAIResponse.self, from: jsonData)
                    print("AI RES", aiResponse)
                    if aiResponse.selectedItemIds.isEmpty {
                        throw NSError(domain: "OutfitService", code: 5, userInfo: [NSLocalizedDescriptionKey: "No suitable outfit could be created with current wardrobe"])
                    }
                    var selectedItemIds = Set(aiResponse.selectedItemIds)
                    
                    // Ensure only one item per category is included
                    var selectedTypes: [ClothingType: ClothingItem] = [:]
                    for item in clothingItems where selectedItemIds.contains(item.id) {
                        if selectedTypes[item.type] == nil {
                            selectedTypes[item.type] = item
                        }
                    }
                    let mutuallyExclusiveTypes: [[ClothingType]] = [
                        [.tShirt, .shirt], // One top
                        [.pants, .shorts]  // One bottom
                    ]
                    for category in mutuallyExclusiveTypes {
                        for item in clothingItems where category.contains(item.type) {
                            if selectedTypes.keys.contains(where: { category.contains($0) }) {
                                continue
                            }
                            selectedTypes[item.type] = item
                        }
                    }

                    // Add selected items to the set
                    selectedItemIds = Set(selectedTypes.values.map { $0.id })
                    for (_, item) in selectedTypes {
                        selectedItemIds.insert(item.id)
                    }
                    let selectedItems = clothingItems.filter { selectedItemIds.contains($0.id) }
                                        
                    // Create the outfit
                    let outfit = Outfit(
                        id: UUID().uuidString,
                        userId: userId,
                        items: selectedItems,
                        weather: weather,
                        createdAt: Date(),
                        description: aiResponse.description,
                        vibe: vibe
                    )
                    
                    DispatchQueue.main.async {
                        completion(.success(outfit))
                    }
                } else {
                    throw NSError(domain: "OutfitService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid AI response format"])
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func createStructuredPrompt(vibe: String, weather: Weather, clothingItems: [ClothingItem]) -> String {
        // Create a minimal representation of the clothing items
        let itemsJson = clothingItems.map { item -> [String: Any] in
            return [
                "id": item.id,
                "type": item.type.rawValue,
                "color": item.color,
                "name": item.name,
                "weatherTags": item.weatherTags.map { $0.rawValue },
                "styleTags": item.styleTags.map { $0.rawValue }
            ]
        }
        
        // Convert to JSON string - use compact printing to save tokens
        let itemsJsonData = try? JSONSerialization.data(withJSONObject: itemsJson, options: [])
        let itemsJsonString = itemsJsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        

        let weatherJson: [String: Any] = [
            "temperature": weather.temperature,
            "condition": weather.condition.rawValue,
            "humidity": weather.humidity,
            "windSpeed": weather.windSpeed,
            "location": weather.location
        ]
        
        let weatherJsonData = try? JSONSerialization.data(withJSONObject: weatherJson, options: [.prettyPrinted])
        let weatherJsonString = weatherJsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        // Create a concise prompt
        return """
        As a stylist, create an outfit for \(vibe) vibe in \(weatherJsonString) weather.
        
        Clothing items:
        \(itemsJsonString)
        
        Rules:
        - Cold (<10°C): include layers
        - Hot (>25°C): light clothing
        - Rainy: water-resistant items
        - Match the \(vibe) vibe
        - Only use items from the list
        - use common clothing combinations for fashion
        - Do not select multiple items of the same type (e.g., no two pants or two shirts) unless its reasonably fashionable such as accessories
        - If the outfit can't be realistically generated or only one item fits, return an empty selectedItemIds array.


        Return JSON with:
        {"selectedItemIds": [item IDs array], "description": "outfit description"}
        """
    }
}

// Simple struct to decode the AI response
struct OutfitAIResponse: Codable {
    let selectedItemIds: [String]
    let description: String
}
