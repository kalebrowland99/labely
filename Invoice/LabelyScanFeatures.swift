//
//  LabelyScanFeatures.swift
//  Labely — QR/barcode live scan, Open Food Facts + OpenAI product insight
//

import SwiftUI
import AVFoundation
import AudioToolbox
import UIKit
import Vision
import PhotosUI
import CoreImage
import OSLog

// MARK: - Logging (filter in Console.app by subsystem or category)

enum LabelyLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Labely"
    static let off = Logger(subsystem: subsystem, category: "OpenFoodFacts")
    static let session = Logger(subsystem: subsystem, category: "ScanSession")
    static let vision = Logger(subsystem: subsystem, category: "VisionBarcode")
    static let ai = Logger(subsystem: subsystem, category: "ProductInsight")
    static let camera = Logger(subsystem: subsystem, category: "BarcodeCamera")
    static let ui = Logger(subsystem: subsystem, category: "ScanUI")
}

// MARK: - Models

struct LabelyProductInsight: Codable, Equatable {
    var healthGrade: HealthGrade
    var quickOverview: QuickOverview
    var ingredientsList: [String]
    var brandTrust: BrandTrust
    var additives: [AdditiveCard]
    var microplasticRisk: RiskBlock
    var heavyMetalRisk: HeavyMetalRisk
    
    struct HealthGrade: Codable, Equatable {
        var score: Int
        var label: String
    }
    
    struct QuickOverview: Codable, Equatable {
        var harmfulAdditivesCount: Int
        var containsSeedOil: Bool
        var totalIngredients: Int
        var ultraProcessed: Bool
        var novaGroup: Int?
        var naturalPercent: Int
        var processedPercent: Int
    }
    
    struct BrandTrust: Codable, Equatable {
        var rating: String
        var summary: String
    }
    
    struct AdditiveCard: Codable, Equatable, Identifiable {
        var id: String { name + (code ?? "") }
        var name: String
        var code: String?
        var risk: String
        var category: String
        var description: String
    }
    
    struct RiskBlock: Codable, Equatable {
        var level: String
        var note: String
    }
    
    struct HeavyMetalRisk: Codable, Equatable {
        var level: String
        var score: Int
        var note: String
        var metals: [MetalRow]
        
        struct MetalRow: Codable, Equatable, Identifiable {
            var id: String { symbol + (name ?? "") }
            var symbol: String
            var name: String?
            var level: String
            var note: String?
        }
    }
    
    static let empty = LabelyProductInsight(
        healthGrade: .init(score: 0, label: "—"),
        quickOverview: .init(
            harmfulAdditivesCount: 0,
            containsSeedOil: false,
            totalIngredients: 0,
            ultraProcessed: false,
            novaGroup: nil,
            naturalPercent: 50,
            processedPercent: 50
        ),
        ingredientsList: [],
        brandTrust: .init(rating: "Unknown", summary: "—"),
        additives: [],
        microplasticRisk: .init(level: "Unknown", note: "—"),
        heavyMetalRisk: .init(level: "Unknown", score: 0, note: "—", metals: [])
    )
}

struct BrandReportPreview: Identifiable, Equatable {
    let id: String
    let brandName: String
    let headline: String
    let severity: String
    let kind: String
}

// MARK: - Scan history

final class LabelyScanHistoryStore: ObservableObject {
    static let shared = LabelyScanHistoryStore()
    private let key = "labely_recent_scans_v1"
    
    @Published private(set) var items: [LabelyScanRecord] = []
    
    struct LabelyScanRecord: Codable, Identifiable, Equatable {
        var id: String { barcode }
        let barcode: String
        let productName: String
        let brand: String?
        let scannedAt: Date
        let healthScore: Int
        /// Open Food Facts product image (HTTPS) when available.
        let imageURL: String?
    }
    
    private init() { load() }
    
    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LabelyScanRecord].self, from: data) else {
            items = []
            return
        }
        items = Array(decoded.prefix(20))
    }
    
    func add(barcode: String, productName: String, brand: String?, healthScore: Int, imageURL: String? = nil) {
        var next = items.filter { $0.barcode != barcode }
        next.insert(
            LabelyScanRecord(barcode: barcode, productName: productName, brand: brand, scannedAt: Date(), healthScore: healthScore, imageURL: imageURL),
            at: 0
        )
        items = Array(next.prefix(20))
        persist()
    }

    func remove(barcode: String) {
        items.removeAll { $0.barcode == barcode }
        persist()
    }
    
    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Home screen: Open Food Facts photo examples (fill empty recent-scan slots)

enum LabelyOFFHomeExamples {
    struct Entry: Identifiable, Equatable {
        var id: String { barcode }
        let barcode: String
        let productName: String
        let brand: String
        /// 0–100, matches health grade ring on home cards
        let healthScore: Int
    }

    /// Preloaded, reliable OFF `image_url` values for default/home items.
    /// These include the numeric image ID (e.g. `front_en.820.400.jpg`) so they won’t 404.
    static let preloadedImageURLByBarcode: [String: URL] = [
        // Home defaults
        "3017620422003": URL(string: "https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.820.400.jpg")!, // Nutella
        "5000112548167": URL(string: "https://images.openfoodfacts.org/images/products/500/011/254/8167/front_de.30.400.jpg")!, // Diet Coke
        "0889392002287": URL(string: "https://images.openfoodfacts.org/images/products/088/939/200/2287/front_en.6.400.jpg")!, // Celsius Energy Drink
        "0043695211030": URL(string: "https://images.openfoodfacts.org/images/products/004/369/521/1030/front_en.8.400.jpg")!, // Hot Pockets Ham & Cheddar
        "0016000224766": URL(string: "https://images.openfoodfacts.org/images/products/001/600/022/4766/front_en.14.400.jpg")!, // Cinnamon Toast Crunch
        "0758108771567": URL(string: "https://images.openfoodfacts.org/images/products/075/810/877/1567/front_en.3.400.jpg")!, // Sweetened almond milk
        
        // Clean Swaps (and other default UI) barcodes
        "5449000000996": URL(string: "https://images.openfoodfacts.org/images/products/544/900/000/0996/front_en.1035.400.jpg")!, // Coca-Cola Classic
        "0012000001086": URL(string: "https://images.openfoodfacts.org/images/products/001/200/000/1086/front_fr.3.400.jpg")!, // Aquafina Still Water
        "8001505005592": URL(string: "https://images.openfoodfacts.org/images/products/800/150/500/5592/front_fr.133.400.jpg")!, // Nocciolata
        "3168930010265": URL(string: "https://images.openfoodfacts.org/images/products/316/893/001/0265/front_en.297.400.jpg")!, // Cruesly Nuts Mix
        "3033710065967": URL(string: "https://images.openfoodfacts.org/images/products/303/371/006/5967/front_en.472.400.jpg")!, // Nesquik Cacao
        "5000157024671": URL(string: "https://images.openfoodfacts.org/images/products/500/015/702/4671/front_en.433.400.jpg")!, // Heinz Beanz
        "7622210449283": URL(string: "https://images.openfoodfacts.org/images/products/762/221/044/9283/front_en.605.400.jpg")!, // Prince Chocolat
        "80052760": URL(string: "https://images.openfoodfacts.org/images/products/000/008/005/2760/front_en.503.400.jpg")! // Kinder Bueno
    ]
    
    /// Real Open Food Facts barcodes — images load via the product API (resolveImageURL) since
    /// OFF CDN filenames embed a numeric image ID that cannot be guessed from the barcode alone.
    static let catalog: [Entry] = [
        // Home defaults (page 1 left→right, then page 2 when swiped)
        Entry(barcode: "3017620422003", productName: "Nutella", brand: "Ferrero", healthScore: 38),
        Entry(barcode: "5000112548167", productName: "Diet Coke", brand: "Coca-Cola", healthScore: 28),
        Entry(barcode: "0889392002287", productName: "Celsius", brand: "CELSIUS", healthScore: 35),
        Entry(barcode: "0043695211030", productName: "Hot Pockets", brand: "Hot Pockets", healthScore: 20),
        Entry(barcode: "0016000224766", productName: "Cinnamon Toast Crunch", brand: "General Mills", healthScore: 25),
        Entry(barcode: "0758108771567", productName: "Sweetened Almond Milk", brand: "?", healthScore: 60)
    ]
    
    /// Runtime-resolved URLs populated by `LabelyCleanSwapsCatalogView` preload task.
    /// Keyed by barcode; only contains entries not already in `preloadedImageURLByBarcode`.
    static var runtimeURLsByBarcode: [String: URL] = [:]

    static func imageURL(barcode: String) -> URL? {
        preloadedImageURLByBarcode[barcode] ?? runtimeURLsByBarcode[barcode]
    }
}

// MARK: - (Default images) Use preloaded direct URLs

// MARK: - Clean Swaps catalog (home sheet; OFF pack photos when available)

enum LabelyCleanSwapCatalog {
    struct Row: Identifiable, Equatable {
        var id: String { "\(category)-\(avoidBarcode)-\(betterBarcode)" }
        let category: String
        let avoidBarcode: String
        let avoidName: String
        let avoidBrand: String
        let avoidScore: Int
        let avoidBullets: [String]
        let betterBarcode: String
        let betterName: String
        let betterBrand: String
        let betterScore: Int
        let betterBullets: [String]
        let footer: String
        
        var avoidImageURL: URL? { LabelyOFFHomeExamples.imageURL(barcode: avoidBarcode) }
        var betterImageURL: URL? { LabelyOFFHomeExamples.imageURL(barcode: betterBarcode) }
    }
    
