//
//  FoodModels.swift
//  Invoice
//
//  Food database models and data transfer objects
//  Clean architecture - Domain layer
//

import Foundation

// MARK: - Domain Models

/// Represents a food product with nutritional information
struct FoodProduct: Identifiable, Codable {
    let id: String
    let name: String
    let brand: String?
    let imageURL: URL?
    let nutritionalInfo: NutritionalInfo?
    let servingSize: String?
    
    var displayName: String {
        if let brand = brand, !brand.isEmpty {
            return "\(name) - \(brand)"
        }
        return name
    }
}

/// Nutritional information per 100g and per serving
struct NutritionalInfo: Codable {
    // Per 100g
    let caloriesPer100g: Double?
    let proteinPer100g: Double?
    let carbsPer100g: Double?
    let fatPer100g: Double?
    let fiberPer100g: Double?
    let sugarsPer100g: Double?
    let sodiumPer100g: Double?
    
    // Per serving
    let caloriesPerServing: Double?
    let proteinPerServing: Double?
    let carbsPerServing: Double?
    let fatPerServing: Double?
}

// MARK: - API Response Models (DTOs)

/// OpenFoodFacts API search response
struct OFFSearchResponse: Codable {
    let products: [OFFProduct]
    let count: Int?
    let page: Int?
    let pageSize: Int?
    
    enum CodingKeys: String, CodingKey {
        case products, count, page
        case pageSize = "page_size"
    }
}

/// OpenFoodFacts API single product response
struct OFFProductResponse: Codable {
    let status: Int?
    let code: String?
    let product: OFFProduct?
}

/// OpenFoodFacts API product model
struct OFFProduct: Codable, Identifiable {
    let code: String?
    let productName: String?
    let productNameEn: String?
    let productNameEs: String?
    let productNameRu: String?
    let brands: String?
    let imageURL: String?
    let nutriments: OFFNutriments?
    let servingSize: String?
    
    var id: String { code ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case productNameEn = "product_name_en"
        case productNameEs = "product_name_es"
        case productNameRu = "product_name_ru"
        case brands
        case imageURL = "image_url"
        case nutriments
        case servingSize = "serving_size"
    }
}

/// OpenFoodFacts nutriment data
struct OFFNutriments: Codable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let sugars100g: Double?
    let sodium100g: Double?
    
    let energyKcalServing: Double?
    let proteinsServing: Double?
    let carbohydratesServing: Double?
    let fatServing: Double?
    
    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case sodium100g = "sodium_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteinsServing = "proteins_serving"
        case carbohydratesServing = "carbohydrates_serving"
        case fatServing = "fat_serving"
    }
}

// MARK: - Mapper Extensions

extension OFFProduct {
    /// Convert API model to domain model with proper language handling
    func toDomainModel(preferredLanguage: AppLanguage) -> FoodProduct? {
        guard let barcode = code?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty else {
            return nil
        }
        // Get product name in preferred language, fallback to default
        let name = getLocalizedName(for: preferredLanguage)
        
        // Skip products without a name in any language
        guard !name.isEmpty else { return nil }
        
        // Convert nutriments
        let nutritionalInfo: NutritionalInfo? = nutriments.map {
            NutritionalInfo(
                caloriesPer100g: $0.energyKcal100g,
                proteinPer100g: $0.proteins100g,
                carbsPer100g: $0.carbohydrates100g,
                fatPer100g: $0.fat100g,
                fiberPer100g: $0.fiber100g,
                sugarsPer100g: $0.sugars100g,
                sodiumPer100g: $0.sodium100g,
                caloriesPerServing: $0.energyKcalServing,
                proteinPerServing: $0.proteinsServing,
                carbsPerServing: $0.carbohydratesServing,
                fatPerServing: $0.fatServing
            )
        }
        
        return FoodProduct(
            id: barcode,
            name: name,
            brand: brands,
            imageURL: imageURL.flatMap { URL(string: $0) },
            nutritionalInfo: nutritionalInfo,
            servingSize: servingSize
        )
    }
    
    /// Get product name in preferred language with intelligent fallback
    private func getLocalizedName(for language: AppLanguage) -> String {
        switch language {
        case .english:
            return productNameEn ?? productName ?? ""
        case .spanish:
            return productNameEs ?? productName ?? ""
        case .russian:
            return productNameRu ?? productName ?? ""
        }
    }
    
    /// Check if product has name in specified language
    func hasNameInLanguage(_ language: AppLanguage) -> Bool {
        let name = getLocalizedName(for: language)
        return !name.isEmpty
    }
}

// MARK: - Search Configuration

