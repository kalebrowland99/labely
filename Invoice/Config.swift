import Foundation

enum Config {
    // MARK: - OpenAI Configuration
    /// All OpenAI traffic goes through `openaiChatCompletion` (Firebase); no client-side API key.
    static let defaultModel = "gpt-4-turbo-preview"
    static let defaultMaxTokens = 500
    static let defaultTemperature = 0.7
    
    // MARK: - SerpAPI Configuration
    static let serpAPIKey: String = APIKeys.serpAPI
    
    // MARK: - Tool-specific Configurations
    static let toolConfigs: [String: ToolConfig] = [
        "AI Bar Generator": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 300,
            temperature: 0.8
        ),
        "Alliterate It": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 150,
            temperature: 0.7
        ),
        "Chorus Creator": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 400, 
            temperature: 0.8
        ),
        "Creative One-Liner": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 200,
            temperature: 0.9
        ),
        "Diss Track Generator": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 500,
            temperature: 0.8
        ),
        "Double Entendre": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 200,
            temperature: 0.9
        ),
        "Finisher": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 500,
            temperature: 0.7
        ),
        "Flex-on-'em": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 400,
            temperature: 0.8
        ),
        "Imperfect Rhyme": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 150,
            temperature: 0.7
        ),
        "Industry Analyzer": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 600,
            temperature: 0.3
        ),
        "Quadruple Entendre": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 300,
            temperature: 0.9
        ),
        "Rap Instagram Captions": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 200,
            temperature: 0.8
        ),
        "Rap Name Generator": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 100,
            temperature: 0.9
        ),
        "Shapeshift": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 150,
            temperature: 0.7
        ),
        "Triple Entendre": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 250,
            temperature: 0.9
        ),
        "Ultimate Come Up Song": ToolConfig(
            model: "gpt-4-turbo-preview",
            maxTokens: 500,
            temperature: 0.8
        )
    ]

    // MARK: - Subscription product identifiers (StoreKit)

    /// Active SKUs wired in Xcode / App Store Connect (exactly three: weekly, standard annual, winback annual at its own price).
    enum SubscriptionSKU {
        static let weekly = "com.labely.ios.premium.weekly3"
        static let annualStandard = "com.labely.ios.premium.annual3"
        static let annualWinback = "com.labely.ios.premium.annual.winback3"

        /// Product IDs loaded via `Product.products(for:)`.
        static let storefrontProductIds: [String] = [
            weekly,
            annualStandard,
            annualWinback
        ]

        /// Grandfather prior ASC products so restores / old subscriptions still unlock.
        static let legacyEntitlementIDs: Set<String> = [
            "com.labely.ios.premium.monthly2",
            "com.labely.ios.premium.weekly2",
            "com.labely.ios.premium.annual2",
            "com.labely.ios.premium.annual.winback2"
        ]

        /// Any ID that grants active premium today.
        static var entitlementProductIDs: Set<String> {
            Set(storefrontProductIds).union(legacyEntitlementIDs)
        }
    }
}

struct ToolConfig {
    let model: String
    let maxTokens: Int
    let temperature: Double
} 
