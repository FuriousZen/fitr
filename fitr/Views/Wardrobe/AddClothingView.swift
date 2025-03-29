import SwiftUI

struct AddClothingView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var authManager: AuthenticationManager
    
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var imageSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var clothingName = ""
    @State private var clothingType: ClothingType = .tShirt
    @State private var clothingColor = ""
    @State private var selectedWeatherTags: Set<WeatherTag> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showActionSheet = false
    @State private var showPhotoGuidance = false
    @State private var isClassifying = false
    @State private var showAIClassificationResults = false
    @State private var aiSuggestedType: ClothingType?
    @State private var aiSuggestedColor: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Image selection
                    VStack(alignment: .center, spacing: 15) {
                        if let selectedImage = selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 250)
                                .cornerRadius(12)
                        } else {
                            ZStack {
                                Rectangle()
                                    .fill(AppColors.moonMist.opacity(0.3))
                                    .frame(height: 250)
                                    .cornerRadius(12)
                                
                                VStack(spacing: 10) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(AppColors.davyGrey)
                                    
                                    Text("Add Clothing Photo")
                                        .font(.headline)
                                        .foregroundColor(AppColors.davyGrey)
                                }
                            }
                        }
                        
                        Button(action: {
                            showActionSheet = true
                        }) {
                            Text(selectedImage == nil ? "Select Image" : "Change Image")
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButtonStyle()
                        .actionSheet(isPresented: $showActionSheet) {
                            ActionSheet(
                                title: Text("Select Photo"),
                                message: Text("Choose a source for your clothing photo"),
                                buttons: [
                                    .default(Text("Camera")) {
                                        self.imageSource = .camera
                                        self.showPhotoGuidance = true
                                    },
                                    .default(Text("Photo Library")) {
                                        self.imageSource = .photoLibrary
                                        self.showImagePicker = true
                                    },
                                    .cancel()
                                ]
                            )
                        }
                        
                        if selectedImage != nil && !isClassifying && !showAIClassificationResults {
                            Button(action: {
                                classifyClothingWithAI()
                            }) {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                    Text("Analyze with AI")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .primaryButtonStyle()
                        }
                        
                        if isClassifying {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                Text("Analyzing clothing...")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.davyGrey)
                            }
                            .padding()
                        }
                        
                        if showAIClassificationResults, let suggestedType = aiSuggestedType, let suggestedColor = aiSuggestedColor {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("AI Analysis Results")
                                    .font(.headline)
                                    .foregroundColor(AppColors.davyGrey)
                                
                                HStack {
                                    Text("Type: \(suggestedType.rawValue)")
                                    Spacer()
                                    Button("Apply") {
                                        clothingType = suggestedType
                                    }
                                    .font(.caption)
                                    .foregroundColor(AppColors.springRain)
                                }
                                
                                HStack {
                                    Text("Color: \(suggestedColor)")
                                    Spacer()
                                    Button("Apply") {
                                        clothingColor = suggestedColor
                                    }
                                    .font(.caption)
                                    .foregroundColor(AppColors.springRain)
                                }
                            }
                            .padding()
                            .background(AppColors.moonMist.opacity(0.3))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.bottom, 10)
                    
                    // Clothing details form
                    Group {
                        Text("Clothing Details")
                            .font(.headline)
                            .foregroundColor(AppColors.davyGrey)
                        
                        TextField("Name", text: $clothingName)
                            .textFieldStyle(RoundedTextFieldStyle())
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type")
                                .font(.subheadline)
                                .foregroundColor(AppColors.davyGrey)
                            
                            Picker("Clothing Type", selection: $clothingType) {
                                ForEach(ClothingType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .padding()
                            .background(AppColors.moonMist.opacity(0.3))
                            .cornerRadius(10)
                        }
                        
                        TextField("Color", text: $clothingColor)
                            .textFieldStyle(RoundedTextFieldStyle())
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weather Tags")
                                .font(.subheadline)
                                .foregroundColor(AppColors.davyGrey)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(WeatherTag.allCases, id: \.self) { tag in
                                        WeatherTagButton(
                                            tag: tag,
                                            isSelected: selectedWeatherTags.contains(tag),
                                            action: {
                                                if selectedWeatherTags.contains(tag) {
                                                    selectedWeatherTags.remove(tag)
                                                } else {
                                                    selectedWeatherTags.insert(tag)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.top, 5)
                    }
                    
                    // Save button
                    Button(action: saveClothingItem) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save Item")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .primaryButtonStyle()
                    .disabled(isLoading || selectedImage == nil || clothingName.isEmpty || clothingColor.isEmpty || selectedWeatherTags.isEmpty)
                    .padding(.top, 10)
                }
                .padding()
            }
            .navigationTitle("Add Clothing")
            .navigationBarItems(leading: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedImage, isPresented: $showImagePicker, sourceType: imageSource)
            }
            .alert(isPresented: $showPhotoGuidance) {
                Alert(
                    title: Text("Photo Guidance"),
                    message: Text("Please lay your clothing flat on a clean, well-lit surface. Make sure the item is fully visible, and avoid any distractions in the background. Take the photo from directly above for the best results!"),
                    primaryButton: .default(Text("Got it!")) {
                        self.showImagePicker = true
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    private func classifyClothingWithAI() {
        guard let image = selectedImage else {
            errorMessage = "Image not available"
            return
        }
        
        isClassifying = true
        showAIClassificationResults = false
        
        // Convert the image to base64 for API call
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            DispatchQueue.main.async {
                self.isClassifying = false
                self.errorMessage = "Failed to process image"
            }
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Call the OpenAI API directly with the base64 image
        callClothingClassificationAPIWithBase64(base64Image: base64Image)
    }

    private func callClothingClassificationAPIWithBase64(base64Image: String) {
        guard let url = URL(string: "\(APIEndpoints.baseURL)\(APIEndpoints.clothingClassificationEndpoint)") else {
            DispatchQueue.main.async {
                self.isClassifying = false
                self.errorMessage = "Invalid API URL"
            }
            return
        }
        
        // Prepare request body with base64 image instead of URL
        let requestBody = ["image_base64": base64Image]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
                self.isClassifying = false
                self.errorMessage = "Failed to prepare request: \(error.localizedDescription)"
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isClassifying = false
                
                if let error = error {
                    self.errorMessage = "Classification failed: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received from classification API"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let typeString = json["type"] as? String,
                           let type = ClothingType.allCases.first(where: { $0.rawValue.lowercased() == typeString.lowercased() }) {
                            self.aiSuggestedType = type
                        }
                        
                        if let color = json["color"] as? String {
                            self.aiSuggestedColor = color
                        }
                        
                        if self.aiSuggestedType != nil || self.aiSuggestedColor != nil {
                            self.showAIClassificationResults = true
                        } else {
                            self.errorMessage = "AI couldn't identify the clothing properly"
                        }
                    }
                } catch {
                    self.errorMessage = "Failed to parse classification response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    private func saveClothingItem() {
        guard let userId = authManager.currentUser?.id, let image = selectedImage else {
            errorMessage = "Missing user ID or image"
            return
        }
        
        if clothingName.isEmpty || clothingColor.isEmpty || selectedWeatherTags.isEmpty {
            errorMessage = "Please fill in all fields and select at least one weather tag"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Upload image to Firebase Storage
        FirebaseService.shared.uploadClothingImage(image: image, userId: userId) { result in
            switch result {
            case .success(let imageURL):
                // Create clothing item
                let clothingItem = ClothingItem(
                    id: UUID().uuidString,
                    userId: userId,
                    imageURL: imageURL,
                    type: self.clothingType,
                    color: self.clothingColor,
                    name: self.clothingName,
                    createdAt: Date(),
                    weatherTags: Array(self.selectedWeatherTags)
                )
                
                // Save to Firestore
                FirebaseService.shared.saveClothingItem(item: clothingItem) { result in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        
                        switch result {
                        case .success:
                            // Close the sheet
                            self.presentationMode.wrappedValue.dismiss()
                        case .failure(let error):
                            self.errorMessage = "Failed to save clothing item: \(error.localizedDescription)"
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Failed to upload image: \(error.localizedDescription)"
                }
            }
        }
    }
}
