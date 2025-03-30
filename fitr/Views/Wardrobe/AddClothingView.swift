import SwiftUI
import FirebaseStorage
import FirebaseVertexAI

struct AddClothingView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var authManager: AuthenticationManager
    
    // MARK: - State Properties
    
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var imageSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var clothingName = ""
    @State private var clothingType: ClothingType = .tShirt
    @State private var clothingColor = ""
    @State private var selectedWeatherTags: Set<WeatherTag> = []
    @State private var selectedStyleTags: Set<StyleTag> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showActionSheet = false
    @State private var showPhotoGuidance = false
    @State private var isClassifying = false
    @State private var showAIClassificationResults = false
    @State private var aiSuggestedType: ClothingType?
    @State private var aiSuggestedColor: String?
    @State private var aiSuggestedStyleTags: [StyleTag]?
    @State private var aiSuggestedWeatherTags: [WeatherTag]?
    @State private var isUploading = false
    @State private var uploadTask: StorageUploadTask?
    
    // Toast state
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isSuccessToast = true
    
    // Vertex AI classifier
    private let clothingClassifier = ClothingClassifier()
    
    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        imageSelectionSection
                        clothingDetailsForm
                        errorMessageSection
                        saveButton
                    }
                    .padding()
                }
                
                // Loading overlay
                if isLoading {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Uploading...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationTitle("Add Clothing")
            .navigationBarItems(leading: cancelButton)
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedImage, isPresented: $showImagePicker, sourceType: imageSource)
                    .onDisappear(perform: resetAIAnalysis)
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
            .onDisappear {
                // Cancel any ongoing upload when view disappears
                uploadTask?.cancel()
            }
            .toast(isPresented: $showToast, message: toastMessage, isSuccess: isSuccessToast)
        }
    }
    
    // MARK: - View Components
    private var imageSelectionSection: some View {
        VStack(alignment: .center, spacing: 15) {
            if let selectedImage = selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 250)
                    .cornerRadius(12)
            } else {
                placeholderImage
            }
            
            selectImageButton
            aiAnalysisSection
        }
        .padding(.bottom, 10)
    }
    
    private var placeholderImage: some View {
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
    
    private var selectImageButton: some View {
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
    }
    
    private var aiAnalysisSection: some View {
        Group {
            if selectedImage != nil && !isClassifying && !showAIClassificationResults {
                Button(action: classifyClothingWithAI) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Analyze with AI")
                    }
                    .frame(maxWidth: .infinity)
                }
                .primaryButtonStyle()
                .disabled(isClassifying)
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
            
            if showAIClassificationResults {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("AI Analysis Results")
                            .font(.headline)
                            .foregroundColor(AppColors.davyGrey)
                    }
                    
                    if let suggestedType = aiSuggestedType {
                        Text("Type: \(suggestedType.rawValue)")
                            .lineLimit(1)
                    }
                    
                    if let suggestedColor = aiSuggestedColor {
                        Text("Color: \(suggestedColor)")
                            .lineLimit(1)
                    }
                    
                    if let suggestedWeatherTags = aiSuggestedWeatherTags, !suggestedWeatherTags.isEmpty {
                        Text("Weather: \(suggestedWeatherTags.map { $0.rawValue }.joined(separator: ", "))")
                            .lineLimit(2)
                    }
                    
                    if let suggestedStyleTags = aiSuggestedStyleTags, !suggestedStyleTags.isEmpty {
                        Text("Style: \(suggestedStyleTags.map { $0.rawValue }.joined(separator: ", "))")
                            .lineLimit(2)
                    }
                    
                    Button(action: applyAllAISuggestions) {
                        Text("Apply All Suggestions")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.springRain)
                    .padding(.top, 8)
                }
                .padding()
                .background(AppColors.moonMist.opacity(0.3))
                .cornerRadius(10)
            }
        }
    }
    private func applyAllAISuggestions() {
        // Apply type suggestion
        if let suggestedType = aiSuggestedType {
            clothingType = suggestedType
        }
        
        // Apply color suggestion
        if let suggestedColor = aiSuggestedColor {
            clothingColor = suggestedColor
        }
        if let suggestedColor = aiSuggestedColor, let suggestedType = aiSuggestedType {
            clothingName = "\(suggestedColor) \(suggestedType)"
           }
        // Apply weather tags suggestions
        if let suggestedWeatherTags = aiSuggestedWeatherTags, !suggestedWeatherTags.isEmpty {
            selectedWeatherTags = Set(suggestedWeatherTags)
        }
        
        // Apply style tags suggestions
        if let suggestedStyleTags = aiSuggestedStyleTags, !suggestedStyleTags.isEmpty {
            selectedStyleTags = Set(suggestedStyleTags)
        }
        
        // Show success toast
        toastMessage = "All suggestions applied!"
        isSuccessToast = true
        showToast = true
        
        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                self.showToast = false
            }
        }
    }
    
    private var clothingDetailsForm: some View {
        Group {
            Text("Clothing Details")
                .font(.headline)
                .foregroundColor(AppColors.davyGrey)
            
            TextField("Name", text: $clothingName)
                .textFieldStyle(RoundedTextFieldStyle())
            
            clothingTypePicker
            colorTextField
            weatherTagsSection
            styleTagsSection
        }
    }
    
    private var clothingTypePicker: some View {
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
    }
    
    private var colorTextField: some View {
        TextField("Color", text: $clothingColor)
            .textFieldStyle(RoundedTextFieldStyle())
    }
    
    private var weatherTagsSection: some View {
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
    
    private var styleTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style Tags")
                .font(.subheadline)
                .foregroundColor(AppColors.davyGrey)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StyleTag.allCases, id: \.self) { tag in
                        StyleTagButton(
                            tag: tag,
                            isSelected: selectedStyleTags.contains(tag),
                            action: {
                                if selectedStyleTags.contains(tag) {
                                    selectedStyleTags.remove(tag)
                                } else {
                                    selectedStyleTags.insert(tag)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 5)
            }
        }
    }
    
    private var errorMessageSection: some View {
        Group {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 5)
            }
        }
    }
    
    private var saveButton: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            saveClothingItem()
        }) {
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
        .disabled(shouldDisableSaveButton)
        .padding(.top, 10)
    }
    
    private var cancelButton: some View {
        Button("Cancel") {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private var shouldDisableSaveButton: Bool {
        isLoading || isUploading || selectedImage == nil || clothingName.isEmpty || clothingColor.isEmpty || selectedWeatherTags.isEmpty || selectedStyleTags.isEmpty
    }
    
    // MARK: - Private Methods
    private func resetAIAnalysis() {
        if selectedImage != nil {
            showAIClassificationResults = false
            aiSuggestedType = nil
            aiSuggestedColor = nil
            aiSuggestedStyleTags = nil
            aiSuggestedWeatherTags = nil
        }
    }
    
    private func classifyClothingWithAI() {
        guard let image = selectedImage, !isClassifying else {
            if selectedImage == nil {
                errorMessage = "Image not available"
            }
            return
        }
        
        isClassifying = true
        showAIClassificationResults = false
        
        clothingClassifier.classifyClothing(image) { result in
            DispatchQueue.main.async {
                self.isClassifying = false
                
                switch result {
                case .success(let classification):
                    // Process the classification result
                    if let type = ClothingType.allCases.first(where: { $0.rawValue.lowercased() == classification.type.lowercased() }) {
                        self.aiSuggestedType = type
                    }
                    
                    self.aiSuggestedColor = classification.color
                    
                    let suggestedStyles = classification.styleTags.compactMap { styleString in
                        return StyleTag.allCases.first { $0.rawValue.lowercased() == styleString.lowercased() }
                    }
                    
                    if !suggestedStyles.isEmpty {
                        self.aiSuggestedStyleTags = suggestedStyles
                    }
                    
                    // Update weather tags suggestion
                    let suggestedWeatherTags = classification.weatherTags.compactMap { weatherString in
                        return WeatherTag.allCases.first { $0.rawValue.lowercased() == weatherString.lowercased() }
                    }
                    
                    if !suggestedWeatherTags.isEmpty {
                        self.aiSuggestedWeatherTags = suggestedWeatherTags
                    }
                    
                    if self.aiSuggestedType != nil || self.aiSuggestedColor != nil ||
                       self.aiSuggestedStyleTags != nil || self.aiSuggestedWeatherTags != nil {
                        self.showAIClassificationResults = true
                        
                        // Show success toast for AI analysis
                        self.toastMessage = "AI analysis complete!"
                        self.isSuccessToast = true
                        self.showToast = true
                        
                        // Hide toast after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                self.showToast = false
                            }
                        }
                    } else {
                        self.errorMessage = "AI couldn't identify the clothing properly"
                        
                        // Show error toast
                        self.toastMessage = "AI analysis failed"
                        self.isSuccessToast = false
                        self.showToast = true
                        
                        // Hide toast after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                self.showToast = false
                            }
                        }
                    }
                    
                case .failure(let error):
                    self.errorMessage = "Classification failed: \(error.localizedDescription)"
                    
                    // Show error toast
                    self.toastMessage = "AI analysis failed"
                    self.isSuccessToast = false
                    self.showToast = true
                    
                    // Hide toast after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.showToast = false
                        }
                    }
                }
            }
        }
    }
    
    private func saveClothingItem() {
        guard !isUploading else {
            print("Upload already in progress - ignoring duplicate call")
            return
        }
        
        guard let userId = authManager.currentUser?.id, let image = selectedImage else {
            errorMessage = "Missing user ID or image"
            return
        }
        
        if clothingName.isEmpty || clothingColor.isEmpty || selectedWeatherTags.isEmpty || selectedStyleTags.isEmpty {
            errorMessage = "Please fill in all fields and select at least one weather tag and style tag"
            return
        }
        
        isLoading = true
        isUploading = true
        errorMessage = nil
        
        // Set a timeout for the upload
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if self.isUploading {
                self.isUploading = false
                self.isLoading = false
                self.errorMessage = "Upload timed out"
                self.uploadTask?.cancel()
                
                // Show timeout toast
                self.toastMessage = "Upload timed out"
                self.isSuccessToast = false
                self.showToast = true
                
                // Hide toast after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        self.showToast = false
                    }
                }
            }
        }
        
        // Upload image to Firebase Storage
        FirebaseService.shared.uploadClothingImage(image: image, userId: userId) { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let imageURL):
                    createAndSaveClothingItem(userId: userId, imageURL: imageURL)
                case .failure(let error):
                    handleUploadError(error)
                }
            }
        }
    }
    
    private func createAndSaveClothingItem(userId: String, imageURL: String) {
        let clothingItem = ClothingItem(
            id: UUID().uuidString,
            userId: userId,
            imageURL: imageURL,
            type: self.clothingType,
            color: self.clothingColor,
            name: self.clothingName,
            createdAt: Date(),
            weatherTags: Array(self.selectedWeatherTags),
            styleTags: Array(self.selectedStyleTags)
        )
        
        FirebaseService.shared.saveClothingItem(item: clothingItem) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                self.isUploading = false
                
                switch result {
                case .success:
                    // Show success toast
                    self.toastMessage = "Item saved successfully!"
                    self.isSuccessToast = true
                    self.showToast = true
                    
                    // Hide toast after 2 seconds and dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            self.showToast = false
                        }
                        // Close the sheet
                        self.presentationMode.wrappedValue.dismiss()
                        
                        NotificationCenter.default.post(
                            name: Notification.Name("WardrobeUpdated"),
                            object: nil,
                            userInfo: ["operation": "add"]
                        )
                    }
                    
                case .failure(let error):
                    self.errorMessage = "Failed to save clothing item: \(error.localizedDescription)"
                    
                    // Show error toast
                    self.toastMessage = "Failed to save item"
                    self.isSuccessToast = false
                    self.showToast = true
                    
                    // Hide toast after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            self.showToast = false
                        }
                    }
                }
            }
        }
    }
    
    private func handleUploadError(_ error: Error) {
        self.isLoading = false
        self.isUploading = false
        self.errorMessage = "Failed to upload image: \(error.localizedDescription)"
        
        // Show error toast
        self.toastMessage = "Failed to upload image"
        self.isSuccessToast = false
        self.showToast = true
        
        // Hide toast after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                self.showToast = false
            }
        }
        
        if let storageError = error as? StorageError {
            switch storageError {
            case .cancelled:
                print("Upload was cancelled")
            default:
                print("Storage error occurred: \(storageError.localizedDescription)")
            }
        }
    }
}

// MARK: - StyleTagButton Component
struct StyleTagButton: View {
    let tag: StyleTag
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(tag.rawValue.capitalized)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(isSelected ? styleColor(for: tag) : AppColors.moonMist.opacity(0.3))
                )
                .foregroundColor(isSelected ? .white : AppColors.davyGrey)
        }
    }
    
    private func styleColor(for tag: StyleTag) -> Color {
        switch tag {
        case .casual, .everyday, .comfortable:
            return AppColors.springRain
        case .formal, .business, .elegant:
            return Color.blue
        case .athletic, .sporty:
            return Color.orange
        case .trendy, .stylish:
            return Color.purple
        case .warm:
            return AppColors.lightPink
        }
    }
}

struct WeatherTagButton: View {
    let tag: WeatherTag
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(tag.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(isSelected ? AppColors.lightPink : AppColors.moonMist.opacity(0.5))
                .foregroundColor(isSelected ? .white : AppColors.davyGrey)
                .cornerRadius(20)
        }
    }
}