    /// Pairs use verified Open Food Facts barcodes so pack images resolve via the product API.
    /// Each barcode appears at most once across all rows (both avoid and better sides).
    static let rows: [Row] = [
        Row(
            category: "Beverages",
            avoidBarcode: "5449000000996", avoidName: "Coca-Cola Classic", avoidBrand: "Coca-Cola", avoidScore: 32,
            avoidBullets: ["• Added sugars", "• Caramel color"],
            betterBarcode: "0012000001086", betterName: "Aquafina Still Water", betterBrand: "Aquafina", betterScore: 80,
            betterBullets: ["✓ No added sugar", "✓ Zero calories"],
            footer: "Reach for still water instead of sugary sodas."
        ),
        Row(
            category: "Sweet Spreads",
            avoidBarcode: "3017620422003", avoidName: "Nutella", avoidBrand: "Ferrero", avoidScore: 38,
            avoidBullets: ["• Palm oil", "• High sugar (57 %)"],
            betterBarcode: "8001505005592", betterName: "Nocciolata Organic", betterBrand: "Rigoni di Asiago", betterScore: 52,
            betterBullets: ["✓ No palm oil", "✓ Organic ingredients"],
            footer: "Swap palm-oil-heavy hazelnut spreads for organic, palm-oil-free alternatives."
        ),
        Row(
            category: "Cookies & bars",
            avoidBarcode: "80052760", avoidName: "Kinder Bueno", avoidBrand: "Kinder", avoidScore: 40,
            avoidBullets: ["• High sugar", "• Palm oil"],
            betterBarcode: "7622210449283", betterName: "Prince Chocolat", betterBrand: "LU", betterScore: 44,
            betterBullets: ["✓ Shorter ingredient list", "✓ Lower fat per bar"],
            footer: "Compare ingredient lists on chocolate bars — shorter is usually better."
        ),
        Row(
            category: "Breakfast drinks",
            avoidBarcode: "3033710065967", avoidName: "Nesquik Cacao", avoidBrand: "Nestlé", avoidScore: 38,
            avoidBullets: ["• Added sugar", "• Artificial flavour"],
            betterBarcode: "3168930010265", betterName: "Cruesly Nuts & Seeds", betterBrand: "Quaker", betterScore: 52,
            betterBullets: ["✓ Whole grain oats", "✓ No added sweeteners"],
            footer: "Skip the sugary chocolate powder; choose wholegrain cereals with no added sugar."
        ),
        Row(
            category: "Diet beverages",
            avoidBarcode: "5000112548167", avoidName: "Diet Coke", avoidBrand: "Coca-Cola", avoidScore: 28,
            avoidBullets: ["• Aspartame sweetener", "• Phosphoric acid"],
            betterBarcode: "3179693006085", betterName: "Perrier Sparkling Water", betterBrand: "Perrier", betterScore: 82,
            betterBullets: ["✓ No sweeteners", "✓ Natural carbonation"],
            footer: "Even diet sodas carry additive concerns — sparkling mineral water is a satisfying swap."
        ),
        Row(
            category: "Pantry",
            avoidBarcode: "5000157024671", avoidName: "Heinz Beanz", avoidBrand: "Heinz", avoidScore: 55,
            avoidBullets: ["• Added sugars", "• Modified starch"],
            betterBarcode: "8005110032028", betterName: "Mutti Polpa Tomatoes", betterBrand: "Mutti", betterScore: 72,
            betterBullets: ["✓ Single ingredient", "✓ No added sugar"],
            footer: "Compare labels on canned staples — single-ingredient products have far fewer additives."
        ),
        Row(
            category: "Energy drinks",
            avoidBarcode: "0889392002287", avoidName: "Celsius", avoidBrand: "CELSIUS", avoidScore: 35,
            avoidBullets: ["• Stimulant load", "• Additives & flavors"],
            betterBarcode: "0898522001000", betterName: "Vita Coco Coconut Water", betterBrand: "Vita Coco", betterScore: 74,
            betterBullets: ["✓ Natural electrolytes", "✓ Minimal ingredients"],
            footer: "Swap daily energy drinks for coconut water — natural electrolytes, no synthetic stimulants."
        ),
        Row(
            category: "Frozen snacks",
            avoidBarcode: "0043695211030", avoidName: "Hot Pockets", avoidBrand: "Hot Pockets", avoidScore: 20,
            avoidBullets: ["• Ultra-processed", "• Preservatives & emulsifiers"],
            betterBarcode: "0085239089929", betterName: "365 Organic Frozen Broccoli", betterBrand: "365 by WFM", betterScore: 88,
            betterBullets: ["✓ Single ingredient", "✓ No additives"],
            footer: "When you’re short on time, plain frozen vegetables are one of the cleanest ready options."
        ),
        Row(
            category: "Cereals",
            avoidBarcode: "0016000224766", avoidName: "Cinnamon Toast Crunch", avoidBrand: "General Mills", avoidScore: 25,
            avoidBullets: ["• Added sugar", "• Flavorings & color"],
            betterBarcode: "0030000013206", betterName: "Quaker Old Fashioned Oats", betterBrand: "Quaker", betterScore: 78,
            betterBullets: ["✓ 100 % whole grain oats", "✓ No added sugar"],
            footer: "Swap sugary cereals for plain oats — add your own fruit for natural sweetness."
        ),
        Row(
            category: "Sweet snacks",
            avoidBarcode: "0044000030148", avoidName: "Oreo Cookies", avoidBrand: "Nabisco", avoidScore: 22,
            avoidBullets: ["• High sugar", "• Ultra-processed"],
            betterBarcode: "0602652101309", betterName: "KIND Dark Chocolate Nuts & Sea Salt", betterBrand: "KIND", betterScore: 62,
            betterBullets: ["✓ Whole nuts & seeds", "✓ Less refined ingredients"],
            footer: "If you want something sweet, reach for a bar with whole ingredients and less refined sugar."
        ),
        Row(
            category: "Nut butters",
            avoidBarcode: "0037600388139", avoidName: "Jif Creamy Peanut Butter", avoidBrand: "Jif", avoidScore: 38,
            avoidBullets: ["• Added sugar & hydrogenated oils", "• Artificial stabilizers"],
            betterBarcode: "0894922001036", betterName: "Justin’s Classic Almond Butter", betterBrand: "Justin’s", betterScore: 72,
            betterBullets: ["✓ Two ingredients only", "✓ No hydrogenated oils"],
            footer: "Look for nut butters with just one or two ingredients — nuts and maybe salt."
        ),
        Row(
            category: "Soft drinks",
            avoidBarcode: "5449000214218", avoidName: "Pepsi Cola", avoidBrand: "PepsiCo", avoidScore: 30,
            avoidBullets: ["• Added sugar", "• Caramel color"],
            betterBarcode: "80872001", betterName: "S.Pellegrino Sparkling Water", betterBrand: "S.Pellegrino", betterScore: 85,
            betterBullets: ["✓ No additives", "✓ Natural carbonation"],
            footer: "Rotate away from colas — sparkling mineral water gives the fizz without the additives."
        )
    ]

    /// All rows with duplicate barcodes removed — each product appears at most once.
    static var uniqueRows: [Row] {
        var seen = Set<String>()
        return rows.filter { row in
            guard seen.isDisjoint(with: [row.avoidBarcode, row.betterBarcode]) else { return false }
            seen.insert(row.avoidBarcode)
            seen.insert(row.betterBarcode)
            return true
        }
    }
}

// MARK: - Open Food Facts raw fetch

/// Open Food Facts may index the same pack as 12-digit UPC-A or 13-digit EAN-13 (leading `0`). Try both.
enum LabelyBarcodeNormalization {
    /// Some packs use a **link** (often read as `http…`); that’s not a GTIN. Taking digits from a URL can yield garbage (e.g. `1`).
    static func isNonProductUrl(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return true }
        if t.contains("://") { return true }
        return false
    }
    
    /// GTIN-style codes used with OFF: EAN-8, UPC-A, EAN-13, ITF-14 (8…14 digits). Shorter strings are not valid product IDs.
    static func candidates(from raw: String) -> [String] {
        if isNonProductUrl(raw) { return [] }
        let digits = raw.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        func append(_ s: String) {
            if seen.insert(s).inserted { out.append(s) }
        }
        append(digits)
        if digits.count == 12 {
            append("0" + digits)
        }
        if digits.count == 13, digits.hasPrefix("0") {
            append(String(digits.dropFirst()))
        }
        return out
    }
}

enum LabelyProductLookupError: LocalizedError {
    case notFoundInOpenFoodFacts
    case invalidBarcode
    /// e.g. SmartLabel / brand link encoded as a URL — not the striped UPC/EAN product number.
    case scannedLinkNotProductGtin
    
    var errorDescription: String? {
        switch self {
        case .notFoundInOpenFoodFacts:
            return "This product isn’t in Open Food Facts yet, or the code didn’t match. Try again with a straight-on view of the barcode, or search the Food database tab."
        case .invalidBarcode:
            return "That scan didn’t produce a valid product code. Try scanning the main pack barcode again."
        case .scannedLinkNotProductGtin:
            return "That scan looks like a website link, not the product number Open Food Facts needs. Use the tall striped barcode with the digits printed under it (UPC/EAN)—usually away from any square or link-style code on the label."
        }
    }
}

