import Foundation

/// Keys come from the Xcode Run scheme (Environment Variables) or are empty so the app uses Firebase proxies.
/// Do not commit real credentials.
enum APIKeys {
    static let openAI = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    static let serpAPI = ProcessInfo.processInfo.environment["SERP_API_KEY"] ?? ""

    static let googleMaps = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"] ?? ""

    static let mixpanel = ProcessInfo.processInfo.environment["MIXPANEL_TOKEN"] ?? ""

    static let facebookAppID = ProcessInfo.processInfo.environment["FACEBOOK_APP_ID"] ?? ""
    static let facebookClientToken = ProcessInfo.processInfo.environment["FACEBOOK_CLIENT_TOKEN"] ?? ""
    static let facebookDisplayName = "Labely"
}
