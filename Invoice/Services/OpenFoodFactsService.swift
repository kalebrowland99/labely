//
//  OpenFoodFactsService.swift
//  Invoice
//
//  Service layer for OpenFoodFacts API integration
//  Clean architecture - Infrastructure layer
//

import Foundation

// MARK: - URL session (connectivity + shared configuration)

private enum OpenFoodFactsURLSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 28
        config.timeoutIntervalForResource = 75
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()
}

// MARK: - Service Protocol

protocol FoodDatabaseService: Actor {
    func searchProducts(query: String, language: AppLanguage) async throws -> [FoodProduct]
    func getProduct(barcode: String, language: AppLanguage) async throws -> FoodProduct
    func clearCache() async
}

// MARK: - OpenFoodFacts Service Implementation

actor OpenFoodFactsService: FoodDatabaseService {
    
    // MARK: - Properties
    
    static let shared = OpenFoodFactsService()
    
    private let baseURL = "https://world.openfoodfacts.org"
    private let config: FoodSearchConfig
    
    // Thread-safe cache
    private var searchCache: [String: CachedSearchResult] = [:]
    
    // MARK: - Initialization
    
    init(config: FoodSearchConfig = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Search for products by name with language-specific results
    func searchProducts(query: String, language: AppLanguage) async throws -> [FoodProduct] {
        // Validate input
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FoodServiceError.invalidQuery
        }
        
        // Check cache
        if let cachedResults = getCachedResults(for: query, language: language) {
            print("✅ [FoodService] Returning cached results for '\(query)' [\(language.code)]")
            return cachedResults
        }
        
        // Make API request
        print("🔍 [FoodService] Searching OpenFoodFacts for '\(query)' [\(language.code)]")
        
        let products = try await performSearch(query: query, language: language)
        
        // Filter products to only show those with names in the selected language
        let filteredProducts = filterProductsByLanguage(products, language: language)
        
        // Convert to domain models
        let domainProducts = filteredProducts.compactMap { $0.toDomainModel(preferredLanguage: language) }
        
        // Cache results
        cacheResults(domainProducts, for: query, language: language)
        
        print("✅ [FoodService] Found \(domainProducts.count) products for '\(query)' [\(language.code)]")
        
        return domainProducts
    }
    
    /// Get product by barcode with language-specific data
    func getProduct(barcode: String, language: AppLanguage) async throws -> FoodProduct {
        print("🔍 [FoodService] Fetching product by barcode: \(barcode) [\(language.code)]")
        
        let offProduct = try await fetchProductByBarcode(barcode, language: language)
        
        guard let domainProduct = offProduct.toDomainModel(preferredLanguage: language) else {
            throw FoodServiceError.productNotFound
        }
        
        return domainProduct
    }
    
    /// Clear all cached results
    func clearCache() async {
        searchCache.removeAll()
        print("🧹 [FoodService] Cache cleared")
    }
    
    // MARK: - Private Methods
    
    /// Perform API search request (retries transient failures — common on cellular / flaky Wi‑Fi).
    private func performSearch(query: String, language: AppLanguage) async throws -> [OFFProduct] {
        try Task.checkCancellation()
        
        guard let url = buildSearchURL(query: query, language: language) else {
            throw FoodServiceError.invalidQuery
        }
        
        let maxAttempts = 4
        var lastError: Error = FoodServiceError.invalidResponse
        
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            
            var request = URLRequest(url: url)
            request.timeoutInterval = config.timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            do {
                let (data, response) = try await OpenFoodFactsURLSession.shared.data(for: request)
                try Task.checkCancellation()
                
                guard let http = response as? HTTPURLResponse else {
                    lastError = FoodServiceError.invalidResponse
                    if attempt < maxAttempts - 1 { try await backoff(attempt: attempt) }
                    continue
                }
                
                let code = http.statusCode
                if (200...299).contains(code) {
                    return try parseSearchResponse(data)
                }
                
                // Retry on rate-limit / temporary server errors
                if [429, 502, 503, 504].contains(code) && attempt < maxAttempts - 1 {
                    try await backoff(attempt: attempt)
                    continue
                }
                
                lastError = FoodServiceError.invalidResponse
                if attempt < maxAttempts - 1 {
                    try await backoff(attempt: attempt)
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError {
                lastError = FoodServiceError.networkError(urlError)
                if urlError.code == .cancelled { throw urlError }
                if attempt < maxAttempts - 1 {
                    try await backoff(attempt: attempt)
                    continue
                }
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    try await backoff(attempt: attempt)
                    continue
                }
            }
        }
        
        throw mapThrownError(lastError)
    }
    
    private func backoff(attempt: Int) async throws {
        let ms = 250 * (attempt + 1) * (attempt + 1)
        try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }
    
    private func mapThrownError(_ error: Error) -> Error {
        if let fe = error as? FoodServiceError { return fe }
        if let u = error as? URLError { return FoodServiceError.networkError(u) }
        return FoodServiceError.networkError(error)
    }
    
    /// Fetch product by barcode (retries transient network failures).
    private func fetchProductByBarcode(_ barcode: String, language: AppLanguage) async throws -> OFFProduct {
        guard let url = buildBarcodeURL(barcode: barcode, language: language) else {
            throw FoodServiceError.invalidQuery
        }
        
        let maxAttempts = 4
        var lastError: Error = FoodServiceError.invalidResponse
        
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            
            var request = URLRequest(url: url)
            request.timeoutInterval = config.timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            
            do {
                let (data, response) = try await OpenFoodFactsURLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    lastError = FoodServiceError.invalidResponse
                    if attempt < maxAttempts - 1 { try await backoff(attempt: attempt) }
                    continue
                }
                if !(200...299).contains(http.statusCode) {
                    if [429, 502, 503, 504].contains(http.statusCode), attempt < maxAttempts - 1 {
                        try await backoff(attempt: attempt)
                        continue
                    }
                    lastError = FoodServiceError.invalidResponse
                    if attempt < maxAttempts - 1 {
                        try await backoff(attempt: attempt)
                        continue
                    }
                    throw mapThrownError(lastError)
                }
                let offResponse = try JSONDecoder().decode(OFFProductResponse.self, from: data)
                guard let product = offResponse.product else {
                    throw FoodServiceError.productNotFound
                }
                return product
            } catch is CancellationError {
                throw CancellationError()
            } catch FoodServiceError.productNotFound {
                throw FoodServiceError.productNotFound
            } catch let urlError as URLError {
                lastError = FoodServiceError.networkError(urlError)
                if urlError.code == .cancelled { throw urlError }
                if attempt < maxAttempts - 1 {
                    try await backoff(attempt: attempt)
                    continue
                }
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    try await backoff(attempt: attempt)
                    continue
                }
            }
        }
        
        throw mapThrownError(lastError)
    }
    
    /// Build search URL with proper parameters
    private func buildSearchURL(query: String, language: AppLanguage) -> URL? {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        // World search with English UI (`lc=en`). Omit `fields` so responses match default OFF search behavior (some deployments ignore or mishandle `fields` on search.pl).
        let urlString = "\(baseURL)/cgi/search.pl?" +
            "search_terms=\(encodedQuery)" +
            "&search_simple=1" +
            "&action=process" +
            "&json=1" +
            "&page_size=\(config.pageSize)" +
            "&lc=\(language.code)"
        
        return URL(string: urlString)
    }
    
    /// Build barcode URL with language parameter (English for product DB lookups).
    private func buildBarcodeURL(barcode: String, language: AppLanguage) -> URL? {
        let urlString = "\(baseURL)/api/v2/product/\(barcode).json?lc=\(language.code)&fields=code,product_name,product_name_en,product_name_es,product_name_ru,brands,image_url,nutriments,serving_size"
        return URL(string: urlString)
    }
    
    /// Parse search response with error handling
    private func parseSearchResponse(_ data: Data) throws -> [OFFProduct] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let productsArray = json["products"] as? [[String: Any]] else {
            print("❌ [FoodService] Failed to parse response")
            throw FoodServiceError.parsingError
        }
        
        var validProducts: [OFFProduct] = []
        
        for productDict in productsArray {
            // `code` is often a JSON number on search.pl — must stringify or barcode-based flows break.
            let codeString = Self.stringCode(from: productDict)
            let product = OFFProduct(
                code: codeString,
                productName: productDict["product_name"] as? String,
                productNameEn: productDict["product_name_en"] as? String,
                productNameEs: productDict["product_name_es"] as? String,
                productNameRu: productDict["product_name_ru"] as? String,
                brands: productDict["brands"] as? String,
                imageURL: productDict["image_url"] as? String,
                nutriments: parseNutriments(productDict["nutriments"] as? [String: Any]),
                servingSize: productDict["serving_size"] as? String
            )
            
            validProducts.append(product)
        }
        
        return validProducts
    }
    
    /// Normalize Open Food Facts `code` field (String, Int, or Double in JSON).
    private static func stringCode(from dict: [String: Any]) -> String? {
        if let s = dict["code"] as? String, !s.isEmpty { return s }
        if let i = dict["code"] as? Int { return String(i) }
        if let d = dict["code"] as? Double { return String(Int(d)) }
        return nil
    }
    
    /// Parse nutriments dictionary
    private func parseNutriments(_ dict: [String: Any]?) -> OFFNutriments? {
        guard let dict = dict else { return nil }
        
        return OFFNutriments(
            energyKcal100g: dict["energy-kcal_100g"] as? Double,
            proteins100g: dict["proteins_100g"] as? Double,
            carbohydrates100g: dict["carbohydrates_100g"] as? Double,
            fat100g: dict["fat_100g"] as? Double,
            fiber100g: dict["fiber_100g"] as? Double,
            sugars100g: dict["sugars_100g"] as? Double,
            sodium100g: dict["sodium_100g"] as? Double,
            energyKcalServing: dict["energy-kcal_serving"] as? Double,
            proteinsServing: dict["proteins_serving"] as? Double,
            carbohydratesServing: dict["carbohydrates_serving"] as? Double,
            fatServing: dict["fat_serving"] as? Double
        )
    }
    
    /// Filter products to only show rows we can display meaningfully for the chosen language.
    private func filterProductsByLanguage(_ products: [OFFProduct], language: AppLanguage) -> [OFFProduct] {
        return products.filter { product in
            switch language {
            case .english:
                // Prefer English-tagged names; always accept a non-empty default `product_name` (many OFF rows only set that field).
                if let nameEn = product.productNameEn, !nameEn.isEmpty { return true }
                if let name = product.productName, !name.isEmpty { return true }
                return false
                
            case .spanish:
                // For Spanish, require product_name_es or product_name that differs from English
                if let nameEs = product.productNameEs, !nameEs.isEmpty {
                    return true
                }
                if let name = product.productName, !name.isEmpty {
                    // Accept if English version doesn't exist or is different
                    return product.productNameEn == nil || product.productNameEn != name
                }
                return false
                
            case .russian:
                // For Russian, require product_name_ru or accept product_name as fallback
                if let nameRu = product.productNameRu, !nameRu.isEmpty {
                    return true
                }
                return product.productName != nil && !product.productName!.isEmpty
            }
        }
    }
    
    // MARK: - Cache Management
    
    private func getCachedResults(for query: String, language: AppLanguage) -> [FoodProduct]? {
        let cacheKey = makeCacheKey(query: query, language: language)
        
        guard let cached = searchCache[cacheKey] else {
            return nil
        }
        
        // Check if cache is expired
        let age = Date().timeIntervalSince(cached.timestamp)
        if age >= config.cacheExpiration {
            searchCache.removeValue(forKey: cacheKey)
            return nil
        }
        
        return cached.products
    }
    
    private func cacheResults(_ products: [FoodProduct], for query: String, language: AppLanguage) {
        let cacheKey = makeCacheKey(query: query, language: language)
        
        searchCache[cacheKey] = CachedSearchResult(
            products: products,
            timestamp: Date()
        )
        
        // Clean up old entries
        cleanupCache()
    }
    
    private func cleanupCache() {
        guard searchCache.count > config.maxCacheEntries else { return }
        
        let sortedKeys = searchCache.sorted { $0.value.timestamp < $1.value.timestamp }
        let keysToRemove = sortedKeys.prefix(searchCache.count - config.maxCacheEntries)
        
        for (key, _) in keysToRemove {
            searchCache.removeValue(forKey: key)
        }
    }
    
    private func makeCacheKey(query: String, language: AppLanguage) -> String {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        return "\(normalizedQuery)_\(language.code)"
    }
}

// MARK: - Cache Model

private struct CachedSearchResult {
    let products: [FoodProduct]
    let timestamp: Date
}