enum LabelyOFFFetch {
    /// Returns the OFF `product` object and the **barcode key that worked** (may differ from the raw scan, e.g. EAN-13 form).
    static func fetchProductDictionary(barcode raw: String) async throws -> (product: [String: Any], resolvedBarcode: String) {
        if LabelyBarcodeNormalization.isNonProductUrl(raw) {
            LabelyLog.off.error("OFF rejected URL/link scan (not GTIN) raw=\(raw, privacy: .public)")
            throw LabelyProductLookupError.scannedLinkNotProductGtin
        }
        let candidates = LabelyBarcodeNormalization.candidates(from: raw)
        LabelyLog.off.debug("OFF fetch start raw=\(raw, privacy: .public) candidates=\(candidates.joined(separator: ","), privacy: .public)")
        guard !candidates.isEmpty else {
            LabelyLog.off.error("OFF no valid GTIN candidates from raw=\(raw, privacy: .public)")
            throw LabelyProductLookupError.invalidBarcode
        }
        for code in candidates {
            do {
                if let product = try await fetchProductOnce(barcode: code) {
                    LabelyLog.off.info("OFF hit barcode=\(code, privacy: .public) (from raw=\(raw, privacy: .public))")
                    return (product, code)
                }
                LabelyLog.off.debug("OFF no product for barcode=\(code, privacy: .public), trying next candidate")
            } catch {
                // UPC/EAN candidates often include one representation OFF does not index (404).
                // Keep trying the remaining candidates unless transport is clearly unavailable.
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain {
                    switch ns.code {
                    case NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                        LabelyLog.off.error("OFF transport failed barcode=\(code, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        throw error
                    default:
                        LabelyLog.off.debug("OFF candidate failed (continuing) barcode=\(code, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        continue
                    }
                }
                LabelyLog.off.debug("OFF candidate failed (continuing) barcode=\(code, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        LabelyLog.off.error("OFF exhausted candidates, not in database raw=\(raw, privacy: .public)")
        throw LabelyProductLookupError.notFoundInOpenFoodFacts
    }
    
    /// `nil` = HTTP OK but product not in database for this code. Throws on network / parse failures.
    private static func fetchProductOnce(barcode: String) async throws -> [String: Any]? {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        components.queryItems = [URLQueryItem(name: "lc", value: "en")]
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            LabelyLog.off.debug("OFF HTTP 404 miss barcode=\(barcode, privacy: .public)")
            return nil
        }
        guard (200...299).contains(http.statusCode) else {
            LabelyLog.off.error("OFF bad HTTP status=\(http.statusCode) for barcode=\(barcode, privacy: .public)")
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            LabelyLog.off.error("OFF JSON parse failed barcode=\(barcode, privacy: .public)")
            throw URLError(.cannotParseResponse)
        }
        let status = json["status"] as? Int ?? 0
        let statusVerbose = json["status_verbose"] as? String ?? ""
        guard status == 1, let product = json["product"] as? [String: Any] else {
            LabelyLog.off.debug("OFF API miss barcode=\(barcode, privacy: .public) status=\(status) status_verbose=\(statusVerbose, privacy: .public)")
            return nil
        }
        return product
    }
    
    static func summaryLines(from product: [String: Any]) -> String {
        let nameEn = product["product_name_en"] as? String ?? ""
        let name = product["product_name"] as? String ?? ""
        let brands = product["brands"] as? String ?? ""
        let ingEn = product["ingredients_text_en"] as? String ?? ""
        let ing = product["ingredients_text"] as? String ?? ""
        let nova = product["nova_group"] as? Int
        let additives = (product["additives_tags"] as? [String])?.joined(separator: ", ") ?? ""
        let analysis = (product["ingredients_analysis_tags"] as? [String])?.joined(separator: ", ") ?? ""
        return """
        product_name_en: \(nameEn)
        product_name (may be another language): \(name)
        brands: \(brands)
        nova_group: \(nova.map(String.init) ?? "unknown")
        additives_tags: \(additives)
        ingredients_analysis_tags: \(analysis)
        ingredients_text_en: \(ingEn)
        ingredients_text (may be another language): \(ing)
        """
    }
}

// MARK: - Merge OFF facts when AI fields are empty or thin

enum LabelyInsightEnrichment {
    /// Prefer English ingredient list when OFF provides `ingredients_text_en` (EU packs often have French label text only).
    static func preferredIngredientsText(from product: [String: Any]) -> String {
        let keys = ["ingredients_text_en", "ingredients_text_en-US", "ingredients_text"]
        for k in keys {
            if let s = product[k] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
        }
        return ""
    }
    
    /// Prefer Open Food Facts for counts/NOVA when the model omits them; keep AI narrative where present.
    static func merge(insight: LabelyProductInsight, product: [String: Any]) -> LabelyProductInsight {
        var o = insight
        let primary = preferredIngredientsText(from: product)
        let lines = ingredientLines(from: primary)
        
        if !lines.isEmpty {
            o.ingredientsList = lines
        }
        
        var q = o.quickOverview
        if !lines.isEmpty {
            q.totalIngredients = lines.count
        }
        if q.novaGroup == nil, let n = product["nova_group"] as? Int {
            q.novaGroup = n
        }
        if let n = q.novaGroup {
            q.ultraProcessed = (n >= 4)
            let split = naturalSplit(nova: n)
            if (q.naturalPercent == 50 && q.processedPercent == 50) {
                q.naturalPercent = split.natural
                q.processedPercent = split.processed
            }
        }
        if let tags = product["additives_tags"] as? [String], !tags.isEmpty, q.harmfulAdditivesCount == 0 {
            q.harmfulAdditivesCount = tags.count
        }
        let rawIng = product["ingredients_text"] as? String ?? ""
        let ingForOil = primary + " " + rawIng
        q.containsSeedOil = q.containsSeedOil || seedOilHeuristic(ingForOil)
        o.quickOverview = q
        
        if o.healthGrade.score == 0, let n = o.quickOverview.novaGroup {
            o.healthGrade.score = scoreFromNova(n)
            o.healthGrade.label = labelForScore(o.healthGrade.score)
        }
        
        if o.brandTrust.summary.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 {
            let b = (product["brands"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            o.brandTrust.summary = defaultBrandSummary(brand: b, rating: o.brandTrust.rating)
        }
        
        return o
    }
    
    private static func ingredientLines(from text: String) -> [String] {
        let parts = text
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(parts.prefix(80))
    }
    
    private static func naturalSplit(nova: Int) -> (natural: Int, processed: Int) {
        switch nova {
        case 1: return (88, 12)
        case 2: return (72, 28)
        case 3: return (50, 50)
        case 4: return (35, 65)
        default: return (50, 50)
        }
    }
    
    private static func seedOilHeuristic(_ text: String) -> Bool {
        let t = text.lowercased()
        let needles = [
            "canola", "soybean oil", "corn oil", "vegetable oil", "sunflower oil", "safflower", "cottonseed oil", "grapeseed",
            "huile de tournesol", "huile de colza", "huile de soja", "tournesol"
        ]
        return needles.contains { t.contains($0) }
    }
    
    private static func scoreFromNova(_ nova: Int) -> Int {
        switch nova {
        case 1: return 82
        case 2: return 68
        case 3: return 52
        case 4: return 30
        default: return 48
        }
    }
    
    private static func labelForScore(_ s: Int) -> String {
        if s >= 75 { return "Excellent" }
        if s >= 55 { return "Good" }
        if s >= 35 { return "Fair" }
        return "Poor"
    }
    
    private static func defaultBrandSummary(brand: String, rating: String) -> String {
        let b = brand.isEmpty ? "This brand" : brand
        switch rating.lowercased() {
        case "clear":
            return "\(b): No major transparency flags from Open Food Facts additives and analysis tags. We still recommend checking recalls and independent tests for your region."
        case "orange":
            return "\(b): Some additives or processing flags appear in Open Food Facts data—review ingredients and sourcing."
        case "red":
            return "\(b): Several additive or processing concerns appear in Open Food Facts data—consider alternatives when possible."
        default:
            return "\(b): Limited brand-level safety data in this response—verify with recalls and trusted third-party sources."
        }
    }
}

// MARK: - OpenAI analysis

actor ProductInsightAnalyzer {
    static let shared = ProductInsightAnalyzer()
    
    func analyze(barcode: String, openFoodProduct: [String: Any]) async throws -> LabelyProductInsight {
        let context = LabelyOFFFetch.summaryLines(from: openFoodProduct)
        let prompt = """
        You are Labely, a product transparency assistant. Use ONLY the Open Food Facts context below. Prefer **English** ingredient lines: when `ingredients_text_en` is present, split THAT for ingredientsList and counts; otherwise use `ingredients_text`. Never invent specific lawsuit names, recall IDs, or lab measurements—use generic phrasing.
        Populate the JSON richly so the app can show a full results screen:
        - healthGrade.score: 0–100 overall transparency/safety (lower for ultra-processed NOVA 4, many risky additives).
        - quickOverview: harmfulAdditivesCount should reflect additives of concern from tags/ingredients; totalIngredients = count of distinct ingredients from the English-preferred ingredient text (split on commas); ultraProcessed true if nova_group is 4 or clearly UPF; naturalPercent + processedPercent should sum to 100 and reflect NOVA/ingredient quality.
        - ingredientsList: split the English-preferred ingredients string into a clean array of ingredient lines (trim, no empty strings). Use English names only when available from the context.
        - additives: up to 8 notable additives with plain-English descriptions and category (e.g. SWEETENER, EMULSIFIER). Use E-codes from tags when present.
        - brandTrust.rating: Clear | Orange | Red based on additive load and data quality; summary: 2–4 sentences, no fake legal claims.
        - microplasticRisk & heavyMetalRisk: conservative Unknown/Low unless clearly implied; notes must not cite fake studies.
        Return ONLY valid minified JSON (no markdown):
        {
          "healthGrade": { "score": 0-100, "label": "Poor|Fair|Good|Excellent" },
          "quickOverview": {
            "harmfulAdditivesCount": Int,
            "containsSeedOil": Bool,
            "totalIngredients": Int,
            "ultraProcessed": Bool,
            "novaGroup": Int or null,
            "naturalPercent": Int,
            "processedPercent": Int
          },
          "ingredientsList": [String],
          "brandTrust": { "rating": "Clear|Orange|Red", "summary": String },
          "additives": [{ "name": String, "code": String or null, "risk": "Low|Moderate|High", "category": String, "description": String }],
          "microplasticRisk": { "level": "Unknown|Low|Moderate|High", "note": String },
          "heavyMetalRisk": {
            "level": "Unknown|Low|Moderate|High",
            "score": 0-100,
            "note": String,
            "metals": [{ "symbol": String, "name": String or null, "level": "Low|Moderate|High|Very High", "note": String or null }]
          }
        }
        Barcode: \(barcode)
        Open Food Facts:
        \(context)
        """
        let raw = try await OpenAIService.shared.generateCompletion(
            prompt: prompt,
            model: "gpt-4o-mini",
            maxTokens: 2800,
            temperature: 0.22
        )
        let jsonString = Self.extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8) else {
            throw LabelyAnalysisError.badResponse
        }
        do {
            let decoded = try JSONDecoder().decode(LabelyProductInsight.self, from: data)
            return LabelyInsightEnrichment.merge(insight: decoded, product: openFoodProduct)
        } catch {
            LabelyLog.ai.error("AI JSON decode failed, using fallback: \(error.localizedDescription, privacy: .public)")
            var fb = Self.fallbackInsight(barcode: barcode, raw: raw)
            fb = LabelyInsightEnrichment.merge(insight: fb, product: openFoodProduct)
            return fb
        }
    }
    
    private static func fallbackInsight(barcode: String, raw: String) -> LabelyProductInsight {
        var copy = LabelyProductInsight.empty
        copy.brandTrust.summary = "Could not parse AI response. Raw length: \(raw.count). Barcode: \(barcode)."
        return copy
    }
    
    private static func extractJSON(from text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") {
            return String(t[start...end])
        }
        return t
    }
}

enum LabelyAnalysisError: Error {
    case badResponse
}

// MARK: - QR / barcode from photo library (Vision)

private extension UIImage.Orientation {
    var labelyVisionOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

private enum LabelyLibraryBarcodeError: LocalizedError {
    case couldNotLoadImage
    case noCodeInImage
    case visionProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .couldNotLoadImage: return "Could not load the selected photo."
        case .noCodeInImage: return "No QR code or barcode found in that photo. Try a clearer image."
        case .visionProcessingFailed:
            return "Could not analyze that photo. Try the live scanner, or use a well-lit, straight-on photo of the barcode."
        }
    }
}

private extension UIImage {
    /// Photos (HEIC, etc.) often produce a `UIImage` with no bitmap `cgImage`, which breaks `VNImageRequestHandler` (“Could not create inference context”).
    func labelyRasterizedForBarcodeVision(maxPixelDimension: CGFloat = 4096) -> UIImage {
        let w = size.width * scale
        let h = size.height * scale
        var rw = w
        var rh = h
        let maxSide = max(rw, rh)
        if maxSide > maxPixelDimension {
            let factor = maxPixelDimension / maxSide
            rw *= factor
            rh *= factor
        }
        let outSize = CGSize(width: rw, height: rh)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: outSize))
        }
    }
}

