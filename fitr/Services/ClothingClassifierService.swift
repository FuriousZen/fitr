import FirebaseVertexAI
import UIKit

class ClothingClassifier {
    private let vertexAI = VertexAI.vertexAI()
    private var generativeModel: GenerativeModel?
    
    init() {
        // Define the response schema for clothing classification
        let clothingSchema = Schema.object(
            properties: [
                "type": Schema.enumeration(values: ClothingType.allCases.map { $0.rawValue }),
                "color": Schema.string(),
                "weatherTags": Schema.array(
                    items: .enumeration(values: WeatherTag.allCases.map { $0.rawValue })
                ),
                "styleTags": Schema.array(
                    items: .enumeration(values: StyleTag.allCases.map { $0.rawValue })
                )
            ]
        )
        
        // Initialize the generative model with the schema
        generativeModel = vertexAI.generativeModel(
            modelName: "gemini-2.0-flash",
            generationConfig: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: clothingSchema
            )
        )
    }
    
    func classifyClothing(_ image: UIImage, completion: @escaping (Result<ClothingClassificationResult, Error>) -> Void) {
        Task {
            do {
                guard let model = generativeModel else {
                    throw NSError(domain: "ClothingClassifier", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not initialized"])
                }
                
                // Create the prompt text
                let promptText = "Classify this clothing item. Identify the type of clothing, its color, appropriate weather conditions, and style categories."
                
                // Generate content using the model with image and text
                let response = try await model.generateContent(image, promptText)
                
                // Parse the JSON response
                if let jsonString = response.text,
                   let jsonData = jsonString.data(using: .utf8) {
                    let decoder = JSONDecoder()
                    let classification = try decoder.decode(ClothingClassificationResult.self, from: jsonData)
                    
                    DispatchQueue.main.async {
                        completion(.success(classification))
                    }
                } else {
                    throw NSError(domain: "ClothingClassifier", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

// Model to decode the AI response
struct ClothingClassificationResult: Codable {
    let type: String
    let color: String
    let weatherTags: [String]
    let styleTags: [String]
}
