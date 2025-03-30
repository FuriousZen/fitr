import SwiftUI
import Firebase
import FirebaseAuth

struct WardrobeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
    @State private var clothingItems: [ClothingItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddClothingSheet = false
    @State private var selectedFilter: ClothingType?
    @State private var hasLoadedInitialData = false
    @State private var gridColumns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 12)
    ]
    
    // Toast state
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isSuccessToast = true
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundLayer
                contentLayer
            }
            .navigationTitle("My Wardrobe")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showAddClothingSheet) {
                AddClothingView()
                    .environmentObject(authManager)
            }
            .onAppear {
                if !hasLoadedInitialData || clothingItems.isEmpty {
                    loadClothingItems()
                    hasLoadedInitialData = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WardrobeUpdated"))) { notification in
                handleWardrobeUpdate(notification)
            }
            .toast(isPresented: $showToast, message: toastMessage, isSuccess: isSuccessToast)
        }
    }
    
    // MARK: - View Components
    
    private var backgroundLayer: some View {
        AppColors.peachSnaps.opacity(0.2).ignoresSafeArea()
    }
    
    private var contentLayer: some View {
        VStack(spacing: 0) {
            filterOptionsSection
            
            if isLoading {
                loadingView
            } else if clothingItems.isEmpty {
                emptyStateView
            } else {
                clothingGridView
            }
            
            errorView
        }
    }
    
    private var filterOptionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterButton(
                    title: "All",
                    isSelected: selectedFilter == nil,
                    action: { selectedFilter = nil }
                )
                
                ForEach(ClothingType.allCases, id: \.self) { type in
                    FilterButton(
                        title: type.rawValue,
                        isSelected: selectedFilter == type,
                        action: { selectedFilter = type }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.white.opacity(0.5))
    }
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.davyGrey))
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "tshirt")
                    .font(.system(size: 60))
                    .foregroundColor(AppColors.davyGrey.opacity(0.6))
                
                Text("Your wardrobe is empty")
                    .font(.headline)
                    .foregroundColor(AppColors.davyGrey)
                
                Text("Add some clothing items to get started")
                    .font(.subheadline)
                    .foregroundColor(AppColors.davyGrey.opacity(0.8))
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    showAddClothingSheet = true
                }) {
                    Text("Add Clothing")
                        .padding(.horizontal, 30)
                }
                .primaryButtonStyle()
            }
            .padding()
            Spacer()
        }
    }
    
    private var clothingGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(filteredClothingItems) { item in
                    ClothingItemView(item: item, onDelete: {
                        deleteClothingItem(item)
                    }, onMarkDirty: {
                        markItemAsDirty(item)
                    })
                    .frame(height: 180)
                }
            }
            .padding(12)
        }
    }
    
    private var errorView: some View {
        Group {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                showAddClothingSheet = true
            }) {
                Image(systemName: "plus")
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: toggleGridLayout) {
                // Check the current grid size to determine which icon to show
                if case let .adaptive(min, _) = gridColumns.first?.size, min == 120 {
                    Image(systemName: "square.grid.3x3")
                } else {
                    Image(systemName: "square.grid.2x2")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    var filteredClothingItems: [ClothingItem] {
        if let filter = selectedFilter {
            return clothingItems.filter { $0.type == filter }
        } else {
            return clothingItems
        }
    }
    
    private func toggleGridLayout() {
        // Check if we're currently using the larger grid
        if case let .adaptive(min, max) = gridColumns.first?.size, min == 120 {
            // Switch to compact grid
            gridColumns = [GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 10)]
        } else {
            // Switch to standard grid
            gridColumns = [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 12)]
        }
    }
    
    private func handleWardrobeUpdate(_ notification: Notification) {
        // Get the operation type from the notification
        let operationType = notification.userInfo?["operation"] as? String ?? "update"
        
        // Set appropriate toast message based on operation
        switch operationType {
        case "add":
            self.toastMessage = "Item added to wardrobe!"
        case "delete":
            self.toastMessage = "Item deleted successfully"
        default:
            self.toastMessage = "Wardrobe updated!"
        }
        
        self.isSuccessToast = true
        self.showToast = true
        
        // Hide toast after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                self.showToast = false
            }
        }
        
        // Refresh the wardrobe items
        loadClothingItems()
    }
    
    private func loadClothingItems() {
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "User not authenticated"
            isLoading = false
            return
        }
        
        isLoading = true
        
        FirebaseService.shared.getCleanClothingItems(for: userId) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let items):
                    self.clothingItems = items
                case .failure(let error):
                    self.errorMessage = "Failed to load clothing items: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteClothingItem(_ item: ClothingItem) {
        FirebaseService.shared.deleteClothingItem(item: item) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update local array directly instead of reloading from Firebase
                    if let index = self.clothingItems.firstIndex(where: { $0.id == item.id }) {
                        self.clothingItems.remove(at: index)
                    }
                    
                    // Show success toast
                    self.toastMessage = "Item deleted successfully"
                    self.isSuccessToast = true
                    self.showToast = true
                    
                    // Hide toast after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            self.showToast = false
                        }
                    }
                    
                    // Notify dashboard to update if needed
                    NotificationCenter.default.post(
                        name: Notification.Name("WardrobeUpdated"),
                        object: nil,
                        userInfo: ["operation": "delete"]
                    )
                case .failure(let error):
                    // Show error toast
                    self.toastMessage = "Failed to delete item"
                    self.isSuccessToast = false
                    self.showToast = true
                    
                    // Hide toast after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.showToast = false
                        }
                    }
                    
                    self.errorMessage = "Failed to delete item: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func markItemAsDirty(_ item: ClothingItem) {
        FirebaseService.shared.markItemAsDirty(item: item) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update local array directly instead of reloading from Firebase
                    if let index = self.clothingItems.firstIndex(where: { $0.id == item.id }) {
                        self.clothingItems.remove(at: index)
                    }
                    
                    // Show success toast
                    self.toastMessage = "\(item.name) added to laundry basket"
                    self.isSuccessToast = true
                    self.showToast = true
                    
                    // Hide toast after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            self.showToast = false
                        }
                    }
                    
                    // Notify dashboard to update if needed
                    NotificationCenter.default.post(
                        name: Notification.Name("WardrobeUpdated"),
                        object: nil,
                        userInfo: ["operation": "update"]
                    )
                case .failure(let error):
                    // Show error toast
                    self.toastMessage = "Failed to move item to laundry"
                    self.isSuccessToast = false
                    self.showToast = true
                    
                    // Hide toast after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.showToast = false
                        }
                    }
                    
                    self.errorMessage = "Failed to move item to laundry: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? AppColors.springRain : AppColors.moonMist.opacity(0.5))
                .foregroundColor(isSelected ? .white : AppColors.davyGrey)
                .cornerRadius(16)
        }
    }
}