private enum LabelyVisionBarcode {
    static func string(from image: UIImage) throws -> String {
        let handlers = visionHandlers(for: image)
        LabelyLog.vision.debug("Vision barcode handlers count=\(handlers.count) imageSize=\(image.size.width)x\(image.size.height) scale=\(image.scale)")
        guard !handlers.isEmpty else {
            LabelyLog.vision.error("Vision no handlers (could not build image inputs)")
            throw LabelyLibraryBarcodeError.couldNotLoadImage
        }
        
        var lastPerformError: Error?
        for (idx, handler) in handlers.enumerated() {
            let request = makeBarcodeRequest()
            do {
                try handler.perform([request])
            } catch {
                lastPerformError = error
                LabelyLog.vision.error("Vision perform failed handlerIndex=\(idx): \(error.localizedDescription, privacy: .public)")
                continue
            }
            if let obs = request.results as? [VNBarcodeObservation],
               let s = obs.compactMap({ $0.payloadStringValue }).first(where: { !$0.isEmpty }) {
                LabelyLog.vision.info("Vision decoded payload=\(s, privacy: .public)")
                return s
            }
            LabelyLog.vision.debug("Vision handlerIndex=\(idx) produced no barcode observations")
        }
        if let err = lastPerformError {
            let ns = err as NSError
            let msg = ns.localizedDescription.lowercased()
            LabelyLog.vision.error("Vision gave up lastError domain=\(ns.domain, privacy: .public) code=\(ns.code)")
            if msg.contains("inference") || msg.contains("context") {
                throw LabelyLibraryBarcodeError.visionProcessingFailed
            }
        }
        LabelyLog.vision.error("Vision no barcode in image after \(handlers.count) handler(s)")
        throw LabelyLibraryBarcodeError.noCodeInImage
    }
    
    private static func makeBarcodeRequest() -> VNDetectBarcodesRequest {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [
            .qr, .ean13, .ean8, .upce, .code128, .code39, .code93,
            .pdf417, .aztec, .dataMatrix, .i2of5
        ]
        if #available(iOS 17.0, *) {
            request.symbologies.append(.microQR)
        }
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        return request
    }
    
    /// Multiple handlers: raw CGImage, CIImage (when CGImage missing), then rasterized bitmap + CIImage fallback.
    private static func visionHandlers(for image: UIImage) -> [VNImageRequestHandler] {
        var list: [VNImageRequestHandler] = []
        if let cg = image.cgImage {
            list.append(VNImageRequestHandler(
                cgImage: cg,
                orientation: image.imageOrientation.labelyVisionOrientation,
                options: [:]
            ))
        }
        if let ci = CIImage(image: image) {
            list.append(VNImageRequestHandler(ciImage: ci, options: [:]))
        }
        let flat = image.labelyRasterizedForBarcodeVision()
        if flat !== image, let cg = flat.cgImage {
            list.append(VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:]))
        }
        if flat !== image, let ci = CIImage(image: flat) {
            list.append(VNImageRequestHandler(ciImage: ci, options: [:]))
        }
        return list
    }
}

private enum LabelyScanLibraryImport {
    static func barcode(from item: PhotosPickerItem) async throws -> String {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            throw LabelyLibraryBarcodeError.couldNotLoadImage
        }
        return try LabelyVisionBarcode.string(from: image)
    }
}

/// Bottom-left control: pick a photo that contains a QR code or barcode.
private struct ScanPhotoLibraryButton: View {
    @Binding var selection: PhotosPickerItem?
    
    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 54, height: 54)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 3)
        }
        .accessibilityLabel("Choose photo with QR or barcode")
    }
}

// MARK: - Barcode scanner (live auto-detect, no on-screen button or hint text)

final class BarcodeLiveScanViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onBarcode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var lastCode: String?
    private var lastTime: CFTimeInterval = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureSession() }
                }
            }
        default:
            break
        }
    }
    
    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        let meta = AVCaptureMetadataOutput()
        if session.canAddOutput(meta) {
            session.addOutput(meta)
            meta.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            meta.metadataObjectTypes = [
                .ean13, .ean8, .upce, .code128, .code39, .interleaved2of5, .pdf417,
                .dataMatrix, .aztec, .qr
            ]
        }
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let decoded = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .filter { ($0.stringValue ?? "").isEmpty == false }
        guard !decoded.isEmpty else { return }
        // Prefer linear product IDs (UPC/EAN/…) over link-style or matrix codes so a URL payload doesn’t win over the striped code.
        let sorted = decoded.sorted { Self.labelyMetadataPriority($0.type) < Self.labelyMetadataPriority($1.type) }
        guard let obj = sorted.first, let s = obj.stringValue, !s.isEmpty else { return }
        let now = CACurrentMediaTime()
        if s == lastCode, now - lastTime < 0.4 { return }
        lastCode = s
        lastTime = now
        LabelyLog.camera.info("Live scan stringValue=\(s, privacy: .public) type=\(String(describing: obj.type), privacy: .public) (from \(decoded.count) object(s))")
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        session.stopRunning()
        onBarcode?(s)
    }
    
    /// Lower = preferred for Open Food Facts (GTIN-style codes). Link/matrix symbologies last so the striped UPC/EAN wins when both appear.
    private static func labelyMetadataPriority(_ type: AVMetadataObject.ObjectType) -> Int {
        switch type {
        case .ean13, .ean8, .upce:
            return 0
        case .code128, .code39, .interleaved2of5, .itf14, .code93:
            return 1
        case .pdf417:
            return 2
        case .dataMatrix:
            return 3
        case .qr, .aztec:
            return 10
        default:
            return 5
        }
    }
    
    deinit {
        if session.isRunning { session.stopRunning() }
    }
}

struct BarcodeScanView: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void
    
    func makeUIViewController(context: Context) -> BarcodeLiveScanViewController {
        let c = BarcodeLiveScanViewController()
        c.onBarcode = onBarcode
        return c
    }
    
    func updateUIViewController(_ uiViewController: BarcodeLiveScanViewController, context: Context) {}
}

// MARK: - Product image from OFF

enum LabelyProductImage {
    static func url(from product: [String: Any]) -> URL? {
        if let u = product["image_url"] as? String, let url = URL(string: u) { return url }
        if let u = product["image_front_url"] as? String, let url = URL(string: u) { return url }
        return nil
    }
}

// MARK: - Results UI

private struct LabelyScanResultsBackground: View {
    var body: some View {
        ZStack {
            Color.white
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.93, blue: 0.88).opacity(0.55),
                    Color.white.opacity(0)
                ],
                center: UnitPoint(x: 0.92, y: 0.06),
                startRadius: 20,
                endRadius: 380
            )
            RadialGradient(
                colors: [
                    Color(red: 0.86, green: 0.88, blue: 0.91).opacity(0.5),
                    Color.white.opacity(0)
                ],
                center: UnitPoint(x: 0.06, y: 0.10),
                startRadius: 30,
                endRadius: 340
            )
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white],
                startPoint: UnitPoint(x: 0.5, y: 0.32),
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Scan results: section explanations (tap ℹ︎)

private enum LabelyResultsHelpTopic: String, Identifiable {
    case overallGrade
    case quickOverview
    case harmfulAdditives
    case seedOils
    case ingredientCount
    case ultraProcessedNova
    case naturalVsProcessed
    case additivesBreakdown
    case brandTrust
    case microplastic
    case heavyMetal
    
    var id: String { rawValue }
    
    var sheetTitle: String {
        switch self {
        case .overallGrade: return "Health grade"
        case .quickOverview: return "Quick overview"
        case .harmfulAdditives: return "Harmful additives"
        case .seedOils: return "Seed oils"
        case .ingredientCount: return "Ingredient count"
        case .ultraProcessedNova: return "Ultra-processed & NOVA"
        case .naturalVsProcessed: return "Natural vs processed"
        case .additivesBreakdown: return "Additives breakdown"
        case .brandTrust: return "Brand trust"
        case .microplastic: return "Microplastic risk"
        case .heavyMetal: return "Heavy metal risk"
        }
    }
    