/// Configuration for food database searches
struct FoodSearchConfig {
    let pageSize: Int
    let timeout: TimeInterval
    let cacheExpiration: TimeInterval
    let maxCacheEntries: Int
    
    static let `default` = FoodSearchConfig(
        pageSize: 12,
        timeout: 25.0,
        cacheExpiration: 300, // 5 minutes
        maxCacheEntries: 20
    )
}

// MARK: - Service Errors

enum FoodServiceError: LocalizedError {
    case invalidQuery
    case invalidResponse
    case networkError(Error)
    case noResults
    case productNotFound
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return NSLocalizedString("invalid_search_query", comment: "")
        case .invalidResponse:
            return NSLocalizedString("unable_to_reach_database", comment: "")
        case .networkError(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    return NSLocalizedString("no_internet_connection", comment: "")
                case .timedOut:
                    return NSLocalizedString("search_timed_out", comment: "")
                default:
                    return NSLocalizedString("unable_to_reach_database", comment: "")
                }
            }
            return NSLocalizedString("search_failed", comment: "")
        case .noResults:
            return NSLocalizedString("no_results_found", comment: "")
        case .productNotFound:
            return NSLocalizedString("product_not_found", comment: "")
        case .parsingError:
            return NSLocalizedString("search_failed", comment: "")
        }
    }
}

// MARK: - openFDA (U.S. food enforcement — shared models for ContentView + GlobalSafetySignalsService)

struct OpenFDAFoodEnforcementResponse: Decodable {
    let results: [OpenFDAFoodEnforcementRecord]?
}

/// One FDA food enforcement / recall report (subset of fields shown in Brand Trust UI).
struct OpenFDAFoodEnforcementRecord: Decodable, Identifiable {
    var id: String { recall_number ?? UUID().uuidString }
    let recall_number: String?
    let reason_for_recall: String?
    let recalling_firm: String?
    let product_description: String?
    let classification: String?
    let report_date: String?
    let status: String?
    let center_classification_date: String?
}

// MARK: - FDA fetch + global portal links (single module target — avoids missing file in Xcode)

enum GlobalSafetySignalsService {
    private static let openFDABase = "https://api.fda.gov/food/enforcement.json"
    
    static func fetchUSFDAEnforcement(brandOrProduct: String, limit: Int = 8) async throws -> [OpenFDAFoodEnforcementRecord] {
        let term = brandOrProduct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let safe = term.replacingOccurrences(of: "\"", with: "")
        let search =
            "recalling_firm:\"\(safe)\"+OR+product_description:\"\(safe)\"+OR+reason_for_recall:\"\(safe)\""
        var components = URLComponents(string: openFDABase)!
        components.queryItems = [
            URLQueryItem(name: "search", value: search),
            URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 50))")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 28
        request.setValue("Labely-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OpenFDAFoodEnforcementResponse.self, from: data)
        return decoded.results ?? []
    }
}

enum LabelyOfficialSafetyPortals {
    struct PortalLink: Identifiable {
        var id: String { url.absoluteString }
        let title: String
        let subtitle: String
        let url: URL
    }
    
    static func links(forBrandQuery query: String) -> [PortalLink] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        var out: [PortalLink] = []
        if let u = URL(string: "https://food.ec.europa.eu/safety/rasff_en") {
            out.append(PortalLink(title: "EU — RASFF (alerts & official controls)", subtitle: "European Commission food safety notifications", url: u))
        }
        if let u = URL(string: "https://www.food.gov.uk/warning-about-product") {
            out.append(PortalLink(title: "UK — Food Standards Agency", subtitle: "Allergen alerts & product recalls", url: u))
        }
        if let u = URL(string: "https://recalls-rappels.canada.ca/en/search/site/\(encoded)") {
            out.append(PortalLink(title: "Canada — Recalls & safety alerts", subtitle: "Government of Canada recall search", url: u))
        }
        if let u = URL(string: "https://www.foodstandards.gov.au/consumer/recalls") {
            out.append(PortalLink(title: "Australia & NZ — FSANZ recalls", subtitle: "Food Standards Australia New Zealand", url: u))
        }
        if let u = URL(string: "https://open.fda.gov/apis/food/enforcement/") {
            out.append(PortalLink(title: "U.S. — openFDA documentation", subtitle: "Food enforcement data dictionary", url: u))
        }
        if let u = URL(string: "https://www.courtlistener.com/?q=\(encoded)") {
            out.append(PortalLink(title: "CourtListener — case search", subtitle: "Free Law Project (verify dockets & filings)", url: u))
        }
        return out
    }
}
