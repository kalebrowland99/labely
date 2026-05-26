import Foundation

// Paywall Configuration Manager
// This allows you to easily switch between hard and soft paywall modes
@MainActor
class PaywallConfigManager: NSObject, ObservableObject {
    static let shared = PaywallConfigManager()
    
    @Published var hardPaywall: Bool = true // Set this to false for soft paywall
    
    private override init() {
        super.init()
        loadConfig()
    }
    
    private func loadConfig() {
        // You can modify this value to switch between paywall modes
        // true = hard paywall (shows winback when user cancels)
        // false = soft paywall (auto-redirects to app when user cancels)
        hardPaywall = true
    }
    
    func togglePaywallMode() {
        hardPaywall.toggle()
        print("🎛️ Paywall mode changed to: \(hardPaywall ? "HARD" : "SOFT")")
    }
}

// MARK: - Instructions for Firebase Remote Config (Future Implementation)
/*
 Paywall flags live in **Firestore** via `RemoteConfigManager` (ContentView.swift):
 - Collection `app_config`, document `paywall_config`
 - `hardpaywall` (bool) — hard vs soft paywall
 - `twopaywall` (bool) — two-step “Unlimited Access” paywall on final onboarding step
 - `twopaywall79` (bool) — when `twopaywall` is on, year purchases **`com.labely.ios.premium.annual2`** with $79.99/yr marketing (strike $799.99, ~90% SAVE); product must exist at that price in ASC
 - `shortonboarding` (bool) — abbreviated v2 flow: welcome → team → motivations → symptoms → symptom results → Lay's chip question ("How do these chips..." → here's why → reveal better alternative) → **rating** → final paywall

To implement Firebase Remote Config in the future:

1. Add Firebase Remote Config to your Xcode project:
   - In Xcode, go to your project settings
   - Select your target
   - Go to "Package Dependencies"
   - Add Firebase Remote Config

2. In Firebase Console:
   - Go to Remote Config
   - Create a parameter called "hardpaywall"
   - Set it as a boolean
   - Set the default value to true
   - Publish the changes

3. Replace PaywallConfigManager with RemoteConfigManager:
   - Import FirebaseRemoteConfig
   - Use RemoteConfig.remoteConfig() to fetch values
   - Set up proper fetch intervals

4. The app will automatically switch between paywall modes based on the Firebase Remote Config value.
*/ 