    var explanation: String {
        switch self {
        case .overallGrade:
            return "This 0–100 score summarizes how the product’s ingredients, processing level (including NOVA), and flagged additives compare to a cleaner baseline. It is not medical advice—use it to compare similar products and spot higher‑transparency options."
        case .quickOverview:
            return "Quick overview pulls the biggest signals from the label data Labely could read: additives of concern, seed‑oil hints, how many ingredients are listed, and whether the product looks ultra‑processed. Tap each row below for more detail on that metric."
        case .harmfulAdditives:
            return "We count additives that Open Food Facts or ingredient analysis tags flag as higher concern (colors, preservatives, emulsifiers, etc.). Fewer flagged additives usually means simpler formulation—but always read the full ingredient list for your own sensitivities."
        case .seedOils:
            return "We flag common industrial seed oils (soy, canola, corn, cottonseed, etc.) when they appear in the ingredient text. People compare oils for processing and omega‑6 load; Labely highlights presence so you can compare to olive/avocado or other oils you prefer."
        case .ingredientCount:
            return "This is how many distinct ingredients Labely could split from the ingredient text. Longer lists often (not always) mean more processing steps and more chances for additives—compare across similar foods to see simpler alternatives."
        case .ultraProcessedNova:
            return "NOVA groups foods by processing: 1 unprocessed, 2 culinary ingredients, 3 processed, 4 ultra‑processed. NOVA 4 usually means industrial formulations with many ingredients and additives. Labely uses NOVA together with ingredients to estimate how “factory‑made” the product is versus minimally processed options."
        case .naturalVsProcessed:
            return "This bar is a rough split from NOVA and ingredient quality signals—not a lab test. Higher “Natural” suggests fewer industrial ingredients; higher “Processed” suggests more reformulation. Use it to compare siblings (e.g. two ketchups), not as a guarantee of wholesomeness."
        case .additivesBreakdown:
            return "Each card highlights an additive category (sweetener, color, emulsifier, etc.) and why it might matter. Risk tags are conservative summaries from public ingredient data—compare across brands to find simpler formulas with fewer additives."
        case .brandTrust:
            return "This is a transparency and additive‑load snapshot for the brand string on the pack—not a legal verdict. “Clear / Orange / Red” reflects how noisy the formulation looks in Open Food Facts data. Check recalls and third‑party tests separately for your region."
        case .microplastic:
            return "Microplastic exposure from food packaging and supply chains is an active research area. Labely stays conservative: unless sources clearly support a level, we show “Unknown.” Compare packaging choices (glass vs plastic) if you’re reducing plastic contact."
        case .heavyMetal:
            return "Heavy metals (lead, cadmium, arsenic, mercury) can vary by ingredient sourcing and processing. Without product‑specific lab data, Labely shows “Unknown” or conservative estimates. Use certified test results when available for sensitive populations."
        }
    }
}

