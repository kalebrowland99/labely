//
//  FoodSearchViewModel.swift
//  Invoice
//
//  View model for food search functionality
//  Clean architecture - Presentation layer
//

import Foundation
import SwiftUI

@MainActor
class FoodSearchViewModel: ObservableObject {
    
    @Published var searchText: String = ""
    @Published var searchResults: [FoodProduct] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedProduct: FoodProduct?
    
    private let foodService: FoodDatabaseService
    /// Open Food Facts uses English for product search (`lc=en`) regardless of app UI language.
    private static let productDatabaseLanguage = AppLanguage.english
    
    private var debouncedSearchTask: Task<Void, Never>?
    private var immediateSearchTask: Task<Void, Never>?
    
    private let debounceInterval: TimeInterval = 0.35
    private let minimumCharacters: Int = 2
    
    init(foodService: FoodDatabaseService = OpenFoodFactsService.shared) {
        self.foodService = foodService
    }
    
    func search(query: String) {
        searchText = query
    }
    
    func selectProduct(_ product: FoodProduct) {
        selectedProduct = product
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        errorMessage = nil
        cancelAllTasks()
    }
    
    func cancelAllTasks() {
        debouncedSearchTask?.cancel()
        immediateSearchTask?.cancel()
        debouncedSearchTask = nil
        immediateSearchTask = nil
        isLoading = false
    }
    
    /// Debounced search while typing.
    func onSearchTextChanged() {
        immediateSearchTask?.cancel()
        errorMessage = nil
        debouncedSearchTask?.cancel()
        
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else {
            searchResults = []
            isLoading = false
            return
        }
        
        isLoading = true
        let query = trimmed
        
        debouncedSearchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else {
                await MainActor.run { self.isLoading = false }
                return
            }
            await self.runSearch(query: query)
        }
    }
    
    /// Return key — runs one search immediately (no debounce) so results aren’t lost to cancel/race.
    func searchImmediately() {
        debouncedSearchTask?.cancel()
        debouncedSearchTask = nil
        immediateSearchTask?.cancel()
        errorMessage = nil
        
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else {
            searchResults = []
            isLoading = false
            return
        }
        
        isLoading = true
        let query = trimmed
        
        immediateSearchTask = Task { [weak self] in
            await self?.runSearch(query: query)
        }
    }
    
    private func runSearch(query: String) async {
        do {
            let results = try await foodService.searchProducts(
                query: query,
                language: Self.productDatabaseLanguage
            )
            try Task.checkCancellation()
            
            let current = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == query else {
                isLoading = false
                return
            }
            
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                searchResults = results
                isLoading = false
                errorMessage = nil
            }
        } catch is CancellationError {
            isLoading = false
        } catch {
            try? Task.checkCancellation()
            let current = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == query else {
                isLoading = false
                return
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                searchResults = []
                isLoading = false
                if let foodError = error as? FoodServiceError {
                    errorMessage = foodError.errorDescription
                } else if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                        errorMessage = NSLocalizedString("no_internet_connection", comment: "")
                    case .timedOut:
                        errorMessage = NSLocalizedString("search_timed_out", comment: "")
                    default:
                        errorMessage = NSLocalizedString("unable_to_reach_database", comment: "")
                    }
                } else {
                    errorMessage = NSLocalizedString("search_failed", comment: "")
                }
            }
        }
    }
    
    func cleanup() {
        cancelAllTasks()
    }
}

#if DEBUG
extension FoodSearchViewModel {
    static var preview: FoodSearchViewModel {
        let vm = FoodSearchViewModel()
        vm.searchResults = [
            FoodProduct(
                id: "1",
                name: "Chicken Breast",
                brand: "Organic Farms",
                imageURL: nil,
                nutritionalInfo: NutritionalInfo(
                    caloriesPer100g: 165,
                    proteinPer100g: 31,
                    carbsPer100g: 0,
                    fatPer100g: 3.6,
                    fiberPer100g: 0,
                    sugarsPer100g: 0,
                    sodiumPer100g: 0.074,
                    caloriesPerServing: nil,
                    proteinPerServing: nil,
                    carbsPerServing: nil,
                    fatPerServing: nil
                ),
                servingSize: "100g"
            )
        ]
        return vm
    }
}
#endif
