import SwiftUI
import Kingfisher
import FirebaseAuth

struct LaundryView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var laundryItems: [ClothingItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItems: Set<String> = []
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var isSuccessToast = true
    @State private var isEditing = false
    @State private var gridColumns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 12)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background color similar to WardrobeView
                AppColors.peachSnaps.opacity(0.2).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if !laundryItems.isEmpty {
                        washControls
                    }
                    
                    if isLoading {
                        loadingView
                    } else if laundryItems.isEmpty {
                        emptyStateView
                    } else {
                        laundryItemsGrid
                    }
                    
                    errorView
                }
            }
            .navigationTitle("Laundry Basket")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    editButton
                }
                
                // Add grid layout toggle like in WardrobeView
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: toggleGridLayout) {
                        if case let .adaptive(min, _) = gridColumns.first?.size, min == 120 {
                            Image(systemName: "square.grid.3x3")
                        } else {
                            Image(systemName: "square.grid.2x2")
                        }
                    }
                }
            }
            .onAppear {
                loadLaundryItems()
            }
            .toast(isPresented: $showToast, message: toastMessage, isSuccess: isSuccessToast)
        }
    }
    
    private var washControls: some View {
        HStack {
            if isEditing {
                Button(action: toggleSelectAll) {
                    Text(selectedItems.count == laundryItems.count ? "Deselect All" : "Select All")
                        .font(.subheadline)
                        .foregroundColor(AppColors.springRain)
                }
                
                Spacer()
                
                Button(action: washSelectedItems) {
                    HStack {
                        Image(systemName: "washer.fill")
                        Text("Wash (\(selectedItems.count))")
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedItems.isEmpty ?
                                  Color.gray.opacity(0.3) :
                                  AppColors.springRain)
                    )
                    .foregroundColor(selectedItems.isEmpty ? Color.gray : .white)
                    .cornerRadius(10)
                }
                .disabled(selectedItems.isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.5))
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
    
    private var editButton: some View {
        Button(action: {
            isEditing.toggle()
            if !isEditing {
                selectedItems.removeAll()
            }
        }) {
            Text(isEditing ? "Done" : "Edit")
        }
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
                Image(systemName: "basket.fill")
                    .font(.system(size: 60))
                    .foregroundColor(AppColors.davyGrey.opacity(0.6))
                
                Text("Your laundry basket is empty")
                    .font(.headline)
                    .foregroundColor(AppColors.davyGrey)
                
                Text("Mark items as dirty to add them here so they aren't mixed in with your outfits")
                    .font(.subheadline)
                    .foregroundColor(AppColors.davyGrey.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding()
            Spacer()
        }
    }
    
    private var laundryItemsGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(laundryItems) { item in
                    LaundryItemView(
                        item: item,
                        isEditing: isEditing,
                        isSelected: selectedItems.contains(item.id),
                        onToggleSelection: { toggleItemSelection(item.id) },
                        onWash: { washSingleItem(item) }
                    )
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
    
    private func loadLaundryItems() {
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "User not authenticated"
            isLoading = false
            return
        }
        
        isLoading = true
        FirebaseService.shared.getLaundryItems(for: userId) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let items):
                    laundryItems = items
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func toggleItemSelection(_ itemId: String) {
        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
        } else {
            selectedItems.insert(itemId)
        }
    }
    
    private func toggleSelectAll() {
        if selectedItems.count == laundryItems.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(laundryItems.map { $0.id })
        }
    }
    
    private func washSingleItem(_ item: ClothingItem) {
        FirebaseService.shared.washItems(items: [item]) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update local state
                    if let index = self.laundryItems.firstIndex(where: { $0.id == item.id }) {
                        self.laundryItems.remove(at: index)
                    }
                    
                    // Show success toast
                    self.showToast(message: "\(item.name) washed and returned to wardrobe", isSuccess: true)
                    
                    // Refresh wardrobe
                    NotificationCenter.default.post(name: .wardrobeUpdated, object: nil)
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.showToast(message: "Failed to wash item", isSuccess: false)
                }
            }
        }
    }
    
    private func washSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        
        let itemsToWash = laundryItems.filter { selectedItems.contains($0.id) }
        FirebaseService.shared.washItems(items: itemsToWash) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update local state
                    self.laundryItems.removeAll { selectedItems.contains($0.id) }
                    self.selectedItems.removeAll()
                    
                    // Show success toast
                    self.showToast(message: "Items washed and returned to wardrobe", isSuccess: true)
                    
                    // Refresh wardrobe
                    NotificationCenter.default.post(name: .wardrobeUpdated, object: nil)
                    
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.showToast(message: "Failed to wash items", isSuccess: false)
                }
            }
        }
    }
    
    private func showToast(message: String, isSuccess: Bool) {
        toastMessage = message
        isSuccessToast = isSuccess
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }
}
extension Notification.Name {
    static let wardrobeUpdated = Notification.Name("WardrobeUpdated")
}