private struct LabelyHealthScoreRing: View {
    let score: Int
    let tint: Color
    private let size: CGFloat = 84
    private let lineWidth: CGFloat = 5
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, score))) / 100.0)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(tint)
                Text("/ 100")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ProductScanResultView: View {
    let barcode: String
    let productName: String
    let brand: String?
    let imageURL: URL?
    let insight: LabelyProductInsight
    let isLoadingInsight: Bool
    var onDone: () -> Void
    
    @State private var showIngredients = false
    @State private var microExpanded = false
    @State private var metalExpanded = false
    @State private var showDeleteConfirm = false
    @State private var helpTopic: LabelyResultsHelpTopic?
    
    var body: some View {
        NavigationView {
            ZStack {
                LabelyScanResultsBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard
                        if isLoadingInsight {
                            loadingBanner
                        }
                        Group {
                            quickOverviewSection
                            ingredientsToggle
                            brandTrustSection
                            additivesSection
                            microplasticSection
                            heavySection
                        }
                        .redacted(reason: isLoadingInsight ? .placeholder : [])
                        .disabled(isLoadingInsight)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { onDone() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete from recents", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.primary)
                    }
                    .accessibilityLabel("More")
                }
            }
            .alert("Delete this recent scan?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    LabelyScanHistoryStore.shared.remove(barcode: barcode)
                    onDone()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes it from your Recents.")
            }
            .sheet(item: $helpTopic) { topic in
                NavigationView {
                    ScrollView {
                        Text(topic.explanation)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .background(Color.white)
                    .navigationTitle(topic.sheetTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { helpTopic = nil }
                        }
                    }
                }
            }
        }
    }
    
    private func helpButton(_ topic: LabelyResultsHelpTopic) -> some View {
        Button {
            helpTopic = topic
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Explain \(topic.sheetTitle)")
    }
    
    private var loadingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.secondary)
            Text("Loading analysis…")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(.systemGray5)
                    }
                }
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                
                Spacer(minLength: 8)
                
                HStack(spacing: 10) {
                    helpButton(.overallGrade)
                    LabelyHealthScoreRing(score: insight.healthGrade.score, tint: gradeColor)
                }
            }
            
            Text(productName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            if let b = brand, !b.isEmpty {
                Text(b)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(insight.healthGrade.label) Health Grade")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(gradeColor.opacity(0.14))
                    .foregroundColor(gradeColor)
                    .clipShape(Capsule())
                Spacer()
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
    }
    
    private var gradeColor: Color {
        let s = insight.healthGrade.score
        if s >= 70 { return Color(red: 0.2, green: 0.7, blue: 0.35) }
        if s >= 45 { return Color.orange }
        return Color.red
    }
    
    private var quickOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("Quick Overview")
                    .font(.system(size: 20, weight: .bold))
                helpButton(.quickOverview)
                Spacer(minLength: 0)
            }
            VStack(spacing: 12) {
                overviewRow(icon: "exclamationmark.triangle.fill", title: "Harmful additives", value: "\(insight.quickOverview.harmfulAdditivesCount)", valueTint: .orange, help: .harmfulAdditives)
                overviewRow(icon: "leaf.fill", title: "Seed oil", value: insight.quickOverview.containsSeedOil ? "Yes" : "No", valueTint: insight.quickOverview.containsSeedOil ? .orange : Color(red: 0.2, green: 0.65, blue: 0.38), help: .seedOils)
                overviewRow(icon: "list.bullet", title: "Total ingredients", value: "\(insight.quickOverview.totalIngredients)", valueTint: Color(red: 0.2, green: 0.65, blue: 0.38), help: .ingredientCount)
                overviewRow(icon: "gearshape.2.fill", title: "Ultra processed", value: insight.quickOverview.ultraProcessed ? "Yes (NOVA \(insight.quickOverview.novaGroup.map(String.init) ?? "?"))" : "No", valueTint: insight.quickOverview.ultraProcessed ? .red : Color(red: 0.2, green: 0.65, blue: 0.38), help: .ultraProcessedNova)
                naturalBar
                    .padding(.top, 22)
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }
    
    private var naturalBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red.opacity(0.85))
                    .font(.system(size: 16))
                Text("Natural vs processed")
                    .font(.subheadline.weight(.semibold))
                helpButton(.naturalVsProcessed)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(insight.quickOverview.naturalPercent)%")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Color(red: 0.2, green: 0.65, blue: 0.38))
                    Text("/")
                        .foregroundColor(.secondary)
                    Text("\(insight.quickOverview.processedPercent)%")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.red.opacity(0.9))
                }
                .font(.subheadline.monospacedDigit())
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(red: 0.35, green: 0.78, blue: 0.45))
                        .frame(width: g.size.width * CGFloat(insight.quickOverview.naturalPercent) / 100.0)
                    Rectangle()
                        .fill(Color.red.opacity(0.88))
                }
            }
            .frame(height: 9)
            .clipShape(Capsule())
            HStack {
                Label("Natural", systemImage: "circle.fill")
                    .foregroundColor(Color(red: 0.2, green: 0.65, blue: 0.38))
                    .font(.caption2)
                Spacer()
                Label("Processed", systemImage: "circle.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
            }
        }
        .padding(.top, 4)
    }
    
    private func overviewRow(icon: String, title: String, value: String, valueTint: Color, help: LabelyResultsHelpTopic? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(valueTint)
                .font(.system(size: 17))
                .frame(width: 26, alignment: .center)
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                if let help {
                    helpButton(help)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(valueTint.opacity(0.13))
                .foregroundColor(valueTint)
                .clipShape(Capsule())
        }
    }
    
    private var ingredientsToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28)) { showIngredients.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle.fill")
                        .foregroundColor(Color(red: 0.2, green: 0.45, blue: 0.95))
                        .font(.system(size: 20))
                    Text("View Individual Ingredients")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.black)
                    Spacer()
                    Image(systemName: showIngredients ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.45))
                }
                .padding(16)
            }
            .buttonStyle(.plain)
            if showIngredients {
                let split = Self.partitionIngredientsForDisplay(insight.ingredientsList)
                VStack(alignment: .leading, spacing: 14) {
                    ingredientsNaturalBlock(count: split.natural.count, tags: split.natural)
                    ingredientsProcessedBlock(count: split.processed.count, tags: split.processed)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
    
    /// Split ingredient lines into “natural” vs more processed/additive-like for tag display.
    private static func partitionIngredientsForDisplay(_ lines: [String]) -> (natural: [String], processed: [String]) {
        let processedHints = ["e1", "e2", "e3", "e4", "e5", "e6", "e9", "sugar", "syrup", "dextrose", "starch", "modified", "lecithin", "emulsifier", "acid", "flavor", "flavour", "color", "colour", "sweetener", "preservative", "nitrite", "phosphate", "citrate", "gum", "mono", "diglyceride", "artificial", "benzoate", "sorbate", "extract", "hydrolyzed", "maltodextrin"]
        var natural: [String] = []
        var processed: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            let looksProcessed = processedHints.contains { lower.contains($0) }
            if looksProcessed { processed.append(line) } else { natural.append(line) }
        }
        if natural.isEmpty, processed.isEmpty { return ([], []) }
        if natural.isEmpty { return (processed, []) }
        if processed.isEmpty { return (natural, []) }
        return (natural, processed)
    }
    
    private func ingredientsNaturalBlock(count: Int, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .foregroundColor(Color(red: 0.2, green: 0.65, blue: 0.38))
                Text("Natural")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.black)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.2, green: 0.65, blue: 0.38))
                    .clipShape(Circle())
                Spacer()
            }
            ingredientTagGrid(tags: tags, tint: Color(red: 0.2, green: 0.65, blue: 0.38))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.96, green: 0.99, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private func ingredientsProcessedBlock(count: Int, tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color.red.opacity(0.85))
                Text("Processed / additives")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.black)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Circle())
                Spacer()
            }
            ingredientTagGrid(tags: tags, tint: Color.red.opacity(0.9))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1.0, green: 0.96, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private func ingredientTagGrid(tags: [String], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(tint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private var brandTrustSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Text("Brand Trust Score")
                    .font(.system(size: 18, weight: .bold))
                helpButton(.brandTrust)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(trustAccent(insight.brandTrust.rating))
                        .frame(width: 8, height: 8)
                    Text(insight.brandTrust.rating)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(severityBackground(insight.brandTrust.rating))
                        .clipShape(Capsule())
                }
            }
            if let b = brand, !b.isEmpty {
                Text(b)
                    .font(.system(size: 22, weight: .bold))
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(insight.brandTrust.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(trustAccent(insight.brandTrust.rating))
                .frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
    
    private func trustAccent(_ r: String) -> Color {
        if r.lowercased() == "clear" { return .green }
        if r.lowercased() == "red" { return .red }
        return .orange
    }
    
    private func severityBackground(_ r: String) -> Color {
        trustAccent(r).opacity(0.15)
    }
    
    private var additivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Additives Breakdown")
                    .font(.system(size: 18, weight: .bold))
                helpButton(.additivesBreakdown)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flask.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("\(insight.additives.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            Text("Chemical additives found in this product.")
                .font(.caption)
                .foregroundColor(.secondary)
            if insight.additives.isEmpty {
                Text("No additive detail returned—try a product with richer Open Food Facts data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(insight.additives) { a in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(a.risk)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(riskTint(a.risk).opacity(0.18))
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                                Text(a.name + (a.code.map { " (\($0))" } ?? ""))
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(a.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(a.category.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(14)
                            .frame(width: 268, alignment: .leading)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.93, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    
    private func riskTint(_ r: String) -> Color {
        if r.lowercased().contains("high") { return .red }
        if r.lowercased().contains("moderate") { return .orange }
        return .green
    }
    
    private var microplasticSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(microplasticDotColor)
                    .frame(width: 8, height: 8)
                Text("Microplastic Risk")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.black)
                helpButton(.microplastic)
                Spacer()
                Text(insight.microplasticRisk.level)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(microplasticAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(riskLevelBackground(insight.microplasticRisk.level))
                    .clipShape(Capsule())
                Image(systemName: microExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.black.opacity(0.45))
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28)) { microExpanded.toggle() }
            }
            if microExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text(microplasticSummaryLine)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.black)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("💡 What this means")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color.black.opacity(0.85))
                        Text(insight.microplasticRisk.note)
                            .font(.subheadline)
                            .foregroundColor(Color.black.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !microplasticPackagingTags.isEmpty {
                        Text("Detected packaging")
                            .font(.caption.weight(.bold))
                            .foregroundColor(Color.black)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(microplasticPackagingTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(Color(red: 0.18, green: 0.49, blue: 0.32))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color(red: 0.91, green: 0.96, blue: 0.91))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.18, green: 0.49, blue: 0.32))
                        Text("Confidence: \(microplasticConfidenceLabel)")
                            .font(.caption)
                            .foregroundColor(Color.black.opacity(0.5))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
    
    private var microplasticDotColor: Color {
        let l = insight.microplasticRisk.level.lowercased()
        if l.contains("high") { return Color.red.opacity(0.9) }
        if l.contains("moderate") { return Color.orange.opacity(0.95) }
        if l.contains("low") { return Color(red: 0.18, green: 0.62, blue: 0.38) }
        return Color.black.opacity(0.35)
    }
    
    private var microplasticAccent: Color {
        let l = insight.microplasticRisk.level.lowercased()
        if l.contains("high") { return .red }
        if l.contains("moderate") { return .orange }
        if l.contains("low") { return Color(red: 0.12, green: 0.49, blue: 0.28) }
        return Color.black.opacity(0.65)
    }
    
    /// First sentence or compact line for the bold summary.
    private var microplasticSummaryLine: String {
        let n = insight.microplasticRisk.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n == "—" { return "Packaging-based microplastic exposure estimate." }
        if let range = n.range(of: ". ") {
            return String(n[..<range.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        return n
    }
    
    private var microplasticPackagingTags: [String] {
        let n = insight.microplasticRisk.note.lowercased()
        var tags: [String] = []
        if n.contains("glass") { tags.append("Glass") }
        if n.contains("metal") || n.contains("steel") || n.contains("tin can") { tags.append("Steel") }
        if n.contains("paper") || n.contains("cardboard") || n.contains("carton") { tags.append("Paper") }
        if n.contains("plastic") || n.contains("pet") || n.contains("polyethylene") { tags.append("Plastic") }
        if n.contains("aluminum") || n.contains("aluminium") { tags.append("Aluminum") }
        return tags
    }
    
    private var microplasticConfidenceLabel: String {
        let l = insight.microplasticRisk.level.lowercased()
        if l == "unknown" { return "Medium" }
        if l.contains("low") || l.contains("high") { return "High" }
        return "Medium"
    }
    
    private func riskLevelBackground(_ level: String) -> Color {
        let l = level.lowercased()
        if l == "high" { return Color.red.opacity(0.14) }
        if l == "moderate" { return Color.orange.opacity(0.16) }
        if l == "low" { return Color.green.opacity(0.14) }
        return Color.gray.opacity(0.14)
    }
    
    private var heavySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(red: 0.18, green: 0.62, blue: 0.38))
                    .frame(width: 8, height: 8)
                Text("Heavy Metal Risk")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.black)
                helpButton(.heavyMetal)
                Spacer()
                Text(insight.heavyMetalRisk.level)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(heavyMetalAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(riskLevelBackground(insight.heavyMetalRisk.level))
                    .clipShape(Capsule())
                Image(systemName: metalExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.black.opacity(0.45))
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.28)) { metalExpanded.toggle() }
            }
            if metalExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Risk Score")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color.black.opacity(0.85))
                            Spacer()
                            Text("\(min(100, max(0, insight.heavyMetalRisk.score)))/100")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(heavyMetalAccent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.black.opacity(0.08))
                                Capsule()
                                    .fill(heavyMetalAccent)
                                    .frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, insight.heavyMetalRisk.score))) / 100.0))
                            }
                        }
                        .frame(height: 6)
                    }
                    if !insight.heavyMetalRisk.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && insight.heavyMetalRisk.note != "—" {
                        Text(insight.heavyMetalRisk.note)
                            .font(.subheadline)
                            .foregroundColor(Color.black.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !insight.heavyMetalRisk.metals.isEmpty {
                        Text("Metal Breakdown")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(Color.black)
                        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                        LazyVGrid(columns: cols, spacing: 10) {
                            ForEach(insight.heavyMetalRisk.metals) { m in
                                heavyMetalMiniCard(m)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
    
    private var heavyMetalAccent: Color {
        riskTint(insight.heavyMetalRisk.level)
    }
    
    private func heavyMetalMiniCard(_ m: LabelyProductInsight.HeavyMetalRisk.MetalRow) -> some View {
        let levelLower = m.level.lowercased()
        let fillRatio: CGFloat = {
            if levelLower.contains("undetect") || levelLower.contains("none") || levelLower.contains("low") { return 0.18 }
            if levelLower.contains("moderate") { return 0.55 }
            if levelLower.contains("high") { return 0.92 }
            return 0.35
        }()
        let barColor: Color = {
            if levelLower.contains("high") { return .red }
            if levelLower.contains("moderate") { return .orange }
            return Color(red: 0.18, green: 0.62, blue: 0.38)
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(m.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(red: 0.18, green: 0.62, blue: 0.38))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(m.name ?? m.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule().fill(barColor).frame(width: max(4, geo.size.width * fillRatio))
                }
            }
            .frame(height: 4)
            Text(m.level)
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color.black.opacity(0.55))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.95, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Brand reports (sample data — replace with API later)

enum LabelyBrandReports {
    static let samples: [BrandReportPreview] = [
        .init(id: "1", brandName: "Starbucks", headline: "Industrial solvents detected in decaf", severity: "Orange", kind: "Lawsuit"),
        .init(id: "2", brandName: "Lindt", headline: "Heavy metals in dark chocolate", severity: "Red", kind: "Lab Test"),
        .init(id: "3", brandName: "PRIME", headline: "PFAS found in hydration drink", severity: "Red", kind: "Lab Test")
    ]
}

// MARK: - Explore tab (search / discovery)

struct ExploreTabView: View {
    @Binding var showFoodDatabase: Bool
    @State private var searchText = ""
    private let chips = ["Snacks", "Drinks", "Cereals", "Bread", "Dairy"]
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Explore")
                    .font(.system(size: 34, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search foods, brands, or categories", text: $searchText)
                        .textInputAutocapitalization(.never)
                }
                .padding(14)
                .background(Color(red: 0.96, green: 0.96, blue: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.top, 12)
                Text("Suggested Categories")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(chips, id: \.self) { c in
                            Text(c)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(red: 0.96, green: 0.96, blue: 0.97))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 10)
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0.2, green: 0.65, blue: 0.35))
                    Text("Search for Products")
                        .font(.title2.weight(.bold))
                    Text("Find products by name, brand, or category")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Browse Open Food Facts database") {
                        showFoodDatabase = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Scan tab + full-screen scan flow

struct ScanSessionResult: Identifiable {
    let id = UUID()
    let barcode: String
    let insight: LabelyProductInsight
    let product: [String: Any]
}

extension ScanSessionResult {
    var displayProductName: String { labelyProductTitle(product) }
    var displayBrand: String? { product["brands"] as? String }
}

// MARK: - Streaming results sheet (open immediately; load progressively)

private struct LabelyPresentedScan: Identifiable, Equatable {
    let id = UUID()
    let rawBarcode: String
}

struct LabelyStreamingScanSheet: View {
    let rawBarcode: String
    var onDone: () -> Void
    
    @State private var resolvedBarcode: String
    @State private var productDict: [String: Any]
    @State private var insight: LabelyProductInsight
    @State private var isLoadingInsight = true
    @State private var loadError: String?
    
    init(rawBarcode: String, onDone: @escaping () -> Void) {
        self.rawBarcode = rawBarcode
        self.onDone = onDone
        
        // Seed the header ASAP from Recents (if available) so we don't show "Loading product…".
        let candidates = LabelyBarcodeNormalization.candidates(from: rawBarcode)
        let seededRecord = candidates
            .compactMap { code in LabelyScanHistoryStore.shared.items.first(where: { $0.barcode == code }) }
            .first
        
        if let r = seededRecord {
            _resolvedBarcode = State(initialValue: r.barcode)
            _productDict = State(initialValue: [
                "product_name": r.productName,
                "brands": r.brand ?? "",
                "image_url": r.imageURL ?? ""
            ])
            var seeded = LabelyProductInsight.empty
            seeded.healthGrade.score = r.healthScore
            _insight = State(initialValue: seeded)
        } else {
            _resolvedBarcode = State(initialValue: rawBarcode)
            _productDict = State(initialValue: [:])
            _insight = State(initialValue: .empty)
        }
    }
    
    var body: some View {
        ZStack {
            if let err = loadError {
                NavigationView {
                    ZStack {
                        LabelyScanResultsBackground()
                        VStack(spacing: 14) {
                            Text("Couldn’t load this product")
                                .font(.system(size: 20, weight: .bold))
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            HStack(spacing: 10) {
                                Button("Close") { onDone() }
                                    .buttonStyle(.bordered)
                                Button("Try again") {
                                    Task { await loadAll(forceRetry: true) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(22)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 5)
                        .padding(.horizontal, 18)
                    }
                }
            } else {
                ProductScanResultView(
                    barcode: resolvedBarcode,
                    productName: labelyProductTitle(productDict),
                    brand: productDict["brands"] as? String,
                    imageURL: LabelyProductImage.url(from: productDict),
                    insight: insight,
                    isLoadingInsight: isLoadingInsight,
                    onDone: onDone
                )
            }
        }
        .task(id: rawBarcode) {
            await loadAll(forceRetry: false)
        }
    }
    
    private func recordHistoryIfPossible(barcode: String, product: [String: Any], score: Int) {
        let name = labelyProductTitle(product)
        let brand = product["brands"] as? String
        let img = (product["image_url"] as? String) ?? (product["image_front_url"] as? String)
        LabelyScanHistoryStore.shared.add(
            barcode: barcode,
            productName: name,
            brand: brand,
            healthScore: score,
            imageURL: img
        )
    }
    
    private func loadAll(forceRetry: Bool) async {
        LabelyLog.ui.info("StreamingSheet loadAll start rawBarcode=\(rawBarcode, privacy: .public) forceRetry=\(forceRetry)")
        if !forceRetry, let cached = LabelyAnalyzeCache.load(barcode: rawBarcode) {
            LabelyLog.ui.info("StreamingSheet cache hit resolved=\(cached.barcode, privacy: .public) product=\(labelyProductTitle(cached.product), privacy: .public)")
            await MainActor.run {
                resolvedBarcode = cached.barcode
                productDict = cached.product
                insight = cached.insight
                isLoadingInsight = false
                loadError = nil
            }
            recordHistoryIfPossible(barcode: cached.barcode, product: cached.product, score: cached.insight.healthGrade.score)
            return
        }
        
        await MainActor.run {
            loadError = nil
            isLoadingInsight = true
            insight = .empty
            productDict = [:]
            resolvedBarcode = rawBarcode
        }
        
        do {
            let (dict, resolved) = try await LabelyOFFFetch.fetchProductDictionary(barcode: rawBarcode)
            LabelyLog.ui.info("StreamingSheet OFF fetched resolved=\(resolved, privacy: .public) product=\(labelyProductTitle(dict), privacy: .public)")
            await MainActor.run {
                productDict = dict
                resolvedBarcode = resolved
            }
            
            let computed = try await ProductInsightAnalyzer.shared.analyze(barcode: resolved, openFoodProduct: dict)
            LabelyLog.ui.info("StreamingSheet insight done resolved=\(resolved, privacy: .public) score=\(computed.healthGrade.score)")
            let session = ScanSessionResult(barcode: resolved, insight: computed, product: dict)
            LabelyAnalyzeCache.save(session)
            recordHistoryIfPossible(barcode: resolved, product: dict, score: computed.healthGrade.score)
            
            await MainActor.run {
                insight = computed
                isLoadingInsight = false
            }
        } catch {
            LabelyLog.ui.error("StreamingSheet load failed rawBarcode=\(rawBarcode, privacy: .public): \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                isLoadingInsight = false
                loadError = labelyUserFacingScanError(error)
            }
        }
    }
}

// MARK: - Cached full analysis (instant reopen; avoids repeat OFF + AI calls)

private enum LabelyAnalyzeCache {
    private static let blobKey = "labely_ai_scan_cache_blob_v2"
    private static let ttl: TimeInterval = 86400 * 14
    private static let maxEntries = 28
    
    private struct Packed: Codable {
        var entries: [String: CachedScan]
    }
    
    private struct CachedScan: Codable {
        let resolvedBarcode: String
        let insight: LabelyProductInsight
        let productJSON: Data
        let savedAt: Date
    }
    
    private static func canonicalDigits(_ barcode: String) -> String {
        barcode.filter(\.isNumber)
    }
    
    static func load(barcode raw: String) -> ScanSessionResult? {
        let packed = loadPacked()
        for code in LabelyBarcodeNormalization.candidates(from: raw) {
            let k = canonicalDigits(code)
            guard !k.isEmpty, let c = packed.entries[k] else { continue }
            guard Date().timeIntervalSince(c.savedAt) <= ttl else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: c.productJSON) as? [String: Any] else { continue }
            LabelyLog.session.info("Analyze cache hit digits=\(k, privacy: .public)")
            return ScanSessionResult(barcode: c.resolvedBarcode, insight: c.insight, product: obj)
        }
        return nil
    }
    
    static func save(_ result: ScanSessionResult) {
        guard JSONSerialization.isValidJSONObject(result.product),
              let pdata = try? JSONSerialization.data(withJSONObject: result.product) else {
            LabelyLog.session.debug("Analyze cache save skipped (product not JSON-serializable)")
            return
        }
        let k = canonicalDigits(result.barcode)
        guard !k.isEmpty else { return }
        var packed = loadPacked()
        packed.entries[k] = CachedScan(
            resolvedBarcode: result.barcode,
            insight: result.insight,
            productJSON: pdata,
            savedAt: Date()
        )
        while packed.entries.count > maxEntries {
            guard let oldestKey = packed.entries.min(by: { $0.value.savedAt < $1.value.savedAt })?.key else { break }
            packed.entries.removeValue(forKey: oldestKey)
        }
        if let data = try? JSONEncoder().encode(packed) {
            UserDefaults.standard.set(data, forKey: blobKey)
        }
    }
    
    private static func loadPacked() -> Packed {
        guard let data = UserDefaults.standard.data(forKey: blobKey),
              let p = try? JSONDecoder().decode(Packed.self, from: data) else {
            return Packed(entries: [:])
        }
        return p
    }
}

/// Shared Open Food Facts fetch + Labely insight (used by scan tab, full-screen scan, and home “recent” replay).
enum LabelyProductScanSession {
    /// - Parameter recordInHistory: When true, dedupes by barcode and moves the scan to the top of recent history.
    /// - Parameter preferCache: When true, returns the last successful analysis for this barcode without repeating Open Food Facts + AI (fast reopen).
    static func analyze(barcode: String, recordInHistory: Bool = true, preferCache: Bool = true) async throws -> ScanSessionResult {
        LabelyLog.session.info("Session analyze start input=\(barcode, privacy: .public) recordHistory=\(recordInHistory) preferCache=\(preferCache)")
        
        if preferCache, let cached = LabelyAnalyzeCache.load(barcode: barcode) {
            if recordInHistory {
                let dict = cached.product
                let name = labelyProductTitle(dict)
                let brand = dict["brands"] as? String
                let img = (dict["image_url"] as? String) ?? (dict["image_front_url"] as? String)
                LabelyScanHistoryStore.shared.add(
                    barcode: cached.barcode,
                    productName: name,
                    brand: brand,
                    healthScore: cached.insight.healthGrade.score,
                    imageURL: img
                )
            }
            return cached
        }
        
        let (dict, resolvedBarcode) = try await LabelyOFFFetch.fetchProductDictionary(barcode: barcode)
        let insight: LabelyProductInsight
        do {
            insight = try await ProductInsightAnalyzer.shared.analyze(barcode: resolvedBarcode, openFoodProduct: dict)
        } catch {
            LabelyLog.ai.error("Product insight (OpenAI) failed after OFF OK resolved=\(resolvedBarcode, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        if recordInHistory {
            let name = labelyProductTitle(dict)
            let brand = dict["brands"] as? String
            let img = (dict["image_url"] as? String) ?? (dict["image_front_url"] as? String)
            LabelyScanHistoryStore.shared.add(
                barcode: resolvedBarcode,
                productName: name,
                brand: brand,
                healthScore: insight.healthGrade.score,
                imageURL: img
            )
        }
        let session = ScanSessionResult(barcode: resolvedBarcode, insight: insight, product: dict)
        LabelyAnalyzeCache.save(session)
        LabelyLog.session.info("Session analyze done resolved=\(resolvedBarcode, privacy: .public) product=\(labelyProductTitle(dict), privacy: .public) score=\(insight.healthGrade.score)")
        return session
    }
}

struct ScanTabView: View {
    @State private var scanKey = UUID()
    @State private var analysisError: String?
    @State private var presentedScan: LabelyPresentedScan?
    @State private var libraryPickerItem: PhotosPickerItem?
    @State private var isReadingLibraryPhoto = false
    
    var body: some View {
        ZStack {
            BarcodeScanView { code in
                Task { await present(barcode: code) }
            }
            .id(scanKey)
            .ignoresSafeArea()
            
            // Minimal prompt on the live camera.
            Text("Scan barcode")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.28))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 18)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            
            VStack {
                Spacer()
                HStack {
                    ScanPhotoLibraryButton(selection: $libraryPickerItem)
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.bottom, 28)
            }
            if isReadingLibraryPhoto {
                Color.black.opacity(0.38).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    Text("Reading code from photo…")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
            }
            if let err = analysisError {
                VStack {
                    Spacer()
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                    Button("Try again") {
                        analysisError = nil
                        scanKey = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 40)
                }
            }
        }
        .onChange(of: libraryPickerItem) { newItem in
            guard let item = newItem else { return }
            Task { await handleLibraryImport(item) }
        }
        .sheet(item: $presentedScan) { item in
            LabelyStreamingScanSheet(
                rawBarcode: item.rawBarcode,
                onDone: { presentedScan = nil; scanKey = UUID() }
            )
        }
    }
    
    private func handleLibraryImport(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isReadingLibraryPhoto = true
            analysisError = nil
        }
        defer {
            Task { @MainActor in
                isReadingLibraryPhoto = false
                libraryPickerItem = nil
            }
        }
        do {
            let code = try await LabelyScanLibraryImport.barcode(from: item)
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            await present(barcode: code)
        } catch {
            let msg: String
            if let le = error as? LocalizedError, let d = le.errorDescription {
                msg = d
            } else {
                msg = error.localizedDescription
            }
            await MainActor.run { analysisError = msg }
        }
    }
    
    private func present(barcode: String) async {
        LabelyLog.ui.info("ScanTab presenting result sheet barcode=\(barcode, privacy: .public)")
        await MainActor.run {
            analysisError = nil
            presentedScan = LabelyPresentedScan(rawBarcode: barcode)
        }
    }
}

/// Maps `URLError`, `LabelyProductLookupError`, etc. to copy suitable for on-screen scan errors.
func labelyUserFacingScanError(_ error: Error) -> String {
    let ns = error as NSError
    LabelyLog.session.debug("User-facing scan error map: description=\(error.localizedDescription, privacy: .public) domain=\(ns.domain, privacy: .public) code=\(ns.code) userInfo=\(String(describing: ns.userInfo), privacy: .public)")
    if let le = error as? LocalizedError, let d = le.errorDescription, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return d
    }
    if ns.domain == NSURLErrorDomain {
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "No internet connection. Check Wi‑Fi or cellular, then try again."
        case NSURLErrorTimedOut:
            return "The request timed out. Try again in a moment."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Couldn’t reach Open Food Facts. Check your connection and try again."
        case NSURLErrorResourceUnavailable:
            return LabelyProductLookupError.notFoundInOpenFoodFacts.errorDescription ?? ns.localizedDescription
        default:
            break
        }
    }
    return ns.localizedDescription
}

private func labelyProductTitle(_ dict: [String: Any]) -> String {
    if let en = dict["product_name_en"] as? String {
        let t = en.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
    }
    guard let s = dict["product_name"] as? String else { return "Product" }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? "Product" : t
}

/// Full-screen flow from Home / FAB: same behavior as tab scan, with Close.
struct LabelyFullScreenScanFlow: View {
    @Binding var isPresented: Bool
    @State private var scanKey = UUID()
    @State private var analysisError: String?
    @State private var presentedScan: LabelyPresentedScan?
    @State private var libraryPickerItem: PhotosPickerItem?
    @State private var isReadingLibraryPhoto = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                BarcodeScanView { code in
                    Task { await present(barcode: code) }
                }
                .id(scanKey)
                .ignoresSafeArea()
                
                // Minimal prompt on the live camera.
                Text("Scan barcode")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.28))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, geo.safeAreaInsets.top + 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                
                VStack {
                    HStack {
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    // Avoid double-counting safe area (keeps X higher like the screenshot).
                    .padding(.top, 10)
                    Spacer()
                    HStack {
                        ScanPhotoLibraryButton(selection: $libraryPickerItem)
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 28)
                }
            if isReadingLibraryPhoto {
                Color.black.opacity(0.38).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    Text("Reading code from photo…")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
            }
            if let err = analysisError {
                VStack {
                    Spacer()
                    Text(err)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Dismiss") {
                        analysisError = nil
                        scanKey = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 40)
                }
            }
        }
        }
        .onChange(of: libraryPickerItem) { newItem in
            guard let item = newItem else { return }
            Task { await handleLibraryImportFullScreen(item) }
        }
        .sheet(item: $presentedScan) { item in
            LabelyStreamingScanSheet(
                rawBarcode: item.rawBarcode,
                onDone: {
                    presentedScan = nil
                    isPresented = false
                }
            )
        }
    }
    
    private func handleLibraryImportFullScreen(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isReadingLibraryPhoto = true
            analysisError = nil
        }
        defer {
            Task { @MainActor in
                isReadingLibraryPhoto = false
                libraryPickerItem = nil
            }
        }
        do {
            let code = try await LabelyScanLibraryImport.barcode(from: item)
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            await present(barcode: code)
        } catch {
            let msg: String
            if let le = error as? LocalizedError, let d = le.errorDescription {
                msg = d
            } else {
                msg = error.localizedDescription
            }
            await MainActor.run { analysisError = msg }
        }
    }
    
    private func present(barcode: String) async {
        LabelyLog.ui.info("FullScreenScan presenting result sheet barcode=\(barcode, privacy: .public)")
        await MainActor.run {
            analysisError = nil
            presentedScan = LabelyPresentedScan(rawBarcode: barcode)
        }
    }
}

struct BrandReportsListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    
    var filtered: [BrandReportPreview] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return LabelyBrandReports.samples }
        return LabelyBrandReports.samples.filter { $0.brandName.lowercased().contains(q) }
    }
    
    var body: some View {
        NavigationView {
            List(filtered) { r in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(severityColor(r.severity).opacity(0.25))
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(r.brandName).font(.headline)
                            Spacer()
                            Text(r.kind).font(.caption2).padding(4).background(Color(.systemGray6)).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Text(r.headline).font(.subheadline).foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Circle().fill(severityColor(r.severity)).frame(width: 8, height: 8)
                            Text(r.severity).font(.caption.weight(.semibold))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .searchable(text: $query, prompt: "Search brands...")
            .navigationTitle("Brand Reports")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
    
    private func severityColor(_ s: String) -> Color {
        if s.lowercased() == "red" { return .red }
        if s.lowercased() == "orange" { return .orange }
        return .green
    }
}

// MARK: - Clean Swaps full-screen catalog

private struct LabelyRemotePackImage: View {
    let barcode: String
    @State private var resolvedURL: URL?

    private var effectiveURL: URL? {
        LabelyOFFHomeExamples.imageURL(barcode: barcode) ?? resolvedURL
    }

    var body: some View {
        LabelyCachedRemoteImage(
            url: effectiveURL,
            placeholderFill: Color(red: 0.94, green: 0.95, blue: 0.96)
        )
        .task(id: barcode) {
            guard LabelyOFFHomeExamples.preloadedImageURLByBarcode[barcode] == nil else { return }
            if let cached = LabelyOFFHomeExamples.runtimeURLsByBarcode[barcode] {
                await MainActor.run { resolvedURL = cached }
                return
            }
            guard let (dict, _) = try? await LabelyOFFFetch.fetchProductDictionary(barcode: barcode),
                  let url = LabelyProductImage.url(from: dict) else { return }
            LabelyOFFHomeExamples.runtimeURLsByBarcode[barcode] = url
            await MainActor.run { resolvedURL = url }
        }
    }
}

struct LabelyCleanSwapsCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(LabelyCleanSwapCatalog.uniqueRows) { row in
                        LabelyCleanSwapCatalogCard(row: row)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
            .background(Color.white)
            .navigationTitle("Clean Swaps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundColor(.black)
                }
            }
        }
        .task { await preloadCatalogImages() }
    }

    /// Concurrently fetches OFF product data for all barcodes not already in the preloaded map,
    /// resolves their image URLs, and warms `LabelyImageMemoryCache` so cards render instantly.
    private func preloadCatalogImages() async {
        let barcodes = LabelyCleanSwapCatalog.uniqueRows
            .flatMap { [$0.avoidBarcode, $0.betterBarcode] }
            .filter { LabelyOFFHomeExamples.preloadedImageURLByBarcode[$0] == nil
                   && LabelyOFFHomeExamples.runtimeURLsByBarcode[$0] == nil }
        guard !barcodes.isEmpty else { return }

        await withTaskGroup(of: (String, URL)?.self) { group in
            for barcode in barcodes {
                group.addTask {
                    guard let (dict, _) = try? await LabelyOFFFetch.fetchProductDictionary(barcode: barcode),
                          let imageURL = LabelyProductImage.url(from: dict) else { return nil }
                    var req = URLRequest(url: imageURL)
                    req.cachePolicy = .returnCacheDataElseLoad
                    if let (data, resp) = try? await URLSession.shared.data(for: req),
                       let http = resp as? HTTPURLResponse,
                       (200...299).contains(http.statusCode),
                       let img = UIImage(data: data), img.size.width > 8 {
                        LabelyImageMemoryCache.shared.setObject(img, forKey: imageURL as NSURL)
                    }
                    return (barcode, imageURL)
                }
            }
            for await result in group {
                if let (barcode, url) = result {
                    LabelyOFFHomeExamples.runtimeURLsByBarcode[barcode] = url
                }
            }
        }
    }
}

private struct LabelyCleanSwapCatalogCard: View {
    let row: LabelyCleanSwapCatalog.Row
    
    private let cardFill = Color(red: 0.96, green: 0.97, blue: 0.97)
    private let avoidRed = Color(red: 0.86, green: 0.2, blue: 0.22)
    private let betterGreen = Color(red: 0.12, green: 0.55, blue: 0.32)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.category)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(betterGreen)
                .clipShape(Capsule())
            HStack(alignment: .top, spacing: 6) {
                swapColumnAvoid
                swapCenterGlyph
                swapColumnBetter
            }
            Text(row.footer)
                .font(.caption)
                .foregroundColor(Color.black.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
    
    private var swapColumnAvoid: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                LabelyRemotePackImage(barcode: row.avoidBarcode)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(avoidRed, lineWidth: 2))
                Text("\(row.avoidScore)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.orange.opacity(0.95))
                    .clipShape(Circle())
                    .padding(4)
            }
            Text("Avoid")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(avoidRed)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(row.avoidName)
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Text(row.avoidBrand)
                .font(.caption2)
                .foregroundColor(Color.black.opacity(0.45))
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(row.avoidBullets.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .foregroundColor(avoidRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var swapCenterGlyph: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(betterGreen)
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("Swap")
                .font(.caption.weight(.bold))
                .foregroundColor(betterGreen)
        }
        .frame(width: 52)
        .padding(.top, 28)
    }
    
    private var swapColumnBetter: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                LabelyRemotePackImage(barcode: row.betterBarcode)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(betterGreen, lineWidth: 2))
                Text("\(row.betterScore)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(betterGreen)
                    .clipShape(Circle())
                    .padding(4)
            }
            Text("Better Choice")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(betterGreen)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(row.betterName)
                .font(.caption.weight(.bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Text(row.betterBrand)
                .font(.caption2)
                .foregroundColor(Color.black.opacity(0.45))
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(row.betterBullets.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .foregroundColor(betterGreen)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}
