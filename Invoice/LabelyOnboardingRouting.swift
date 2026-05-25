import SwiftUI
import AVFoundation
import UIKit
import StoreKit
import ConfettiSwiftUI

/// Which full-screen onboarding stack to present from `ContentView` / `OnboardingView`.
///
/// - `legacy`: Original Labely flow starting at `NameEntryView` (questions → rating → paywall).
/// - `v2`: New default onboarding — build screens here; pull paywall-inspired pieces in as you go.
enum LabelyOnboardingVariant: Equatable {
    case legacy
    case v2

    /// Active onboarding for production. Change to `.legacy` to ship the old flow.
    static let active: LabelyOnboardingVariant = .v2
}

// MARK: - Design tokens (cream + forest green, onboarding reference)

/// “Live cleaner” welcome screen — exact sRGB `#f5f3e8` (0xf5, 0xf3, 0xe8).
private let labelyOnboardingCream = Color(
    red: CGFloat(0xf5) / 255,
    green: CGFloat(0xf3) / 255,
    blue: CGFloat(0xe8) / 255
)
/// Matches `labelyOnboardingCream` for AVPlayer letterboxing behind `resizeAspect` video.
private let labelyOnboardingCreamUIColor = UIColor(
    red: CGFloat(0xf5) / 255,
    green: CGFloat(0xf3) / 255,
    blue: CGFloat(0xe8) / 255,
    alpha: 1
)
/// Corner radius for marketing hero video (rounded over full-width `resizeAspect` frame).
private let labelyOnboardingMarketingVideoCornerRadius: CGFloat = 22
/// Welcome screen hero clip — visibly softer corners than other onboarding slots.
private let labelyOnboardingWelcomeHeroVideoCornerRadius: CGFloat = 28
private let labelyOnboardingPrimaryGreen = Color(red: 74 / 255, green: 103 / 255, blue: 65 / 255)
private let labelyOnboardingTextGreen = Color(red: 49 / 255, green: 81 / 255, blue: 61 / 255)

/// “Choose your team” subtitle — medium olive (Figma).
private let labelyChooseTeamSubtitleOlive = Color(red: 100 / 255, green: 118 / 255, blue: 78 / 255)

/// Picture-option cards — exact sRGB `#f8f8fc`.
private let labelyOnboardingPictureCardFill = Color(
    red: CGFloat(0xf8) / 255,
    green: CGFloat(0xf8) / 255,
    blue: CGFloat(0xfc) / 255
)

/// V2 onboarding header geometry. The back button keeps the same arrow styling, with a larger tap target.
private let labelyV2OnboardingHeaderSideInset: CGFloat = 24
private let labelyV2OnboardingBackButtonSize: CGFloat = 56
private let labelyV2OnboardingHeaderSpacing: CGFloat = 16

/// Bottom CTA bar above the home indicator (same idea as legacy onboarding / scanning step).
private struct LabelyOnboardingHillsBottomChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var appeared = false

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, labelyV2OnboardingHeaderSideInset)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
            .onAppear {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.80).delay(0.22)) {
                    appeared = true
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
    }
}

/// Mascot splash / pledge background — `#38543b` (used below by launch-green bottom chrome).
private let labelySplashScreenUIColor = UIColor(
    red: CGFloat(0x38) / 255,
    green: CGFloat(0x54) / 255,
    blue: CGFloat(0x3b) / 255,
    alpha: 1
)
private let labelySplashScreenCGColor = labelySplashScreenUIColor.cgColor
private let labelyOnboardingLaunchGreen = Color(uiColor: labelySplashScreenUIColor)

/// Step 16 “Behavioral balance” dynamic image screen — `#37663f`.
private let labelyOnboardingBehavioralBalanceBackground = Color(
    red: CGFloat(0x37) / 255,
    green: CGFloat(0x66) / 255,
    blue: CGFloat(0x3f) / 255
)

/// Dark launch-green screens (pledge, etc.): fade behind the bottom CTA so scroll content never hides it.
private struct LabelyOnboardingLaunchGreenBottomChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, labelyV2OnboardingHeaderSideInset)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [
                        labelyOnboardingLaunchGreen.opacity(0),
                        labelyOnboardingLaunchGreen.opacity(0.94),
                        labelyOnboardingLaunchGreen
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
    }
}

/// “Live cleaner. Feel better.” — exact sRGB `#456647` (0x45, 0x66, 0x47).
private let labelyOnboardingSloganUIColor = UIColor(
    red: CGFloat(0x45) / 255,
    green: CGFloat(0x66) / 255,
    blue: CGFloat(0x47) / 255,
    alpha: 1
)
private let labelyOnboardingSloganGreen = Color(uiColor: labelyOnboardingSloganUIColor)

// MARK: - Bundled onboarding-material images

private enum OnboardingMaterialImage {
    static func url(named name: String, ext: String = "png") -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "onboarding-material") {
            return u
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }

    /// Loads from `onboarding-material` (png/jpg/jpeg) first, then root bundle, then `UIImage(named:)`.
    static func resolvedUIImage(named name: String) -> UIImage? {
        if let u = url(named: name, ext: "png"), let img = UIImage(contentsOfFile: u.path) { return img }
        if let u = url(named: name, ext: "jpg"), let img = UIImage(contentsOfFile: u.path) { return img }
        if let u = url(named: name, ext: "jpeg"), let img = UIImage(contentsOfFile: u.path) { return img }
        return UIImage(named: name)
    }

    /// Same as `resolvedUIImage` but prefers **JPEG** when both `.jpg` and `.png` exist (e.g. `depression.jpg` vs `depression.png`).
    static func resolvedUIImagePreferringJPEG(named name: String) -> UIImage? {
        if let u = url(named: name, ext: "jpg"), let img = UIImage(contentsOfFile: u.path) { return img }
        if let u = url(named: name, ext: "jpeg"), let img = UIImage(contentsOfFile: u.path) { return img }
        if let u = url(named: name, ext: "png"), let img = UIImage(contentsOfFile: u.path) { return img }
        return UIImage(named: name)
    }

    @ViewBuilder
    static func swiftUIImage(named name: String) -> some View {
        if let ui = resolvedUIImage(named: name) {
            Image(uiImage: ui)
                .resizable()
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    static func swiftUIImagePreferringJPEG(named name: String) -> some View {
        if let ui = resolvedUIImagePreferringJPEG(named: name) {
            Image(uiImage: ui)
                .resizable()
        } else {
            Color.clear
        }
    }
}

/// Maps `"Kara N."` / `"Emma Klein"` → `testimonial-kara-n` / `testimonial-emma-klein` for square portraits in `onboarding-material/`.
private func labelyOnboardingReviewerPortraitBasename(displayName: String) -> String {
    let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
    let parts = displayName.components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard let firstRaw = parts.first else { return "testimonial-x" }
    let firstSlug = firstRaw.lowercased().filter { $0.isLetter }
    guard parts.count >= 2 else { return "testimonial-\(firstSlug)" }
    let secondSlug = parts[1].lowercased().filter { $0.isLetter }
    guard !secondSlug.isEmpty else { return "testimonial-\(firstSlug)" }
    return "testimonial-\(firstSlug)-\(secondSlug)"
}

/// Reviewer headshot: bundled `testimonial-*` in onboarding-material, optional legacy asset catalog name, then generated portrait.
private struct OnboardingReviewerAvatarView: View {
    let materialBasename: String
    var legacyAssetName: String? = nil
    let initial: String
    let accentColor: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let ui = OnboardingMaterialImage.resolvedUIImage(named: materialBasename) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let legacy = legacyAssetName, UIImage(named: legacy) != nil {
                Image(legacy)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                LabelyGeneratedReviewerAvatar(
                    seed: materialBasename,
                    initial: initial,
                    accentColor: accentColor,
                    size: size
                )
            }
        }
        .overlay(
            Circle()
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct LabelyGeneratedReviewerAvatar: View {
    let seed: String
    let initial: String
    let accentColor: Color
    let size: CGFloat

    private var hash: Int {
        seed.unicodeScalars.reduce(0) { partial, scalar in
            abs((partial &* 31) &+ Int(scalar.value))
        }
    }

    private var skinTone: Color {
        let tones = [
            Color(red: 0.96, green: 0.73, blue: 0.56),
            Color(red: 0.88, green: 0.62, blue: 0.42),
            Color(red: 0.72, green: 0.46, blue: 0.30),
            Color(red: 0.54, green: 0.34, blue: 0.24),
            Color(red: 0.98, green: 0.80, blue: 0.64)
        ]
        return tones[hash % tones.count]
    }

    private var hairColor: Color {
        let colors = [
            Color(red: 0.16, green: 0.10, blue: 0.07),
            Color(red: 0.34, green: 0.20, blue: 0.11),
            Color(red: 0.75, green: 0.50, blue: 0.24),
            Color(red: 0.78, green: 0.72, blue: 0.62),
            Color(red: 0.08, green: 0.08, blue: 0.08)
        ]
        return colors[(hash / 3) % colors.count]
    }

    private var backgroundColors: [Color] {
        [
            accentColor.opacity(0.88),
            Color(red: 0.88, green: 0.93, blue: 0.82),
            Color(red: 0.96, green: 0.90, blue: 0.76)
        ]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.20))
                .frame(width: size * 0.78, height: size * 0.78)
                .offset(x: -size * 0.18, y: -size * 0.20)

            Capsule(style: .continuous)
                .fill(hairColor)
                .frame(width: size * 0.64, height: size * 0.62)
                .offset(y: -size * 0.10)

            Circle()
                .fill(skinTone)
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(y: -size * 0.02)

            if hash.isMultiple(of: 2) {
                RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                    .fill(hairColor)
                    .frame(width: size * 0.50, height: size * 0.18)
                    .offset(y: -size * 0.30)
            }

            HStack(spacing: size * 0.11) {
                Circle()
                    .fill(Color.black.opacity(0.70))
                    .frame(width: size * 0.055, height: size * 0.055)
                Circle()
                    .fill(Color.black.opacity(0.70))
                    .frame(width: size * 0.055, height: size * 0.055)
            }
            .offset(y: -size * 0.04)

            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.55))
                .frame(width: size * 0.18, height: size * 0.035)
                .offset(y: size * 0.12)

            if hash.isMultiple(of: 5) {
                HStack(spacing: size * 0.03) {
                    Circle()
                        .stroke(Color.black.opacity(0.65), lineWidth: max(1, size * 0.025))
                        .frame(width: size * 0.18, height: size * 0.18)
                    Circle()
                        .stroke(Color.black.opacity(0.65), lineWidth: max(1, size * 0.025))
                        .frame(width: size * 0.18, height: size * 0.18)
                }
                .offset(y: -size * 0.04)
            }

            Text(String(initial.prefix(1)).uppercased())
                .font(.system(size: size * 0.22, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.88))
                .offset(x: size * 0.25, y: size * 0.26)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Full-bleed `onboarding-material/bg` (edge-to-edge including home indicator). Uses screen bounds so it is not limited to the `GeometryReader` safe-area height.
private struct OnboardingHillsBackdropView: View {
    private let verticalLayoutBoost: CGFloat = 1.24

    var body: some View {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        return ZStack(alignment: .bottom) {
            OnboardingMaterialImage.swiftUIImage(named: "bg")
                .scaledToFill()
                .frame(width: w, height: h * verticalLayoutBoost, alignment: .bottom)
                .frame(width: w, height: h, alignment: .bottom)
                .clipped()
            Color.white.opacity(0.12)
        }
        .frame(width: w, height: h)
        .clipped()
    }
}

/// Scroll band min height matching `AdditivesToAvoidOnboardingView` so primary choices sit mid-screen above bottom chrome.
private func labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: CGFloat) -> CGFloat {
    max(260, screenHeight - 288)
}

// MARK: - Onboarding press feedback (no default dimming — scale + blur + haptic)

private struct LabelyOnboardingPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .compositingGroup()
            .opacity(1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1, anchor: .center)
            .blur(radius: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                guard pressed else { return }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
    }
}

// MARK: - Roots

/// Preserves the existing onboarding stack without moving it out of `ContentView.swift`.
struct LegacyLabelyOnboardingRootView: View {
    var body: some View {
        NameEntryView()
            .horizontalSlideTransition()
    }
}

/// New onboarding: welcome → choose team → cleaner-product goals → testimonials (×2) → `NameEntryView` questions.
struct NewLabelyOnboardingRootView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    @State private var step: Int = 1
    @State private var isStepInteractive = true
    @State private var showingSignIn = false
    @State private var showingEmailSignIn = false
    @State private var selectedMotivations: Set<LabelyCleanerProductMotivation> = []
    @State private var selectedTeam: LabelyOnboardingTeamChoice = .cleanLivingGirlie
    @State private var selectedSymptoms: Set<LabelySymptomChoice> = []
    @State private var selectedDietaryRestrictions: Set<String> = ["None"]
    @State private var selectedAllergies: Set<String> = ["None"]
    @State private var ultraProcessedFrequencyAnswer: String = "Sometimes"
    @State private var waterFilterAnswer: String = "No"
    @State private var plasticHeatingAnswer: String = "Sometimes"
    @State private var cannedFoodsAnswer: String = "Sometimes"
    @State private var selectedAdditiveChoice: LabelyAdditiveChoice = .allOfTheAbove

    /// Primary motivation drives testimonial content — first match in enum declaration order.
    private var primaryMotivation: LabelyCleanerProductMotivation {
        LabelyCleanerProductMotivation.allCases.first { selectedMotivations.contains($0) } ?? .liveHealthier
    }

    private var testimonialContent: LabelyOnboardingTestimonialContent {
        primaryMotivation.testimonialContent(for: selectedTeam)
    }

    private func navigate(to newStep: Int) {
        guard newStep != step, isStepInteractive else { return }
        isStepInteractive = false
        withAnimation(.easeInOut(duration: 0.42)) {
            step = newStep
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            isStepInteractive = true
        }
    }

    /// Lets the team card’s press animation finish before crossfading to the next step.
    private func navigateAfterTeamSelect(to newStep: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            navigate(to: newStep)
        }
    }

    private var stepCrossfadeTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .opacity
        )
    }

    var body: some View {
        ZStack {
            stepView
                .id(step)
                .transition(stepCrossfadeTransition)
                .allowsHitTesting(isStepInteractive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(
            get: { showingSignIn && !authManager.isLoggedIn },
            set: { showingSignIn = $0 }
        )) {
            SignInView(showingEmailSignIn: $showingEmailSignIn)
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.52)])
                .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(isPresented: $showingEmailSignIn) {
            EmailSignInView()
        }
        .onAppear {
            MixpanelService.shared.trackOnboardingStarted()
        }
    }

    @ViewBuilder private var stepView: some View {
        switch step {
            case 0, 1:
                NewOnboardingWelcomeScreen(
                    onContinue: { navigate(to: 2) },
                    onSignIn: { showingSignIn = true }
                )
            case 2:
                ChooseTeamOnboardingView(
                    headingTitle: remoteConfig.shortOnboarding ? "Which are you?" : "Choose your team",
                    onBack: { navigate(to: 1) },
                    onSelectTeam: { team in
                        selectedTeam = team
                        navigateAfterTeamSelect(to: 3)
                    }
                )
            case 3:
                CleanerProductsMotivationsOnboardingView(
                    onBack: { navigate(to: 2) },
                    onContinue: { motivations in
                        selectedMotivations = motivations
                        navigate(to: 4)
                    }
                )
            case 4:
                Group {
                    if remoteConfig.shortOnboarding {
                        SymptomsSelectionOnboardingView(
                            onBack: { navigate(to: 3) },
                            onContinue: { symptoms in
                                selectedSymptoms = symptoms
                                navigate(to: 5)
                            }
                        )
                    } else {
                TestimonialOnboardingView(
                    review: testimonialContent.first,
                            secondReview: testimonialContent.second,
                    heading: testimonialContent.heading,
                    goalSubtitle: testimonialContent.firstSubtitle,
                            totalSegments: 3, filledSegments: 2,
                            isLastTestimonial: true,
                    onBack: { navigate(to: 3) },
                            onNext: { navigate(to: 9) }
                )
                    }
                }
            case 5:
                Group {
                    if remoteConfig.shortOnboarding {
                        BehavioralBalanceOnboardingView(
                            symptoms: selectedSymptoms,
                            onBack: { navigate(to: 4) },
                            onContinue: { navigate(to: 6) }
                        )
                    } else {
                TestimonialOnboardingView(
                    review: testimonialContent.second,
                            secondReview: nil,
                    heading: testimonialContent.heading,
                    goalSubtitle: testimonialContent.secondSubtitle,
                    totalSegments: 4, filledSegments: 3,
                    isLastTestimonial: true,
                    onBack: { navigate(to: 4) },
                    onNext: { navigate(to: 6) }
                )
                    }
                }
            case 6:
                Group {
                    if remoteConfig.shortOnboarding {
                        LaysChipsEducationOnboardingView(
                            onBack: { navigate(to: 5) },
                            // Pre-paywall: rating → paywall (no try-for-$0 carousel screen).
                            onComplete: { navigate(to: 29) }
                        )
                    } else {
                InsideLabelyOnboardingView(
                    onBack: { navigate(to: 5) },
                    onContinue: { navigate(to: 7) }
                )
                    }
                }
            case 7:
                ScanningAppsQuestionOnboardingView(
                    onBack: { navigate(to: 6) },
                    onAnswer: { navigate(to: 8) }
                )
            case 8:
                OlivePledgeOnboardingView(
                    onBack: { navigate(to: 7) },
                    onContinue: { navigate(to: 9) }
                )
            case 9:
                AdditivesToAvoidOnboardingView(
                    onBack: { navigate(to: 4) },
                    onContinue: { choice in
                        selectedAdditiveChoice = choice
                        navigate(to: 10)
                    }
                )
            case 10:
                ThenVsNowOnboardingView(
                    imageNames: ["ketchup-thenvsnow", "ritz-thenvsnow"],
                    onBack: { navigate(to: 9) },
                    onContinue: { navigate(to: 12) }
                )
            case 11:
                ThenVsNowOnboardingView(
                    imageName: "ritz-thenvsnow",
                    onBack: { navigate(to: 10) },
                    onContinue: { navigate(to: 12) }
                )
            case 12:
                CarcinogenStatsOnboardingView(
                    onBack: { navigate(to: 11) },
                    onContinue: { navigate(to: 15) },
                    team: selectedTeam
                )
            case 13:
                PanicToPlanOnboardingView(
                    onBack: { navigate(to: 12) },
                    onContinue: { navigate(to: 14) }
                )
            case 14:
                NumberOneHealthAppOnboardingView(
                    onPersonalize: { navigate(to: 15) }
                )
            case 15:
                SymptomsSelectionOnboardingView(
                    onBack: { navigate(to: 12) },
                    onContinue: { symptoms in
                        selectedSymptoms = symptoms
                        navigate(to: 16)
                    }
                )
            case 16:
                BehavioralBalanceOnboardingView(
                    symptoms: selectedSymptoms,
                    onBack: { navigate(to: 15) },
                    onContinue: { navigate(to: 17) }
                )
            case 17:
                AlleviateSymptomsBelieveOnboardingView(
                    onBack: { navigate(to: 16) },
                    onReady: { navigate(to: 18) }
                )
            case 18:
                GoalsGraphOnboardingView(
                    onBack: { navigate(to: 17) },
                    onContinue: { navigate(to: 19) }
                )
            case 19:
                FamilyStoryVideoOnboardingView(
                    onBack: { navigate(to: 18) },
                    onSkip: { navigate(to: 20) },
                    onContinue: { navigate(to: 20) }
                )
            case 20:
                LaysChipsEducationOnboardingView(
                    onBack: { navigate(to: 19) },
                    onComplete: { navigate(to: 21) }
                )
            case 21:
                OnboardingFrequencyQuestionView(
                    title: "How often do you eat\nultra-processed foods?",
                    options: ["Daily", "Sometimes", "Never"],
                    onBack: { navigate(to: 20) },
                    onPick: { choice in
                        ultraProcessedFrequencyAnswer = choice
                        navigate(to: 22)
                    }
                )
            case 22:
                OnboardingFrequencyQuestionView(
                    title: "Do you filter your drinking\nwater at home?",
                    options: ["No", "Yes, basic carbon filter (Brita)", "Yes, advanced filter"],
                    onBack: { navigate(to: 21) },
                    onPick: { choice in
                        waterFilterAnswer = choice
                        navigate(to: 23)
                    }
                )
            case 23:
                OnboardingFrequencyQuestionView(
                    title: "Do you heat food in plastic\ncontainers?",
                    options: ["Daily", "Sometimes", "Never"],
                    onBack: { navigate(to: 22) },
                    onPick: { choice in
                        plasticHeatingAnswer = choice
                        navigate(to: 24)
                    }
                )
            case 24:
                OnboardingFrequencyQuestionView(
                    title: "Do you buy canned foods\nregularly?",
                    options: ["Daily", "Sometimes", "Never"],
                    onBack: { navigate(to: 23) },
                    onPick: { choice in
                        cannedFoodsAnswer = choice
                        navigate(to: 25)
                    }
                )
            case 25:
                OnboardingPillSelectionView(
                    title: "Do you have any dietary\nrestrictions?",
                    options: [
                        "None", "Gluten-Free", "Vegan", "Vegetarian", "Pescatarian",
                        "Kosher", "Halal", "Pork-Free", "Palm-Oil-Free", "Seed-Oil-Free",
                        "Lactose-Free", "Folic-Acid-Free", "Fluoride-Free"
                    ],
                    disclaimer: nil,
                    selected: $selectedDietaryRestrictions,
                    onBack: { navigate(to: 24) },
                    onNext: { navigate(to: 26) }
                )
            case 26:
                OnboardingPillSelectionView(
                    title: "Any allergies we should\nknow about?",
                    options: [
                        "None", "Fish", "Dairy", "Eggs", "Soy/Soybeans", "All Nuts",
                        "Peanuts", "Sesame", "Sulfite-Free", "Gluten", "Corn"
                    ],
                    disclaimer: .init(
                        text: "Disclaimer: Labely is not a substitute for medical advice. Always consult your healthcare provider."
                    ),
                    selected: $selectedAllergies,
                    onBack: { navigate(to: 25) },
                    onNext: { navigate(to: 27) }
                )
            case 27:
                SafeguardsLoadingOnboardingView(
                    onBack: { navigate(to: 26) },
                    onFinished: { navigate(to: 28) }
                )
            case 28:
                FoodGuardianSummaryOnboardingView(
                    team: selectedTeam,
                    primaryMotivation: primaryMotivation,
                    selectedMotivations: selectedMotivations,
                    symptoms: selectedSymptoms,
                    dietaryRestrictions: selectedDietaryRestrictions,
                    allergies: selectedAllergies,
                    ultraProcessedAnswer: ultraProcessedFrequencyAnswer,
                    waterFilterAnswer: waterFilterAnswer,
                    plasticHeatingAnswer: plasticHeatingAnswer,
                    cannedFoodsAnswer: cannedFoodsAnswer,
                    selectedAdditiveChoice: selectedAdditiveChoice,
                    onBack: { navigate(to: 27) },
                    onStartJourney: { navigate(to: 29) }
                )
            case 29:
                OnboardingGiveRatingView(
                    onBack: { navigate(to: remoteConfig.shortOnboarding ? 6 : 28) },
                    onNext: { navigate(to: 34) }
                )
            case 34:
                OnboardingFinalPaywallView(
                    onBack: { navigate(to: 29) },
                    onFinished: { navigate(to: 36) }
                )
            case 36:
                NameEntryView()
                    .horizontalSlideTransition()
            default:
                NameEntryView()
                    .horizontalSlideTransition()
            }
    }
}

// MARK: - "Avoiding bad ingredients can be tough..." (steps 10 & 11)

private struct ThenVsNowOnboardingView: View {
    let imageNames: [String]
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var imageIndex = 0
    @State private var slideDirection = 1

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    init(imageName: String, onBack: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.imageNames = [imageName]
        self.onBack = onBack
        self.onContinue = onContinue
    }

    init(imageNames: [String], onBack: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.imageNames = imageNames
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        GeometryReader { geo in
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: goBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.white)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let segW = (g.size.width - spacing) / 2
                            HStack(spacing: spacing) {
                                ForEach(0..<2, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(i <= imageIndex ? labelyOnboardingPrimaryGreen : Color.white.opacity(0.42))
                                        .frame(width: segW, height: 5)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text("Avoiding bad ingredients\ncan be tough...")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            OnboardingMaterialImage.swiftUIImage(named: imageNames[min(imageIndex, imageNames.count - 1)])
                                .scaledToFit()
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .id(imageIndex)
                                .transition(.asymmetric(
                                    insertion: .move(edge: slideDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: slideDirection > 0 ? .leading : .trailing).combined(with: .opacity)
                                ))

                            Text("*because our food has changed.*")
                                .font(.system(size: 15, weight: .regular).italic())
                                .foregroundColor(labelyChooseTeamSubtitleOlive)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.top, 16)
                                .padding(.bottom, 24)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: advanceImageOrContinue) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
    }

    private func advanceImageOrContinue() {
        if imageIndex < imageNames.count - 1 {
            slideDirection = 1
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                imageIndex += 1
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        } else {
            onContinue()
        }
    }

    private func goBack() {
        if imageIndex > 0 {
            slideDirection = -1
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                imageIndex -= 1
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            onBack()
        }
    }
}

// MARK: - "And it's destroying our bodies." (step 12)

private struct CarcinogenStatsOnboardingView: View {
    let onBack: () -> Void
    let onContinue: () -> Void
    let team: LabelyOnboardingTeamChoice

    @State private var flagCarcinogens = false

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset
    /// Figma: bold italic terracotta for statistic emphasis (not bright red).
    private let carcinogenHighlightTerracotta = Color(red: 0.58, green: 0.31, blue: 0.23)

    private var carcinogenFigmaBody: Text {
        team.ultraProcessedRiskText(
            baseSize: 30,
            green: labelyOnboardingTextGreen,
            accent: carcinogenHighlightTerracotta
        )
    }

    var body: some View {
        GeometryReader { geo in
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                labelyOnboardingCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(labelyOnboardingTextGreen)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let segW = (g.size.width - spacing) / 2
                            HStack(spacing: spacing) {
                                ForEach(0..<2, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(i == 0 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.25))
                                        .frame(width: segW, height: 5)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text("And it's destroying\nour bodies.")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            carcinogenFigmaBody
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .minimumScaleFactor(0.65)
                                .padding(.horizontal, 28)
                                .padding(.top, 28)

                            HStack(spacing: 12) {
                                Text(team.ultraProcessedToggleLabel)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.50, green: 0.50, blue: 0.50))

                                Spacer(minLength: 0)

                                Toggle("", isOn: $flagCarcinogens)
                                    .labelsHidden()
                                    .tint(labelyOnboardingPrimaryGreen)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
                            )
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 28)

                            Text(team.ultraProcessedSource)
                                .font(.system(size: 12, weight: .regular))
                                .italic()
                                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                                .padding(.top, 20)
                                .padding(.bottom, 24)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: onContinue) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(flagCarcinogens ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.45)))
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                        .disabled(!flagCarcinogens)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
    }
}

private extension LabelyOnboardingTeamChoice {
    func ultraProcessedRiskText(baseSize: CGFloat, green: Color, accent: Color) -> Text {
        let base = Font.system(size: baseSize, weight: .regular)
        let emphasis = Font.system(size: baseSize, weight: .bold).italic()
        switch self {
        case .holisticHealthBro:
            return Text("Men who eat the most\n")
                .font(base).foregroundColor(green)
                + Text("ultra-processed foods\n")
                .font(emphasis).foregroundColor(accent)
                + Text("have ")
                .font(base).foregroundColor(green)
                + Text("6x higher odds ")
                .font(emphasis).foregroundColor(accent)
                + Text("of\nhaving ")
                .font(base).foregroundColor(green)
                + Text("testosterone\ndeficiency")
                .font(emphasis).foregroundColor(accent)
        case .mamaBearProtector, .wellnessWarriorDad:
            return Text("If a child's blood-lead\nconcentration creeps up\nby just ")
                .font(base).foregroundColor(green)
                + Text("0.000005 grams")
                .font(emphasis).foregroundColor(accent)
                + Text(",\nstudies show they lose\nabout ")
                .font(base).foregroundColor(green)
                + Text("5 IQ points for\nlife.*")
                .font(emphasis).foregroundColor(accent)
        case .cleanLivingGirlie:
            return Text("Women who eat the most\n")
                .font(base).foregroundColor(green)
                + Text("ultra-processed foods\n")
                .font(emphasis).foregroundColor(accent)
                + Text("have almost ")
                .font(base).foregroundColor(green)
                + Text("4x higher\n")
                .font(emphasis).foregroundColor(accent)
                + Text("odds ")
                .font(emphasis).foregroundColor(accent)
                + Text("of developing\n")
                .font(base).foregroundColor(green)
                + Text("breast cancer")
                .font(emphasis).foregroundColor(accent)
        }
    }

    var ultraProcessedToggleLabel: String {
        switch self {
        case .cleanLivingGirlie:
            return "Flag carcinogens"
        case .holisticHealthBro:
            return "Boost Testosterone\nNaturally"
        case .mamaBearProtector:
            return "Turn on Kid-Safe Mode"
        case .wellnessWarriorDad:
            return "Turn on Kid-Safe Mode"
        }
    }

    var ultraProcessedSource: String {
        switch self {
        case .holisticHealthBro:
            return "Source: Hu et al. (2018). Nutrients."
        case .mamaBearProtector, .wellnessWarriorDad:
            return "*5 µg/dL to 10 µg/dL. Source: Jusko et al. (2008), Environmental Health Perspectives."
        case .cleanLivingGirlie:
            return "Source: Nouri et al. (2024). BMC Cancer."
        }
    }
}

// MARK: - "Labely is your trusted guide from panic to plan" (step 13)

private struct PanicToPlanOnboardingView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    var body: some View {
        GeometryReader { geo in
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            let panicImageWidth = geo.size.width - 8
            let panicImageHeight = max(geo.size.height * 0.52, bandMin * 0.92)
            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.white)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let segW = (g.size.width - spacing) / 2
                            HStack(spacing: spacing) {
                                ForEach(0..<2, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(i == 0 ? labelyOnboardingPrimaryGreen : Color.white.opacity(0.42))
                                        .frame(width: segW, height: 5)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text("Labely is your trusted guide\nfrom panic to plan")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            OnboardingMaterialImage.swiftUIImage(named: "panic-to-plan")
                                .scaledToFit()
                                .frame(width: panicImageWidth, height: panicImageHeight)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 4)
                                .padding(.bottom, 8)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: onContinue) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - "#1 holistic health app" (step 14)

private struct NumberOneHealthAppOnboardingView: View {
    let onPersonalize: () -> Void

    var body: some View {
        ZStack {
            labelyOnboardingCream.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        OnboardingMaterialImage.swiftUIImage(named: "#1-health-app")
                            .scaledToFit()
                            .padding(.horizontal, 40)
                            .padding(.top, 20)

                        Text("Take your health & well-being\nto the next level with Labely")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 24)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LabelyOnboardingHillsBottomChrome {
                Button(action: onPersonalize) {
                    Text("Personalize my experience")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
            }
        }
    }
}

// MARK: - Symptoms selection (short + long onboarding)

private enum LabelySymptomChoice: Int, CaseIterable, Identifiable {
    case lowEnergy, brainFog, anxiety, depression, sleepProblems, weightGain, hyperactivity, behavioralIssues
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .lowEnergy:         return "Low energy"
        case .brainFog:          return "Brain fog"
        case .anxiety:           return "Anxiety"
        case .depression:        return "Depression"
        case .sleepProblems:     return "Sleep problems"
        case .weightGain:        return "Weight gain"
        case .hyperactivity:     return "Hyperactivity"
        case .behavioralIssues:  return "Behavioral issues"
        }
    }

    var imageName: String {
        switch self {
        case .lowEnergy:         return "low-energy"
        case .brainFog:          return "brain-fog"
        case .anxiety:           return "anxiety"
        case .depression:        return "depression"
        case .sleepProblems:     return "sleep-problems"
        case .weightGain:        return "weight-gain"
        case .hyperactivity:     return "hyperactivity"
        case .behavioralIssues:  return "behavior-issues"
        }
    }
}

private struct SymptomsSelectionOnboardingView: View {
    let onBack: () -> Void
    let onContinue: (Set<LabelySymptomChoice>) -> Void

    @State private var selected: Set<LabelySymptomChoice> = []

    private let gridSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = labelyV2OnboardingHeaderSideInset
    private let symptomCardCornerRadius: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let gridWidth = geo.size.width - horizontalPadding * 2
            let columnWidth = (gridWidth - gridSpacing) / 2
            let gridMinHeight = max(300, geo.size.height - 280)
            ZStack {
                labelyOnboardingCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(labelyOnboardingTextGreen)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let segW = (g.size.width - spacing) / 2
                            HStack(spacing: spacing) {
                                ForEach(0..<2, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(i == 0 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.25))
                                        .frame(width: segW, height: 5)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text("What are you suffering from?")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(minimum: 0), spacing: gridSpacing),
                                    GridItem(.flexible(minimum: 0), spacing: gridSpacing)
                                ],
                                spacing: gridSpacing
                            ) {
                                ForEach(LabelySymptomChoice.allCases) { symptom in
                                    SymptomPictureButton(
                                        symptom: symptom,
                                        columnWidth: columnWidth,
                                        cardCornerRadius: symptomCardCornerRadius,
                                        isSelected: selected.contains(symptom),
                                        onTap: {
                                            if selected.contains(symptom) {
                                                selected.remove(symptom)
                                            } else {
                                                selected.insert(symptom)
                                            }
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                    )
                                }
                            }
                            .frame(width: gridWidth)
                            .frame(maxWidth: .infinity)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: gridMinHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        VStack(spacing: 16) {
                            Button(action: { onContinue([]) }) {
                                Text("Skip for now")
                                    .font(.system(size: 15, weight: .regular))
                                    .underline()
                                    .foregroundColor(labelyOnboardingTextGreen.opacity(0.55))
                            }
                            .buttonStyle(.plain)

                            Button(action: { onContinue(selected) }) {
                                Text("Continue")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(Capsule().fill(selected.isEmpty ? labelyOnboardingPrimaryGreen.opacity(0.45) : labelyOnboardingPrimaryGreen))
                            }
                            .buttonStyle(LabelyOnboardingPressableButtonStyle())
                            .disabled(selected.isEmpty)
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

private struct SymptomPictureButton: View {
    let symptom: LabelySymptomChoice
    let columnWidth: CGFloat
    let cardCornerRadius: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    /// Same width-relative image band as `motivationCard` (~0.58–0.78 × column width).
    private var imageBandHeight: CGFloat { columnWidth * 0.72 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                OnboardingMaterialImage.swiftUIImage(named: symptom.imageName)
                    .scaledToFill()
                    .frame(width: columnWidth, height: imageBandHeight)
                    .clipped()
                    .contentShape(Rectangle())

                Text(symptom.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isSelected ? labelyOnboardingPrimaryGreen : labelyOnboardingTextGreen.opacity(0.78))
                    )
                    .padding(8)
            }
            .frame(width: columnWidth, height: imageBandHeight)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? labelyOnboardingPrimaryGreen : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(LabelyOnboardingPressableButtonStyle())
    }
}

// MARK: - "You Can Improve X Naturally" (step 16) — dynamic based on selected symptoms

private struct BehavioralBalanceOnboardingView: View {
    let symptoms: Set<LabelySymptomChoice>
    let onBack: () -> Void
    let onContinue: () -> Void

    private let bg = labelyOnboardingBehavioralBalanceBackground

    /// Priority order when multiple symptoms are selected.
    private static let priorityOrder: [LabelySymptomChoice] = [
        .behavioralIssues, .hyperactivity, .anxiety, .depression,
        .brainFog, .sleepProblems, .lowEnergy, .weightGain
    ]

    private var primarySymptom: LabelySymptomChoice? {
        for s in Self.priorityOrder where symptoms.contains(s) { return s }
        return nil
    }

    /// When nothing is selected show the generic "skip for now" image.
    private var dynamicImageNameFallback: String { "skipfornow" }

    /// Maps each symptom to `onboarding-material/<name>.jpg` (e.g. `lowenergy.jpg`, `anxiety.jpg`, `weightgain.jpg`).
    private var dynamicImageName: String {
        switch primarySymptom {
        case .lowEnergy:        return "lowenergy"
        case .brainFog:         return "brainfog"
        case .anxiety:          return "anxiety"
        case .depression:       return "depression"
        case .sleepProblems:    return "sleepproblems"
        case .weightGain:       return "weightgain"
        case .hyperactivity:    return "hyperactivity"
        case .behavioralIssues: return "behavioralissues"
        case nil:               return dynamicImageNameFallback
        }
    }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.horizontal, labelyV2OnboardingHeaderSideInset)
                .padding(.top, 8)

                Spacer(minLength: 0)

                OnboardingMaterialImage.swiftUIImagePreferringJPEG(named: dynamicImageName)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)

                Spacer(minLength: 0)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(labelyOnboardingPrimaryGreen)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(Color.white))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
                .padding(.horizontal, labelyV2OnboardingHeaderSideInset)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - "Do you believe you can alleviate your symptoms?" (step 17)

private struct AlleviateSymptomsBelieveOnboardingView: View {
    let onBack: () -> Void
    let onReady: () -> Void

    @State private var showAlignmentAlert = false

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    var body: some View {
        ZStack {
            labelyOnboardingCream.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    GeometryReader { g in
                        let spacing: CGFloat = 3
                        let segW = (g.size.width - spacing) / 2
                        HStack(spacing: spacing) {
                            ForEach(0..<2, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(i == 0 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.25))
                                    .frame(width: segW, height: 5)
                            }
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)

                Text("Do you believe you can\nalleviate your symptoms in\n90 days through clean eating?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(labelyOnboardingTextGreen)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 28)

                Spacer(minLength: 20)

                OnboardingMaterialImage.swiftUIImage(named: "alleviate-your-symptoms")
                    .scaledToFit()
                    .padding(.horizontal, 24)

                Spacer(minLength: 20)

                Button(action: { withAnimation(.easeOut(duration: 0.22)) { showAlignmentAlert = true } }) {
                    Text("I'm not sure")
                        .font(.system(size: 15, weight: .regular))
                        .underline()
                        .foregroundColor(labelyOnboardingTextGreen.opacity(0.65))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)

                Button(action: onReady) {
                    Text("Yes, I'm ready!")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 32)
            }
            .blur(radius: showAlignmentAlert ? 6 : 0)
            .allowsHitTesting(!showAlignmentAlert)

            if showAlignmentAlert {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 22) {
                    Text("Labely is for people who are committed to living healthier. We believe that food is medicine and that you can feel better by using cleaner products.")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("If you're not aligned, then Labely may not be for you.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(labelyChooseTeamSubtitleOlive)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: { withAnimation(.easeOut(duration: 0.2)) { showAlignmentAlert = false } }) {
                        Text("I understand")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                    }
                    .buttonStyle(LabelyOnboardingPressableButtonStyle())
                }
                .padding(26)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: 10)
                )
                .padding(.horizontal, 28)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: showAlignmentAlert)
        .navigationBarHidden(true)
    }
}

// MARK: - "Your Goals" graph (step 18)

private struct GoalsGraphOnboardingView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var showGraph = false
    @State private var showProofStat = false
    @State private var canContinue = false

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset
    private let graphGreen = labelyOnboardingPrimaryGreen
    private let graphRed  = Color(red: 0.82, green: 0.22, blue: 0.22)

    var body: some View {
        ZStack {
            labelyOnboardingCream.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    GeometryReader { g in
                        let spacing: CGFloat = 3
                        let segW = (g.size.width - spacing) / 2
                        HStack(spacing: spacing) {
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(labelyOnboardingPrimaryGreen)
                                .frame(width: segW, height: 5)
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(labelyOnboardingPrimaryGreen.opacity(0.25))
                                .frame(width: segW, height: 5)
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)

                Text("Feel better fast. Labely is the\neasiest way to start")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(labelyOnboardingTextGreen)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                    .padding(.horizontal, 28)

                Spacer(minLength: 20)

                // Graph card
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your Goals")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 12)
                        .opacity(showGraph ? 1 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.2), value: showGraph)

                    // Grid + curves
                    ZStack(alignment: .bottomLeading) {
                        // Horizontal grid lines
                        VStack(spacing: 0) {
                            ForEach(0..<4) { _ in
                                Spacer()
                                Rectangle()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(height: 1)
                            }
                        }
                        .padding(.horizontal, 20)

                        GeometryReader { geo in
                            let w = geo.size.width - 40
                            let h = geo.size.height
                            let originY = h * 0.82

                            // Green area fill
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: h))
                                p.addLine(to: CGPoint(x: 0, y: originY))
                                p.addCurve(
                                    to: CGPoint(x: w, y: h * 0.08),
                                    control1: CGPoint(x: w * 0.25, y: originY),
                                    control2: CGPoint(x: w * 0.55, y: h * 0.08)
                                )
                                p.addLine(to: CGPoint(x: w, y: h))
                                p.closeSubpath()
                            }
                            .fill(graphGreen.opacity(0.10))
                            .offset(x: 20)
                            .opacity(showGraph ? 1 : 0)
                            .animation(.easeOut(duration: 1.0).delay(0.5), value: showGraph)

                            // Red area fill
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: h))
                                p.addLine(to: CGPoint(x: 0, y: originY))
                                p.addCurve(
                                    to: CGPoint(x: w * 0.45, y: h * 0.52),
                                    control1: CGPoint(x: w * 0.15, y: originY - 10),
                                    control2: CGPoint(x: w * 0.30, y: h * 0.48)
                                )
                                p.addCurve(
                                    to: CGPoint(x: w, y: h * 0.60),
                                    control1: CGPoint(x: w * 0.60, y: h * 0.56),
                                    control2: CGPoint(x: w * 0.80, y: h * 0.50)
                                )
                                p.addLine(to: CGPoint(x: w, y: h))
                                p.closeSubpath()
                            }
                            .fill(graphRed.opacity(0.07))
                            .offset(x: 20)
                            .opacity(showGraph ? 1 : 0)
                            .animation(.easeOut(duration: 1.0).delay(0.5), value: showGraph)

                            // Green line
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: originY))
                                p.addCurve(
                                    to: CGPoint(x: w, y: h * 0.08),
                                    control1: CGPoint(x: w * 0.25, y: originY),
                                    control2: CGPoint(x: w * 0.55, y: h * 0.08)
                                )
                            }
                            .trim(from: 0, to: showGraph ? 1 : 0)
                            .stroke(graphGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .offset(x: 20)
                            .animation(.easeOut(duration: 1.2).delay(0.4), value: showGraph)

                            // Red line
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: originY))
                                p.addCurve(
                                    to: CGPoint(x: w * 0.45, y: h * 0.52),
                                    control1: CGPoint(x: w * 0.15, y: originY - 10),
                                    control2: CGPoint(x: w * 0.30, y: h * 0.48)
                                )
                                p.addCurve(
                                    to: CGPoint(x: w, y: h * 0.60),
                                    control1: CGPoint(x: w * 0.60, y: h * 0.56),
                                    control2: CGPoint(x: w * 0.80, y: h * 0.50)
                                )
                            }
                            .trim(from: 0, to: showGraph ? 1 : 0)
                            .stroke(graphRed, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .offset(x: 20)
                            .animation(.easeOut(duration: 1.2).delay(0.4), value: showGraph)

                            // Origin circle
                            Circle()
                                .strokeBorder(labelyOnboardingTextGreen, lineWidth: 2)
                                .background(Circle().fill(Color.white))
                                .frame(width: 10, height: 10)
                                .position(x: 20, y: originY)
                                .opacity(showGraph ? 1 : 0)
                                .animation(.easeOut(duration: 0.3).delay(0.4), value: showGraph)
                        }
                    }
                    .frame(height: 160)

                    // Legend
                    HStack(spacing: 20) {
                        HStack(spacing: 6) {
                            Circle().fill(graphGreen).frame(width: 10, height: 10)
                            Text("With Labely")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.20, green: 0.20, blue: 0.20))
                        }
                        HStack(spacing: 6) {
                            Circle().fill(graphRed).frame(width: 10, height: 10)
                            Text("Traditional Approach")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.20, green: 0.20, blue: 0.20))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                    .opacity(showGraph ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(1.0), value: showGraph)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                )
                .padding(.horizontal, horizontalPadding)

                Text("91% of Labely users achieve their health goals within 6 months")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(labelyOnboardingTextGreen.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, horizontalPadding + 12)
                    .padding(.top, 16)
                    .opacity(showProofStat ? 1 : 0)
                    .scaleEffect(showProofStat ? 1 : 0.94)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: showProofStat)

                Spacer()

                Button(action: onContinue) {
                    Text("Let's get started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Capsule().fill(canContinue ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.45))
                        )
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
                .disabled(!canContinue)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 32)
                .opacity(showProofStat ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.15), value: showProofStat)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showGraph = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.95) {
                showProofStat = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.25) {
                canContinue = true
            }
        }
    }
}

// MARK: - "One family's story of hope" video (step 19)

private func bundleURLForFamilyStoryOnboardingVideo() -> URL? {
    let name = "onboardingvideo"
    if let u = Bundle.main.url(forResource: name, withExtension: "mp4", subdirectory: "onboarding-material") {
        return u
    }
    return Bundle.main.url(forResource: name, withExtension: "mp4")
}

private struct FamilyStoryVideoOnboardingView: View {
    let onBack: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    @State private var familyStoryVideoPreviewLocked = true

    var body: some View {
        ZStack {
            labelyOnboardingCream.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    GeometryReader { g in
                        let spacing: CGFloat = 3
                        let total = 4
                        let segW = (g.size.width - CGFloat(total - 1) * spacing) / CGFloat(total)
                        HStack(spacing: spacing) {
                            ForEach(0..<total, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(i < 3 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.25))
                                    .frame(width: segW, height: 5)
                            }
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)

                Text("One family's story of hope")
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(labelyOnboardingTextGreen)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                Text("From Chaos to a Plan")
                    .font(.system(size: 16, weight: .regular, design: .default).italic())
                    .foregroundColor(labelyChooseTeamSubtitleOlive)
                    .padding(.top, 6)

                Spacer(minLength: 16)

                if let url = bundleURLForFamilyStoryOnboardingVideo() {
                    ZStack {
                        LabelyOnboardingFamilyStoryVideoPlayer(
                            url: url,
                            previewLocked: $familyStoryVideoPreviewLocked
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        if familyStoryVideoPreviewLocked {
                            Color.black.opacity(0.38)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .onTapGesture {
                                    familyStoryVideoPreviewLocked = false
                                }

                            Button {
                                familyStoryVideoPreviewLocked = false
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "speaker.slash.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Unmute")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.92))
                                .clipShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Unmute and play video from the beginning")
                        }
                    }
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .padding(.horizontal, horizontalPadding)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "film")
                                    .font(.system(size: 28))
                                    .foregroundColor(labelyOnboardingTextGreen.opacity(0.4))
                                Text("Add onboardingvideo.mp4 to\nonboarding-material")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(labelyChooseTeamSubtitleOlive)
                                    .multilineTextAlignment(.center)
                            }
                        )
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .padding(.horizontal, horizontalPadding)
                }

                Spacer(minLength: 8)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LabelyOnboardingHillsBottomChrome {
                VStack(spacing: 16) {
                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(.system(size: 15, weight: .regular))
                            .underline()
                            .foregroundColor(labelyOnboardingTextGreen.opacity(0.55))
                    }
                    .buttonStyle(.plain)

                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                    }
                    .buttonStyle(LabelyOnboardingPressableButtonStyle())
                }
                .padding(.bottom, 4)
            }
        }
        .navigationBarHidden(true)
    }
}

/// Host view whose **root layer** is `AVPlayerLayer`, so layout always matches bounds (avoids black video when `AVPlayerLayer` never received a non-zero frame).
private final class LabelyAVPlayerLayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct LabelyOnboardingFamilyStoryVideoPlayer: UIViewRepresentable {
    let url: URL
    @Binding var previewLocked: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let host = LabelyAVPlayerLayerHostView()
        host.backgroundColor = .black
        let player = AVPlayer(url: url)
        player.isMuted = true
        host.playerLayer.player = player
        host.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.player = player
        context.coordinator.isPreviewLocked = true
        context.coordinator.lastBindingPreviewLocked = true
        DispatchQueue.main.async {
            context.coordinator.attachEndObserverIfNeeded()
        }
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attachEndObserverIfNeeded()
        context.coordinator.applyBindingChange(previewLocked: previewLocked)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachEndObserver()
        coordinator.player?.pause()
        coordinator.player = nil
        (uiView as? LabelyAVPlayerLayerHostView)?.playerLayer.player = nil
    }

    final class Coordinator {
        var player: AVPlayer?
        private var endObserver: NSObjectProtocol?
        var isPreviewLocked = true
        var lastBindingPreviewLocked = true

        func attachEndObserverIfNeeded() {
            guard endObserver == nil, let item = player?.currentItem else { return }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.handleDidPlayToEnd()
            }
        }

        func detachEndObserver() {
            if let token = endObserver {
                NotificationCenter.default.removeObserver(token)
            }
            endObserver = nil
        }

        private func handleDidPlayToEnd() {
            guard let player else { return }
            if isPreviewLocked {
                player.seek(to: .zero) { _ in player.play() }
            }
        }

        func applyBindingChange(previewLocked bindingValue: Bool) {
            if lastBindingPreviewLocked, !bindingValue {
                isPreviewLocked = false
                player?.isMuted = false
                player?.pause()
                player?.seek(to: .zero) { [weak self] finished in
                    guard finished else { return }
                    self?.player?.play()
                }
            }
            lastBindingPreviewLocked = bindingValue
            isPreviewLocked = bindingValue
        }
    }
}

// MARK: - Main marketing video (`onboarding-material/main.mp4`, plus legacy extensions)

/// Thrifty `ContentView.swift.backup`: `MainVideoPlayer` + `frame(maxWidth: .infinity)` + `clipped()`. Try-free also used `maxHeight: 500`; we use flexible height by default (`capHeight == nil`).
private enum LabelyOnboardingThriftyMainVideoLayout {
    static let legacyTryFreeCapHeight: CGFloat = 500
}

/// Muted hero clip (`onboarding-material/main.*`); mirrors Thrifty `MainVideoPlayer` (AVPlayerLayer + `resizeAspect` + loop).
///
/// **Rounding:** `AVPlayerLayer` is this type’s *sublayer* inside a plain `UIView` container so `cornerRadius` + `clipsToBounds`
/// reliably masks video pixels. Clipping only the representable in SwiftUI often fails when the layer class is `AVPlayerLayer`.
private struct LabelyOnboardingMainMarketingVideoPlayer: UIViewRepresentable {
    var loops: Bool = true
    /// When `loops` is false, called once when playback reaches the end (main thread).
    var onPlayToEnd: (() -> Void)? = nil
    /// Fills any letterboxing behind the layer (use cream on welcome, white on white screens).
    var hostBackgroundUIColor: UIColor = .white
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    /// Applied on a wrapping container view (`clipsToBounds`). Use `0` for square corners.
    var clipCornerRadius: CGFloat = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(loops: loops, onPlayToEnd: onPlayToEnd)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = hostBackgroundUIColor
        applyContainerRounding(container)

        let host = LabelyAVPlayerLayerHostView()
        host.backgroundColor = hostBackgroundUIColor
        host.playerLayer.videoGravity = videoGravity
        host.playerLayer.backgroundColor = hostBackgroundUIColor.cgColor
        host.isUserInteractionEnabled = false
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.host = host

        guard let url = Self.bundleURLForMainMarketingVideo() else {
            return container
        }

        let player = AVPlayer(url: url)
        player.isMuted = true
        host.playerLayer.player = player
        context.coordinator.player = player

        DispatchQueue.main.async {
            context.coordinator.attachEndObserverIfNeeded()
            player.play()
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.backgroundColor = hostBackgroundUIColor
        applyContainerRounding(uiView)
        context.coordinator.attachEndObserverIfNeeded()
    }

    private func applyContainerRounding(_ container: UIView) {
        if clipCornerRadius > 0.5 {
            container.layer.cornerRadius = clipCornerRadius
            container.layer.cornerCurve = .continuous
            container.clipsToBounds = true
        } else {
            container.layer.cornerRadius = 0
            container.clipsToBounds = false
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detachEndObserver()
        coordinator.player?.pause()
        coordinator.player = nil
        coordinator.host?.playerLayer.player = nil
        coordinator.host = nil
    }

    private static func bundleURLForMainMarketingVideo() -> URL? {
        let name = "main"
        for ext in ["mp4", "MP4", "MOV", "mov"] {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "onboarding-material")
                ?? Bundle.main.url(forResource: name, withExtension: ext) {
                return u
            }
        }
        return nil
    }

    final class Coordinator {
        let loops: Bool
        var onPlayToEnd: (() -> Void)?
        var player: AVPlayer?
        weak var host: LabelyAVPlayerLayerHostView?
        private var endObserver: NSObjectProtocol?
        private var didFireNonLoopEnd = false

        init(loops: Bool, onPlayToEnd: (() -> Void)?) {
            self.loops = loops
            self.onPlayToEnd = onPlayToEnd
        }

        func attachEndObserverIfNeeded() {
            guard endObserver == nil, let item = player?.currentItem else { return }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.handleDidPlayToEnd()
            }
        }

        func detachEndObserver() {
            if let token = endObserver {
                NotificationCenter.default.removeObserver(token)
            }
            endObserver = nil
        }

        private func handleDidPlayToEnd() {
            guard let player else { return }
            if loops {
                player.seek(to: .zero) { _ in player.play() }
            } else if !didFireNonLoopEnd {
                didFireNonLoopEnd = true
                onPlayToEnd?()
            }
        }
    }
}

/// Thrifty-style `MainVideoPlayer` stack: full width, optional height cap, rounded corners via UIKit container on the player, `resizeAspect` inside player.
private struct LabelyThriftyStyleMainMarketingVideoBlock: View {
    var loops: Bool
    var onPlayToEnd: (() -> Void)? = nil
    let hostBackgroundUIColor: UIColor
    var uiOpacity: Double = 1
    var bottomPadding: CGFloat = 0
    /// Pass `LabelyOnboardingThriftyMainVideoLayout.legacyTryFreeCapHeight` to mimic old 500pt cap; `nil` fills parent (use with `frame(maxHeight: .infinity)`).
    var capHeight: CGFloat? = nil
    var clipCornerRadius: CGFloat = labelyOnboardingMarketingVideoCornerRadius

    var body: some View {
        playerFill
            .opacity(uiOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .padding(.bottom, bottomPadding)
    }

    @ViewBuilder
    private var playerFill: some View {
        if let h = capHeight {
            LabelyOnboardingMainMarketingVideoPlayer(
                loops: loops,
                onPlayToEnd: onPlayToEnd,
                hostBackgroundUIColor: hostBackgroundUIColor,
                videoGravity: .resizeAspect,
                clipCornerRadius: clipCornerRadius
            )
            .frame(maxWidth: .infinity)
            .frame(maxHeight: h)
        } else {
            LabelyOnboardingMainMarketingVideoPlayer(
                loops: loops,
                onPlayToEnd: onPlayToEnd,
                hostBackgroundUIColor: hostBackgroundUIColor,
                videoGravity: .resizeAspect,
                clipCornerRadius: clipCornerRadius
            )
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Lay's education → "Here's why" → "Try these instead" (step 20)

private struct LaysChipsEducationOnboardingView: View {
    let onBack: () -> Void
    let onComplete: () -> Void

    @State private var showHeresWhy = false
    @State private var showTryInsteadSheet = false
    @State private var confettiTrigger = 0
    @State private var tryInsteadExpandSeed = false
    @State private var tryInsteadExpandProcessing = false
    @State private var tryInsteadExpandAdditives = false

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    var body: some View {
        ZStack {
            labelyOnboardingCream.ignoresSafeArea()

                laysQuestionLayer
        }
        .sheet(isPresented: $showHeresWhy) {
            HeresWhyLaysSheetView(onRevealBetterAlternative: {
                showHeresWhy = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showTryInsteadSheet = true
                }
            })
            .presentationDetents([.fraction(0.94)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTryInsteadSheet) {
            tryInsteadLayer
                .presentationDetents([.fraction(0.84)])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
        }
    }

    private var laysQuestionLayer: some View {
        GeometryReader { geo in
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                labelyOnboardingCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(labelyOnboardingTextGreen)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let total = 5
                            let segW = (g.size.width - CGFloat(total - 1) * spacing) / CGFloat(total)
                            HStack(spacing: spacing) {
                                ForEach(0..<total, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(i < 4 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.25))
                                        .frame(width: segW, height: 5)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text("How do these chips make you feel after eating them?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            OnboardingMaterialImage.swiftUIImage(named: "lays")
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .padding(.horizontal, 40)
                                .padding(.top, 16)

                            VStack(spacing: 12) {
                                ForEach(["Sluggish & tired", "Bloated", "I don't eat these"], id: \.self) { label in
                                    Button(action: { showHeresWhy = true }) {
                                        Text(label)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 52)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(Color.white)
                                                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                                            )
                                    }
                                    .buttonStyle(LabelyOnboardingPressableButtonStyle())
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 20)
                            .padding(.bottom, 28)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
    }

    private var tryInsteadLayer: some View {
        ZStack {
            labelyOnboardingCream.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Text("Try these instead")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .italic()
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                    HStack(alignment: .top, spacing: 14) {
                        OnboardingMaterialImage.swiftUIImage(named: "siete-kettle-chips")
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sea Salt Kettle Chips")
                                .font(.system(size: 16, weight: .bold))
                            Text("Siete")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                            HStack(spacing: 6) {
                                Text("87/100")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(labelyOnboardingTextGreen)
                                Text("Excellent")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(labelyOnboardingPrimaryGreen)
                                Circle()
                                    .fill(labelyOnboardingPrimaryGreen)
                                    .frame(width: 8, height: 8)
                            }
                            .padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, horizontalPadding)

                    labelySaysCard {
                        Text("Made with avocado oil rich in heart-healthy monounsaturated fats. These kettle cooked chips use non-GMO potatoes, providing a cleaner alternative with no inflammatory oils.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(red: 0.22, green: 0.22, blue: 0.22))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)

                    tryInsteadBreakdownRows
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 16)

                    Spacer(minLength: 100)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onComplete) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 24)
                .background(labelyOnboardingCream.opacity(0.82))
            }
        }
        .confettiCannon(
            trigger: $confettiTrigger,
            num: 60,
            colors: [.red, .yellow, .blue, .green, .purple, Color(white: 0.55), .orange, .cyan],
            confettiSize: 10,
            radius: 360
        )
        .onAppear {
            // Fire after sheet settle so particles aren’t clipped / lost during presentation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                confettiTrigger += 1
            }
        }
        .navigationBarHidden(true)
    }

    private var tryInsteadBreakdownRows: some View {
        VStack(spacing: 10) {
            OnboardingBreakdownDisclosureCard(
                title: "Seed Oils",
                icon: "leaf.fill",
                tag: "None",
                tagForeground: labelyOnboardingPrimaryGreen,
                tagCapsuleFill: labelyOnboardingPrimaryGreen.opacity(0.15),
                dotColor: labelyOnboardingPrimaryGreen,
                isExpanded: $tryInsteadExpandSeed
            ) {
                Text("No seed oils — avocado oil only.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
            }

            OnboardingBreakdownDisclosureCard(
                title: "Processing Profile",
                icon: "point.3.connected.trianglepath.dotted",
                tag: "Moderate",
                tagForeground: Color(red: 0.75, green: 0.45, blue: 0.12),
                tagCapsuleFill: Color.orange.opacity(0.15),
                dotColor: Color.orange,
                isExpanded: $tryInsteadExpandProcessing
            ) {
                processingLevelBar(moderate: true)
            }

            OnboardingBreakdownDisclosureCard(
                title: "Additives",
                icon: "flask.fill",
                tag: "No additives",
                tagForeground: labelyOnboardingPrimaryGreen,
                tagCapsuleFill: labelyOnboardingPrimaryGreen.opacity(0.15),
                dotColor: labelyOnboardingPrimaryGreen,
                isExpanded: $tryInsteadExpandAdditives
            ) {
                Text("No additives found!")
                    .font(.system(size: 14, weight: .regular))
                    .italic()
                    .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
            }
        }
    }

    private func processingLevelBar(moderate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Processing level")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [labelyOnboardingPrimaryGreen, Color.yellow.opacity(0.85), Color.red.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 10)
                Circle()
                    .fill(Color(red: 0.25, green: 0.25, blue: 0.28))
                    .frame(width: 14, height: 14)
                    .offset(x: moderate ? 120 : 180)
                HStack {
                    Text("Unprocessed")
                        .font(.system(size: 9, weight: .medium))
                    Spacer()
                    Text("Ultra-processed")
                        .font(.system(size: 9, weight: .medium))
                }
                .offset(y: 18)
            }
            .frame(height: 36)
        }
    }
}

private struct HeresWhyLaysSheetView: View {
    let onRevealBetterAlternative: () -> Void

    @State private var expandSeedOils = false
    @State private var expandProcessing = false
    @State private var expandAdditives = false
    @State private var revealPulse = false

    private let horizontalPadding: CGFloat = 20

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("Here's why")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundColor(labelyOnboardingTextGreen)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 18)

                HStack(alignment: .top, spacing: 14) {
                    OnboardingMaterialImage.swiftUIImage(named: "lays")
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Barbecue Potato Chips")
                            .font(.system(size: 16, weight: .bold))
                        Text("Lay's")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.38))
                        HStack(spacing: 6) {
                            Text("16/100")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color.red.opacity(0.85))
                            Text("Avoid")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.red.opacity(0.85))
                            Circle()
                                .fill(Color.red.opacity(0.85))
                                .frame(width: 8, height: 8)
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, horizontalPadding)

                labelySaysCard { heresWhyLaysAttributed() }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)

                VStack(spacing: 10) {
                    OnboardingBreakdownDisclosureCard(
                        title: "Seed Oils",
                        icon: "leaf.fill",
                        tag: "Present",
                        tagForeground: Color.red.opacity(0.85),
                        tagCapsuleFill: Color.red.opacity(0.14),
                        dotColor: Color.red.opacity(0.85),
                        isExpanded: $expandSeedOils
                    ) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            ForEach(["Canola Oil", "Corn Oil", "Soybean Oil", "Sunflower Oil"], id: \.self) { oil in
                                Text(oil)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.red.opacity(0.85))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.red.opacity(0.12)))
                            }
                        }
                    }

                    OnboardingBreakdownDisclosureCard(
                        title: "Processing Profile",
                        icon: "point.3.connected.trianglepath.dotted",
                        tag: "High",
                        tagForeground: Color.red.opacity(0.85),
                        tagCapsuleFill: Color.red.opacity(0.14),
                        dotColor: Color.red.opacity(0.85),
                        isExpanded: $expandProcessing
                    ) {
                        processingLevelBarHeresWhy()
                    }

                    OnboardingBreakdownDisclosureCard(
                        title: "Additives",
                        icon: "flask.fill",
                        tag: "No additives",
                        tagForeground: labelyOnboardingPrimaryGreen,
                        tagCapsuleFill: labelyOnboardingPrimaryGreen.opacity(0.14),
                        dotColor: labelyOnboardingPrimaryGreen,
                        isExpanded: $expandAdditives
                    ) {
                        Text("No additives found!")
                            .font(.system(size: 14, weight: .regular))
                            .italic()
                            .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.38))
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ingredients")
                        .font(.system(size: 15, weight: .bold))
                    Text("Potatoes, Vegetable Oil (Canola, Corn, Soybean, and/or Sunflower Oil), and Salt.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                        .lineSpacing(3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.96, green: 0.96, blue: 0.97)))
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
                Button(action: onRevealBetterAlternative) {
                    Text("Reveal better alternative")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
            .scaleEffect(revealPulse ? 1.06 : 1.0)
            .shadow(
                color: labelyOnboardingPrimaryGreen.opacity(revealPulse ? 0.45 : 0.22),
                radius: revealPulse ? 14 : 8,
                x: 0,
                y: 4
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                    revealPulse = true
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(labelyOnboardingCream.opacity(0.98))
        }
        .background(labelyOnboardingCream)
    }

    private func heresWhyLaysAttributed() -> Text {
        let red = Color.red.opacity(0.88)
        return Text("High sodium content causes ")
            + Text("water retention").foregroundColor(red).fontWeight(.semibold)
            + Text(" and ")
            + Text("bloating").foregroundColor(red).fontWeight(.semibold)
            + Text(". The ultra-processed oils are ")
            + Text("hard to digest").foregroundColor(red).fontWeight(.semibold)
            + Text(", while acrylamides from high-heat frying ")
            + Text("irritate your gut").foregroundColor(red).fontWeight(.semibold)
            + Text(" lining.")
    }

    private func processingLevelBarHeresWhy() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [labelyOnboardingPrimaryGreen, Color.yellow.opacity(0.85), Color.red.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 10)
                Circle()
                    .fill(Color(red: 0.25, green: 0.25, blue: 0.28))
                    .frame(width: 14, height: 14)
                    .offset(x: UIScreen.main.bounds.width * 0.72)
            }
            HStack {
                Text("Unprocessed")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                Text("Ultra-processed")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
    }
}

private func labelySaysCard<B: View>(@ViewBuilder body: () -> B) -> some View {
    HStack(alignment: .top, spacing: 10) {
        OnboardingMaterialImage.swiftUIImage(named: "labely-says")
            .scaledToFit()
            .frame(width: 26, height: 26)
        VStack(alignment: .leading, spacing: 6) {
            Text("Labely says")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(labelyOnboardingTextGreen)
            body()
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    )
}

private struct OnboardingBreakdownDisclosureCard<Content: View>: View {
    let title: String
    let icon: String
    let tag: String
    let tagForeground: Color
    let tagCapsuleFill: Color
    let dotColor: Color
    @Binding var isExpanded: Bool
    @ViewBuilder var expandedContent: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(labelyOnboardingTextGreen)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))
                    Spacer()
                    Text(tag)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tagForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tagCapsuleFill))
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent()
                    .padding(.top, 12)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
    }
}

// MARK: - Frequency question rows (steps 21–24)

private struct OnboardingFrequencyQuestionView: View {
    let title: String
    let options: [String]
    let onBack: () -> Void
    let onPick: (String) -> Void

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    var body: some View {
        GeometryReader { geo in
            let optionsMinHeight = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                labelyOnboardingCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(labelyOnboardingTextGreen)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let total = 4
                            let segW = (g.size.width - CGFloat(total - 1) * spacing) / CGFloat(total)
                            HStack(spacing: spacing) {
                                ForEach(0..<total, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(i < 2 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.25))
                                        .frame(width: segW, height: 5)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 28)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(spacing: 12) {
                                ForEach(options, id: \.self) { option in
                                    Button(action: { onPick(option) }) {
                                        Text(option)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: 52)
                                            .padding(.horizontal, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(Color.white)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                                                    )
                                            )
                                    }
                                    .buttonStyle(LabelyOnboardingPressableButtonStyle())
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: optionsMinHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Dietary / allergies pills (steps 25–26) & safeguards loading (27)

private struct OnboardingDisclaimerConfig {
    let text: String
}

private let labelyOnboardingDisclaimerMint = Color(
    red: CGFloat(0xE8) / 255,
    green: CGFloat(0xF3) / 255,
    blue: CGFloat(0xE9) / 255
)

private struct OnboardingPillSelectionView: View {
    let title: String
    let options: [String]
    let disclaimer: OnboardingDisclaimerConfig?
    @Binding var selected: Set<String>
    let onBack: () -> Void
    let onNext: () -> Void

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset
    private let pillColumns = [GridItem(.adaptive(minimum: 108), spacing: 10, alignment: .center)]

    var body: some View {
        GeometryReader { geo in
            let contentMinHeight = max(180, geo.size.height - 380)
            ZStack {
                labelyOnboardingCream.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(labelyOnboardingTextGreen)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let total = 6
                            let segW = (g.size.width - CGFloat(total - 1) * spacing) / CGFloat(total)
                            HStack(spacing: spacing) {
                                ForEach(0..<total, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(i < 5 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.22))
                                        .frame(width: segW, height: 5)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text(title)
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 28)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            LazyVGrid(columns: pillColumns, spacing: 10) {
                                ForEach(options, id: \.self) { option in
                                    Button(action: { toggle(option) }) {
                                        Text(option)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(selected.contains(option) ? .white : Color(red: 0.14, green: 0.14, blue: 0.14))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 12)
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                Capsule()
                                                    .fill(selected.contains(option) ? labelyOnboardingPrimaryGreen : Color.white)
                                                    .overlay(
                                                        Capsule()
                                                            .strokeBorder(
                                                                selected.contains(option) ? Color.clear : Color.black.opacity(0.08),
                                                                lineWidth: 1
                                                            )
                                                    )
                                            )
                                    }
                                    .buttonStyle(LabelyOnboardingPressableButtonStyle())
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 22)

                            if let disclaimer = disclaimer {
                                    Text(disclaimer.text)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(labelyOnboardingTextGreen)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 16)
                                        .padding(.top, 4)
                                        .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(labelyOnboardingDisclaimerMint)
                                )
                                .padding(.horizontal, horizontalPadding)
                                .padding(.top, 20)
                            }

                            Color.clear.frame(height: 24)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: contentMinHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: onNext) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func toggle(_ option: String) {
        if option == "None" {
            selected = ["None"]
            return
        }
        selected.remove("None")
        if selected.contains(option) {
            selected.remove(option)
        } else {
            selected.insert(option)
        }
        if selected.isEmpty {
            selected = ["None"]
        }
    }
}

// MARK: - Food guardian summary (step 28)

private enum OnboardingGuardianScoring {
    /// Lower = more lifestyle/symptom load (illustrative, not medical).
    static func holisticCurrentScore(
        symptoms: Set<LabelySymptomChoice>,
        ultraProcessed: String,
        water: String,
        plastic: String,
        canned: String,
        dietary: Set<String>,
        allergies: Set<String>
    ) -> Int {
        var score = 100
        score -= min(28, symptoms.count * 4)
        score -= ultraProcessedPenalty(ultraProcessed)
        score -= waterPenalty(water)
        score -= frequencyPenalty(plastic, daily: 18, often: 14, sometimes: 9, never: 3)
        score -= frequencyPenalty(canned, daily: 12, often: 9, sometimes: 6, never: 2)
        let dietExtras = dietary.filter { $0 != "None" }.count
        score -= min(8, dietExtras * 2)
        let allergyExtras = allergies.filter { $0 != "None" }.count
        score -= min(6, allergyExtras * 2)
        return max(9, min(44, score))
    }

    static func avgLabelyPeerScore(team: LabelyOnboardingTeamChoice) -> Int {
        switch team {
        case .cleanLivingGirlie: return 91
        case .holisticHealthBro: return 90
        case .mamaBearProtector: return 92
        case .wellnessWarriorDad: return 89
        }
    }

    static func ultraProcessedPenalty(_ answer: String) -> Int {
        switch answer {
        case "Daily": return 22
        case "Often": return 16
        case "Sometimes": return 10
        case "Never": return 4
        default: return 10
        }
    }

    static func waterPenalty(_ answer: String) -> Int {
        if answer == "No" { return 12 }
        if answer.contains("advanced") { return 3 }
        if answer.contains("Brita") || answer.contains("basic") { return 6 }
        return 8
    }

    static func frequencyPenalty(
        _ answer: String,
        daily: Int,
        often: Int,
        sometimes: Int,
        never: Int
    ) -> Int {
        switch answer {
        case "Daily": return daily
        case "Often": return often
        case "Sometimes": return sometimes
        case "Never": return never
        default: return sometimes
        }
    }
}

private extension LabelyOnboardingTeamChoice {
    /// Single-line persona title for the guardian card.
    var guardianPersonaTitle: String {
        switch self {
        case .cleanLivingGirlie: return "Clean-Living Girlie"
        case .holisticHealthBro: return "Holistic Health Bro"
        case .mamaBearProtector: return "Mama Bear Protector"
        case .wellnessWarriorDad: return "Wellness Warrior Dad"
        }
    }
}

private extension LabelyCleanerProductMotivation {
    var guardianSwapSubtitle: String {
        switch self {
        case .liveHealthier: return "Tasty alternatives"
        case .betterSleep: return "Evening-friendly swaps"
        case .clearerThinking: return "Focus-friendly picks"
        case .moreEnergy: return "Steady-energy swaps"
        case .happierSkin: return "Skin-loving alternatives"
        case .healthierFamily: return "Family-approved swaps"
        }
    }

    var guardianTruthSubtitle: String {
        switch self {
        case .liveHealthier: return "Cuts through misleading labels"
        case .betterSleep: return "Spots hidden stimulants"
        case .clearerThinking: return "Surfaces sneaky additives"
        case .moreEnergy: return "Highlights energy traps"
        case .happierSkin: return "Flags skin irritants"
        case .healthierFamily: return "Kid-label clarity"
        }
    }

    var guardianToxinSubtitle: String {
        switch self {
        case .liveHealthier: return "Flags harmful chemicals"
        case .betterSleep: return "Watchlist for sleep disruptors"
        case .clearerThinking: return "Neuro irritant alerts"
        case .moreEnergy: return "Crash-causing ingredients"
        case .happierSkin: return "Harsh preservative alerts"
        case .healthierFamily: return "Family toxin watchlist"
        }
    }

    var guardianWeekMilestone: String {
        switch self {
        case .liveHealthier: return "Feel the difference clean eating makes"
        case .betterSleep: return "Wind-down routines feel easier"
        case .clearerThinking: return "Notice calmer, clearer afternoons"
        case .moreEnergy: return "Steadier energy through the day"
        case .happierSkin: return "Skin looks less reactive"
        case .healthierFamily: return "Meals everyone can trust"
        }
    }

    var guardianMonthMilestone: String {
        switch self {
        case .liveHealthier: return "Feel like a completely new person"
        case .betterSleep: return "Sleep feels deeper and more consistent"
        case .clearerThinking: return "Thinking feels sharper and lighter"
        case .moreEnergy: return "Energy that lasts without the crash"
        case .happierSkin: return "A glow you can see in the mirror"
        case .healthierFamily: return "Confident choices for every plate"
        }
    }
}

private struct GuardianChecklistItem: Identifiable {
    let title: String
    let isComplete: Bool
    let priority: Int
    let focus: String
    let swapAction: String

    var id: String { title }
}

private struct FoodGuardianSummaryOnboardingView: View {
    let team: LabelyOnboardingTeamChoice
    let primaryMotivation: LabelyCleanerProductMotivation
    let selectedMotivations: Set<LabelyCleanerProductMotivation>
    let symptoms: Set<LabelySymptomChoice>
    let dietaryRestrictions: Set<String>
    let allergies: Set<String>
    let ultraProcessedAnswer: String
    let waterFilterAnswer: String
    let plasticHeatingAnswer: String
    let cannedFoodsAnswer: String
    let selectedAdditiveChoice: LabelyAdditiveChoice
    let onBack: () -> Void
    let onStartJourney: () -> Void

    @State private var confettiTrigger = 0

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset
    private let cardMint = Color(red: 232 / 255, green: 245 / 255, blue: 233 / 255)
    private let scoreRed = Color(red: 0.86, green: 0.22, blue: 0.22)
    private let scoreGreen = Color(red: 0.22, green: 0.62, blue: 0.38)

    private var userScore: Int {
        OnboardingGuardianScoring.holisticCurrentScore(
            symptoms: symptoms,
            ultraProcessed: ultraProcessedAnswer,
            water: waterFilterAnswer,
            plastic: plasticHeatingAnswer,
            canned: cannedFoodsAnswer,
            dietary: dietaryRestrictions,
            allergies: allergies
        )
    }

    private var avgPeerScore: Int {
        OnboardingGuardianScoring.avgLabelyPeerScore(team: team)
    }

    private var concernCount: Int {
        if !symptoms.isEmpty { return symptoms.count }
        return max(1, selectedMotivations.count)
    }

    private var concernSubtitle: String {
        let n = concernCount
        return "Managing \(n) health concern\(n == 1 ? "" : "s")"
    }

    private var triggerChips: [String] {
        var chips = symptoms.sorted { $0.rawValue < $1.rawValue }.map { $0.label.lowercased() }
        if chips.isEmpty {
            chips = [primaryMotivation.label.lowercased()]
        }
        for d in dietaryRestrictions.filter({ $0 != "None" }).sorted() {
            if chips.count >= 6 { break }
            chips.append(d.lowercased())
        }
        for a in allergies.filter({ $0 != "None" }).sorted() {
            if chips.count >= 6 { break }
            chips.append(a.lowercased())
        }
        return chips
    }

    private var checklistItems: [GuardianChecklistItem] {
        let watchesSeedOils = selectedAdditiveChoice == .seedOils || selectedAdditiveChoice == .allOfTheAbove
        let watchesArtificialAdditives = selectedAdditiveChoice == .artificialAdditives || selectedAdditiveChoice == .allOfTheAbove
        let watchesHeavyMetals = selectedAdditiveChoice == .heavyMetals || selectedAdditiveChoice == .allOfTheAbove
        let avoidsProcessedFoods = ultraProcessedAnswer == "Never"
        let filtersWater = waterFilterAnswer != "No"
        let avoidsPlasticContainers = plasticHeatingAnswer == "Never"
        let avoidsCannedFoods = cannedFoodsAnswer == "Never"
        let followsCleanerDiet = avoidsProcessedFoods && !["Daily", "Often"].contains(cannedFoodsAnswer)
            && !["Daily", "Often"].contains(plasticHeatingAnswer)

        return [
            GuardianChecklistItem(
                title: "Avoids ultra-processed foods",
                isComplete: avoidsProcessedFoods,
                priority: OnboardingGuardianScoring.ultraProcessedPenalty(ultraProcessedAnswer),
                focus: "ultra-processed foods",
                swapAction: "swap one ultra-processed staple for a cleaner version"
            ),
            GuardianChecklistItem(
                title: "Filters drinking water",
                isComplete: filtersWater,
                priority: OnboardingGuardianScoring.waterPenalty(waterFilterAnswer),
                focus: "drinking water",
                swapAction: "set up a simple water-filter routine"
            ),
            GuardianChecklistItem(
                title: "Avoids plastic containers",
                isComplete: avoidsPlasticContainers,
                priority: OnboardingGuardianScoring.frequencyPenalty(plasticHeatingAnswer, daily: 18, often: 14, sometimes: 9, never: 3),
                focus: "heated plastic containers",
                swapAction: "move reheating into glass or ceramic containers"
            ),
            GuardianChecklistItem(
                title: "Avoids canned foods",
                isComplete: avoidsCannedFoods,
                priority: OnboardingGuardianScoring.frequencyPenalty(cannedFoodsAnswer, daily: 12, often: 9, sometimes: 6, never: 2),
                focus: "canned foods",
                swapAction: "find cleaner packaged or fresh alternatives"
            ),
            GuardianChecklistItem(
                title: "Watches for seed oils",
                isComplete: watchesSeedOils,
                priority: watchesSeedOils ? 2 : 10,
                focus: "seed oils",
                swapAction: "replace one seed-oil snack or sauce"
            ),
            GuardianChecklistItem(
                title: "Watches for artificial additives",
                isComplete: watchesArtificialAdditives,
                priority: watchesArtificialAdditives ? 2 : 10,
                focus: "artificial additives",
                swapAction: "scan labels for dyes, preservatives, and flavor enhancers"
            ),
            GuardianChecklistItem(
                title: "Watches for heavy metals",
                isComplete: watchesHeavyMetals,
                priority: watchesHeavyMetals ? 2 : 10,
                focus: "heavy metals",
                swapAction: "use Labely's lab-tested signals for higher-risk products"
            ),
            GuardianChecklistItem(
                title: "Already follows a cleaner diet",
                isComplete: followsCleanerDiet,
                priority: followsCleanerDiet ? 2 : 8,
                focus: "cleaner daily habits",
                swapAction: "build repeatable cleaner meals around foods you already like"
            ),
            GuardianChecklistItem(
                title: "Already reads food labels",
                isComplete: selectedAdditiveChoice == .allOfTheAbove,
                priority: selectedAdditiveChoice == .allOfTheAbove ? 2 : 7,
                focus: "food labels",
                swapAction: "let Labely explain the confusing label terms as you shop"
            ),
            GuardianChecklistItem(
                title: "Feels their best",
                isComplete: symptoms.isEmpty,
                priority: symptoms.isEmpty ? 2 : min(18, symptoms.count * 4),
                focus: symptomsFocus,
                swapAction: "connect your food choices to how you feel each day"
            )
        ]
    }

    private var topGapItems: [GuardianChecklistItem] {
        let gaps = checklistItems
            .filter { !$0.isComplete }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.title < rhs.title
                }
                return lhs.priority > rhs.priority
            }
        return Array(gaps.prefix(3))
    }

    private var primaryGap: GuardianChecklistItem {
        topGapItems.first ?? checklistItems[0]
    }

    private var secondaryGap: GuardianChecklistItem {
        if topGapItems.count > 1 {
            return topGapItems[1]
        }
        return primaryGap
    }

    private var focusSummary: String {
        let focuses = topGapItems.map(\.focus)
        if focuses.isEmpty {
            return primaryMotivation.label.lowercased()
        }
        if focuses.count == 1 {
            return focuses[0]
        }
        return focuses.dropLast().joined(separator: ", ") + " and " + (focuses.last ?? "")
    }

    private var symptomsFocus: String {
        let labels = symptoms.sorted { $0.rawValue < $1.rawValue }.map { $0.label.lowercased() }
        guard !labels.isEmpty else { return "feeling your best" }
        if labels.count == 1 {
            return labels[0]
        }
        return labels.prefix(2).joined(separator: " and ")
    }

    private var checklistTitle: String {
        if team == .mamaBearProtector || team == .wellnessWarriorDad || selectedMotivations.contains(.healthierFamily) {
            return "Where your family stands"
        }
        return "Where you stand"
    }

    var body: some View {
        ZStack(alignment: .top) {
            labelyOnboardingCream.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Based on everything you told us...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.black.opacity(0.45))
                        .padding(.top, 56)

                    Text("Meet Your Personal Food Guardian")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    guardianProfileCard
                        .padding(.top, 18)

                    scoreSection
                        .padding(.top, 22)

                    checklistCard
                        .padding(.top, 22)

                    journeyCard
                        .padding(.top, 16)

                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, horizontalPadding)
            }

            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onStartJourney) {
                Text("Start My Journey")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Capsule().fill(labelyOnboardingPrimaryGreen))
            }
            .buttonStyle(LabelyOnboardingPressableButtonStyle())
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(labelyOnboardingCream.opacity(0.98))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                confettiTrigger += 1
            }
        }
        .confettiCannon(
            trigger: $confettiTrigger,
            num: 70,
            colors: [
                labelyOnboardingPrimaryGreen,
                scoreGreen,
                Color.yellow.opacity(0.85),
                Color.white,
                Color(red: 0.75, green: 0.95, blue: 0.82)
            ],
            confettiSize: 11,
            radius: 400
        )
        .navigationBarHidden(true)
    }

    private var guardianProfileCard: some View {
        HStack(alignment: .center, spacing: 16) {
            OnboardingMaterialImage.swiftUIImage(named: team.imageAssetName)
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(team.guardianPersonaTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                Text(concernSubtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.black.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardMint)
        )
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR HOLISTIC HEALTH SCORE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.42))
                .kerning(0.6)

            holisticScoreRow(
                label: "Your current score",
                dot: scoreRed,
                value: userScore,
                bar: scoreRed
            )

            holisticScoreRow(
                label: "Avg. Labely user (30 days)",
                dot: scoreGreen,
                value: avgPeerScore,
                bar: scoreGreen
            )
        }
    }

    private func holisticScoreRow(label: String, dot: Color, value: Int, bar: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.black.opacity(0.55))
                Spacer()
                Text("\(value)/100")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(bar)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.06))
                    Capsule()
                        .fill(bar)
                        .frame(width: max(8, g.size.width * CGFloat(value) / 100))
                }
            }
            .frame(height: 8)
        }
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(checklistTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(labelyOnboardingTextGreen)
                .padding(.bottom, 14)

            ForEach(checklistItems) { item in
                checklistRow(item)
                    .padding(.vertical, 7)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }

    private func checklistRow(_ item: GuardianChecklistItem) -> some View {
        HStack(spacing: 12) {
            Text(item.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(item.isComplete ? scoreGreen : Color(red: 0.90, green: 0.25, blue: 0.25))
                .accessibilityLabel(item.isComplete ? "Complete" : "Needs work")
        }
    }

    private var guardianSectionDivider: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(labelyOnboardingPrimaryGreen)
                .background(Circle().fill(labelyOnboardingCream).padding(-2))
        }
        .frame(height: 24)
    }

    private var triggerChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(triggerChips.enumerated()), id: \.offset) { _, chip in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(labelyOnboardingPrimaryGreen)
                        Text(chip)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(labelyOnboardingTextGreen)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(cardMint)
                            .overlay(
                                Capsule()
                                    .strokeBorder(labelyOnboardingPrimaryGreen.opacity(0.35), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private var superpowersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            superpowerRow(icon: "arrow.left.arrow.right", title: "Clean Swap Finder", subtitle: primaryMotivation.guardianSwapSubtitle)
            Divider().padding(.vertical, 12)
            superpowerRow(icon: "checkmark.shield.fill", title: "Truth Detector", subtitle: primaryMotivation.guardianTruthSubtitle)
            Divider().padding(.vertical, 12)
            superpowerRow(icon: "flask.fill", title: "Toxin Alerts", subtitle: primaryMotivation.guardianToxinSubtitle)

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
                .padding(.vertical, 14)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundColor(labelyOnboardingPrimaryGreen)
                Text("Your guardian is ready")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(labelyOnboardingTextGreen)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }

    private func superpowerRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(labelyOnboardingPrimaryGreen)
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.black.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
    }

    private var journeyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 15))
                    .foregroundColor(labelyOnboardingPrimaryGreen)
                Text("Your 30 days with Labely")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(labelyOnboardingTextGreen)
            }
            .padding(.bottom, 24)

            journeyStepRow(
                topConnector: false,
                bottomConnector: true,
                node: .complete,
                title: "Today · Week 1 · Get comfortable",
                subtitle: "Scan what's already in your pantry. Labely will pay closest attention to \(focusSummary). No changes yet, just awareness."
            )
            journeyStepRow(
                topConnector: true,
                bottomConnector: true,
                node: .outlineIcon("arrow.left.arrow.right"),
                title: "Week 2 · Start swapping",
                subtitle: "Start with one small win: \(primaryGap.swapAction). Labely finds cleaner alternatives that still fit your routine."
            )
            journeyStepRow(
                topConnector: true,
                bottomConnector: true,
                node: .outlineIcon("fork.knife"),
                title: "Week 3 · Food becomes medicine",
                subtitle: "Build instinct around \(secondaryGap.focus). You start understanding what is in your food and how it connects to \(symptomsFocus)."
            )
            journeyStepRow(
                topConnector: true,
                bottomConnector: false,
                node: .outlineIcon("trophy.fill"),
                title: "Week 4 · This is your new life",
                subtitle: "\(primaryMotivation.guardianMonthMilestone). Cleaner choices feel normal, not like work."
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }

    private enum JourneyNode {
        case complete
        case outlineIcon(String)
    }

    private func journeyStepRow(
        topConnector: Bool,
        bottomConnector: Bool,
        node: JourneyNode,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                if topConnector {
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 2, height: 10)
                }

                Group {
                    switch node {
                    case .complete:
                        ZStack {
                            Circle()
                                .fill(labelyOnboardingPrimaryGreen)
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    case .outlineIcon(let icon):
                        ZStack {
                            Circle()
                                .strokeBorder(labelyOnboardingPrimaryGreen.opacity(0.45), lineWidth: 2)
                                .background(Circle().fill(Color.white))
                                .frame(width: 22, height: 22)
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(labelyOnboardingPrimaryGreen)
                        }
                    }
                }

                if bottomConnector {
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 2, height: 58)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.black.opacity(0.45))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, bottomConnector ? 16 : 0)
        }
    }
}

// MARK: - Give us a rating (step 29) — adapted from legacy `RatingView`

private struct OnboardingGiveRatingView: View {
    let onBack: () -> Void
    let onNext: () -> Void

    @StateObject private var remoteConfig = RemoteConfigManager.shared
    @State private var selectedRating: Int = 5
    @State private var footerReady = false
    @State private var didRequestReview = false

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset
    private let starGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    private let laurelGold = Color(red: 0.78, green: 0.62, blue: 0.18)

    var body: some View {
        ZStack(alignment: .top) {
            labelyOnboardingCream.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 52)

                    Text("Give us a rating")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 8)

                    laurelStarsRow
                        .padding(.top, 28)

                    Text("Labely was designed for\npeople like you")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 20)

                    downloadSocialProofRow
                        .padding(.top, 16)

                    VStack(spacing: 14) {
                        ForEach(ratingTestimonials) { testimonial in
                            ratingTestimonialCard(testimonial)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 28)
                    .padding(.bottom, 100)
                }
            }

            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Button(action: onNext) {
                    Text("Next")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Capsule().fill(canContinue ? labelyOnboardingPrimaryGreen : Color.gray.opacity(0.45)))
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
                .disabled(!canContinue)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 16)
                .padding(.top, 10)
            }
            .background(
                LinearGradient(
                    colors: [labelyOnboardingCream.opacity(0), labelyOnboardingCream, labelyOnboardingCream],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .onAppear {
            footerReady = false
            MixpanelService.shared.trackQuestionViewed(questionTitle: "Give us a rating", stepNumber: 29)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                footerReady = true
            }
            if remoteConfig.hardPaywall, !didRequestReview {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    requestAppStoreReviewIfPossible()
                    didRequestReview = true
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var canContinue: Bool {
        selectedRating > 0 && footerReady
    }

    private var laurelStarsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(laurelGold)

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        selectedRating = index
                        MixpanelService.shared.trackQuestionAnswered(answer: "\(index) stars", stepNumber: 29)
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 26))
                            .foregroundColor(starGold)
                            .scaleEffect(selectedRating >= index ? 1.08 : 0.92)
                            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selectedRating)
                    }
                    .buttonStyle(.plain)
                }
            }

            Image(systemName: "laurel.trailing")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(laurelGold)
        }
        .padding(.horizontal, horizontalPadding)
    }

    private var downloadSocialProofRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach(["onb1", "onb2", "onb3"], id: \.self) { name in
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(labelyOnboardingCream, lineWidth: 2.5))
                }
            }
            Text("+")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(labelyOnboardingTextGreen.opacity(0.55))
            Text("thousands of downloads")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.black.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalPadding + 8)
    }

    private struct RatingTestimonial: Identifiable {
        let id = UUID()
        let imageName: String
        let name: String
        let handle: String
        let body: String
    }

    private var selectedTeamForRating: LabelyOnboardingTeamChoice {
        if let raw = UserDefaults.standard.string(forKey: "labely_onboarding_team_choice"),
           let team = LabelyOnboardingTeamChoice(rawValue: raw) {
            return team
        }
        return .cleanLivingGirlie
    }

    private var ratingTestimonials: [RatingTestimonial] {
        switch selectedTeamForRating {
        case .holisticHealthBro:
            return [
                RatingTestimonial(
                    imageName: "boy1",
                    name: "Noah K.",
                    handle: "@noahclean",
                    body: "Labely cuts through label noise fast. I scan, swap, and stay dialed in without overthinking every snack."
                ),
                RatingTestimonial(
                    imageName: "boy2",
                    name: "Jared S.",
                    handle: "@jaredwellness",
                    body: "I thought I was eating clean. Labely showed me the seed oils and additives hiding in my routine."
                ),
                RatingTestimonial(
                    imageName: "dad2",
                    name: "Marcus T.",
                    handle: "@marcust",
                    body: "The cleaner alternatives are actually practical. It feels built for real grocery trips, not perfect diets."
                )
            ]
        case .mamaBearProtector:
            return parentRatingTestimonials
        case .wellnessWarriorDad:
            return [
                RatingTestimonial(
                    imageName: "dad1",
                    name: "Anthony V.",
                    handle: "@anthonyv",
                    body: "I want safer picks for my kids without spending an hour reading labels. Labely makes that automatic."
                ),
                RatingTestimonial(
                    imageName: "dad2",
                    name: "David S.",
                    handle: "@davids",
                    body: "Scan, compare, swap. Our pantry is cleaner and grocery runs are faster."
                ),
                RatingTestimonial(
                    imageName: "boy2",
                    name: "Shawn E.",
                    handle: "@shawne",
                    body: "Labely flagged products I never would have questioned. It has become part of how I shop for the family."
                )
            ]
        case .cleanLivingGirlie:
            return [
                RatingTestimonial(
                    imageName: "girl1",
                    name: "Emma Klein",
                    handle: "@emmakl3in",
                    body: "Labely helped me spot additives and seed oils in foods I thought were healthy. My swaps finally feel easy."
                ),
                RatingTestimonial(
                    imageName: "girl2",
                    name: "Josie Washburn",
                    handle: "@josiesapphires",
                    body: "The clean alternatives feature has already helped me discover products I now use daily."
                ),
                RatingTestimonial(
                    imageName: "onb3",
                    name: "Hilary Butler",
                    handle: "@hilarybutler",
                    body: "I used to trust the front of the label. Now I scan and get the truth in seconds."
                )
            ]
        }
    }

    private var parentRatingTestimonials: [RatingTestimonial] {
        [
            RatingTestimonial(
                imageName: "mom1",
                name: "Emma Klein",
                handle: "@emmakl3in",
                body: "Labely has been a lifesaver for me and my family. I discovered which baby products had concerning ingredients."
            ),
            RatingTestimonial(
                imageName: "mom2",
                name: "Josie Washburn",
                handle: "@josiesapphires",
                body: "Labely is a no brainer for parents who want cleaner food for their children."
            ),
            RatingTestimonial(
                imageName: "onb3",
                name: "Hilary Butler",
                handle: "@hilarybutler",
                body: "Scanned my kids' snacks and finally saw what was actually inside. It cuts through the marketing."
            )
        ]
    }

    private func ratingTestimonialCard(_ testimonial: RatingTestimonial) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                OnboardingReviewerAvatarView(
                    materialBasename: testimonial.imageName,
                    legacyAssetName: testimonial.imageName,
                    initial: String(testimonial.name.first ?? "?"),
                    accentColor: Color(red: 0.42, green: 0.50, blue: 0.44),
                    size: 48
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(testimonial.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
                    Text(testimonial.handle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.black.opacity(0.45))
                }

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(starGold)
                    }
                }
            }

            Text(testimonial.body)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }

    private func requestAppStoreReviewIfPossible() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

// MARK: - Final paywall (step 34)

private struct OnboardingFinalPaywallView: View {
    let onBack: () -> Void
    let onFinished: () -> Void

    @StateObject private var storeManager = StoreManager()
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var remoteConfig = RemoteConfigManager.shared

    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var navigateToCreateAccount = false
    @State private var showWinback = false
    @State private var isRestoring = false
    @State private var showContent = false
    @State private var currentPaywallStep = 1
    @State private var bellAnimating = false
    @State private var prefetchingTimeline = false
    /// Two-paywall layout (`twopaywall`): weekly + 3-day trial (`weeklyProduct`) vs annual no trial (`annualProduct`).
    @State private var catalogYearlyPlanSelected = true

    /// Marketing numbers for row copy (should match ASC / Subscriptions.storekit).
    private let twoPaywallWeeklyPriceWeekly: Double = 9.99
    private let twoPaywallAnnualPrice: Double = 29
    private let paywallForestGreen = Color(red: 62 / 255, green: 102 / 255, blue: 65 / 255) // #3E6641
    private let paywallLightAccentGreen = Color(red: 141 / 255, green: 176 / 255, blue: 81 / 255) // #8DB051
    private let paywallGoldAccent = Color(red: 212 / 255, green: 175 / 255, blue: 55 / 255) // #D4AF37

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset
    private let testimonialGold = Color(red: 212 / 255, green: 175 / 255, blue: 55 / 255)

    private var weeklyProduct: Product? {
        storeManager.subscriptions.first(where: { $0.id == Config.SubscriptionSKU.weekly })
    }

    private var annualProduct: Product? {
        storeManager.subscriptions.first(where: { $0.id == Config.SubscriptionSKU.annualStandard })
            ?? storeManager.subscriptions.first(where: { $0.id == Config.SubscriptionSKU.annualWinback })
    }

    var body: some View {
        Group {
            if remoteConfig.twoPaywall {
                onboardingTwoPaywallLayout
            } else {
                ZStack(alignment: .top) {
                    Color.white.ignoresSafeArea()

                    VStack(spacing: 0) {
                        finalPaywallHeader

                        ZStack {
                            if currentPaywallStep == 1 {
                                finalPaywallBellContent
                                    .transition(.opacity)
                            } else {
                                finalPaywallTimelineContent
                .transition(.opacity)
            }
        }
                        .animation(.easeInOut(duration: 0.28), value: currentPaywallStep)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    finalPaywallBottomBar
                }
            }
        }
        .onAppear {
            authManager.setPaywallScreenState(true)
            MixpanelService.shared.trackQuestionViewed(questionTitle: remoteConfig.twoPaywall ? "Final paywall (two paywall)" : "Final paywall", stepNumber: 34)
            MixpanelService.shared.trackSubscriptionViewed(planType: "onboarding_final_paywall")
            showContent = true
            if !remoteConfig.twoPaywall {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    bellAnimating = true
                }
            }
            Task { _ = await storeManager.loadProductsWithRetry() }
        }
        .onDisappear {
            if !authManager.hasCompletedSubscription {
                authManager.setPaywallScreenState(false)
            }
        }
        .onChange(of: authManager.isLoggedIn) { loggedIn in
            if loggedIn, navigateToCreateAccount {
                navigateToCreateAccount = false
                onFinished()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.8)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTermsOfService) {
            TermsOfServiceView()
                .presentationDetents([.height(UIScreen.main.bounds.height * 0.8)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $navigateToCreateAccount) {
            CreateAccountView()
        }
        .fullScreenCover(isPresented: $showWinback) {
            WinbackView(isPresented: $showWinback, storeManager: storeManager)
        }
        .navigationBarHidden(true)
    }

    // MARK: - Two paywall layout (Firestore field `twopaywall`)

    private var onboardingTwoPaywallLayout: some View {
        ZStack(alignment: .top) {
            labelyOnboardingCream
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Button(action: { onBack() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .regular))
                            .foregroundColor(paywallForestGreen)
                        .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                            .frame(width: 56, height: 56, alignment: .leading)
                            .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                    Spacer()
                    Button(action: { Task { await restorePurchasesFromFinalPaywall() } }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(paywallForestGreen)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(isRestoring)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Restore")
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        twoPaywallRatingHeroBlock
                        .frame(maxWidth: .infinity)

                        Text("Get unlimited access")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .multilineTextAlignment(.leading)

                        twoPaywallFeatureBulletsColumn

                        twoPaywallTryFreeMarketingVideoSection
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.42), value: showContent)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            twoPaywallFloatingPlansAndCheckoutChrome
        }
    }

    /// Pay reference layout: struck “list” yearly price vs your annual price on this marketing screen (matches reference mock).
    private let twoPaywallYearStrikeReference = "$312.34"

    /// Reference-style SAVE capsule copy.
    private let twoPaywallSavePercentDisplayed = "SAVE 90%"

    /// Shown on the yearly row (informational marketing line; Checkout uses StoreKit).
    private let twoPaywallAnnualMarketingLine = "$29/year"

    private var twoPaywallAnnualPerWeekMarketing: String {
        String(format: "$%.2f/week", twoPaywallAnnualPrice / 52)
    }

    private var twoPaywallWeeklySubtitleExact: String {
        String(format: "3 Days free then $%.2f/week", twoPaywallWeeklyPriceWeekly)
    }

    private var twoPaywallRatingHeroBlock: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(paywallGoldAccent)
                    .rotationEffect(.degrees(-18))

                VStack(spacing: 6) {
                    Text("4.9")
                        .font(.system(size: 52, weight: .heavy))
                        .foregroundColor(labelyOnboardingTextGreen)
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(testimonialGold)
                        }
                    }
                }

                Image(systemName: "leaf.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(paywallGoldAccent)
                    .rotationEffect(.degrees(18))
                    .scaleEffect(x: -1, y: 1)
            }

            Label {
                Text("App Store")
                    .font(.system(size: 14, weight: .semibold))
            } icon: {
                Image(systemName: "apple.logo")
                            .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(Color.black.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.85))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
        )
    }

    /// Main marketing hero clip only (above floating plan rows — no extra slogan block on this paywall).
    private var twoPaywallTryFreeMarketingVideoSection: some View {
        LabelyThriftyStyleMainMarketingVideoBlock(
            loops: true,
            onPlayToEnd: nil,
            hostBackgroundUIColor: labelyOnboardingCreamUIColor,
            bottomPadding: 0,
            capHeight: min(340, max(248, UIScreen.main.bounds.width * 0.88)),
            clipCornerRadius: labelyOnboardingMarketingVideoCornerRadius
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }

    private var twoPaywallFeatureBulletsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            twoPaywallFeatureBullet(emoji: "📸", text: "Scan barcodes & ingredient labels in seconds")
            twoPaywallFeatureBullet(emoji: "🧪", text: "Flag risky additives & seed oils at a glance")
            twoPaywallFeatureBullet(emoji: "✨", text: "Discover cleaner swaps for your staples")
            twoPaywallFeatureBullet(emoji: "♾️", text: "Unlimited scanning — use Labely anytime")
        }
    }

    private func twoPaywallFeatureBullet(emoji: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(emoji).font(.system(size: 20))
            Text(text)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.black.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var twoPaywallStackedPlanRows: some View {
        VStack(spacing: 13) {
            twoPaywallWeekPlanRow
            twoPaywallYearPlanRow
        }
        .padding(.top, 4)
    }

    /// SAVE pill color on two-paywall annual row — sits above the green selection outline.
    private var twoPaywallSaveCapsuleFill: Color {
        Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
    }

    private var twoPaywallWeekPlanRow: some View {
        let selected = !catalogYearlyPlanSelected
        return Button(action: { catalogYearlyPlanSelected = false }) {
            HStack(alignment: .center, spacing: 14) {
                twoPaywallRadioMark(selected: selected)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Week")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(Color.black.opacity(0.92))
                    Text(twoPaywallWeeklySubtitleExact)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.black.opacity(0.48))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? paywallForestGreen : Color.black.opacity(0.09), lineWidth: selected ? 2.25 : 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var twoPaywallYearPlanRow: some View {
        let selected = catalogYearlyPlanSelected
        return Button(action: { catalogYearlyPlanSelected = true }) {
            HStack(alignment: .center, spacing: 14) {
                twoPaywallRadioMark(selected: selected)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Year")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(Color.black.opacity(0.92))
                        Spacer(minLength: 12)
                        Text(twoPaywallAnnualPerWeekMarketing)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(paywallForestGreen)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(twoPaywallYearStrikeReference)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color.black.opacity(0.42))
                            .strikethrough(true, color: Color.black.opacity(0.42))
                        Text(twoPaywallAnnualMarketingLine)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundColor(Color.black.opacity(0.92))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 17)
            .padding(.top, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? paywallForestGreen : Color.black.opacity(0.09), lineWidth: selected ? 2.25 : 1)
            )
            .overlay(alignment: .topTrailing) {
                Text(twoPaywallSavePercentDisplayed)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .tracking(0.6)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(twoPaywallSaveCapsuleFill)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.18), radius: 5, x: 0, y: 2)
                    // Center of the pill sits on the green stroke — draw this overlay last so it isn’t covered by strokeBorder.
                    .offset(x: 4, y: -14)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func twoPaywallRadioMark(selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24, weight: .regular))
            .foregroundColor(selected ? paywallForestGreen : Color.black.opacity(0.22))
    }

    /// True when StoreKit hasn't returned anything yet on cold start (weekly + annual product IDs).
    private var twoPaywallProductsColdLoading: Bool {
        storeManager.isLoadingProducts && storeManager.subscriptions.isEmpty
    }

    private var twoPaywallPurchaseReadyProduct: Bool {
        catalogYearlyPlanSelected ? (annualProduct != nil) : (weeklyProduct != nil)
    }

    /// Plan rows + primary CTA pinned above the home indicator (scroll is only for content above).
    private var twoPaywallFloatingPlansAndCheckoutChrome: some View {
        VStack(spacing: 14) {
            twoPaywallStackedPlanRows

            Button(action: { Task { await purchaseTwoPaywallSelection() } }) {
                HStack(spacing: 8) {
                    if isPurchasing || twoPaywallProductsColdLoading || storeManager.subscriptions.isEmpty {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    }
                    Text(twoPaywallButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(bottomBarFillEnabled ? paywallForestGreen : Color.gray.opacity(0.55))
                )
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
            .disabled(bottomBarDisabled)

            if catalogYearlyPlanSelected {
                twoPaywallMoneyBackGuaranteeRow
            } else {
                twoPaywallNoPaymentDueRow
            }

            HStack(spacing: 10) {
                Button("Terms of use") {
                    showingTermsOfService = true
                }
                Text("·")
                    .foregroundColor(Color.black.opacity(0.35))
                Button("Privacy Policy") {
                    showingPrivacyPolicy = true
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color.black.opacity(0.45))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [
                    labelyOnboardingCream.opacity(0.02),
                    labelyOnboardingCream.opacity(0.94),
                    labelyOnboardingCream
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .opacity(showContent ? 1 : 0)
        .animation(.easeOut(duration: 0.35), value: showContent)
    }

    private var bottomBarFillEnabled: Bool {
        !(isPurchasing || twoPaywallProductsColdLoading || storeManager.subscriptions.isEmpty || !twoPaywallPurchaseReadyProduct)
    }

    private var bottomBarDisabled: Bool {
        isPurchasing || twoPaywallProductsColdLoading || storeManager.subscriptions.isEmpty || !twoPaywallPurchaseReadyProduct
    }

    private var twoPaywallButtonTitle: String {
        if isPurchasing {
            return "Processing…"
        }
        if twoPaywallProductsColdLoading || storeManager.subscriptions.isEmpty {
            return "Loading…"
        }
        return twoPaywallPrimaryCTATitle
    }

    private var twoPaywallNoPaymentDueRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
            Text("No payment due now")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
        }
    }

    private var twoPaywallMoneyBackGuaranteeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
            Text("100 money-back guarantee")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.78))
        }
    }

    private var twoPaywallPrimaryCTATitle: String {
        if catalogYearlyPlanSelected {
            return "Continue"
        }
        return "Try for free"
    }

    private var finalPaywallHeader: some View {
        ZStack {
            footerLinks
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .opacity(currentPaywallStep == 2 ? 1 : 0)

            HStack {
                Button(action: handleFinalPaywallBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        .frame(width: 56, height: 56, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .zIndex(2)

                Spacer()
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 8)
    }

    private var finalPaywallBellContent: some View {
            VStack(spacing: 0) {
                Text("We'll send you a reminder\nbefore your trial ends")
                .font(.system(size: 28, weight: .bold))
                    .foregroundColor(labelyOnboardingTextGreen)
                    .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalPadding + 4)
                    .padding(.top, 28)
                    .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(0.25), value: showContent)

                Spacer()

                ZStack {
                    Image(systemName: "bell")
                    .font(.system(size: min(UIScreen.main.bounds.width * 0.52, 200), weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [labelyOnboardingPrimaryGreen, labelyOnboardingLaunchGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    .rotationEffect(.degrees(bellAnimating ? -15 : 0))
                    .scaleEffect(bellAnimating ? 0.98 : 1.0)
                    .animation(Animation.easeInOut(duration: 0.25).repeatForever(autoreverses: true), value: bellAnimating)

                    Circle()
                        .fill(labelyOnboardingPrimaryGreen)
                    .frame(width: 50, height: 50)
                        .overlay(
                            Text("1")
                            .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                        )
                    .offset(x: 55, y: -60)
                    .rotationEffect(.degrees(bellAnimating ? -15 : 0))
                    .scaleEffect(bellAnimating ? 0.98 : 1.0)
                    .animation(Animation.easeInOut(duration: 0.25).repeatForever(autoreverses: true), value: bellAnimating)
                }
                .opacity(showContent ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.55), value: showContent)

                Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var finalPaywallTimelineContent: some View {
        VStack(spacing: 0) {
            Text(remoteConfig.hardPaywall ? "Start your 7-Day FREE trial to continue." : "Subscribe to Labely Unlimited")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(labelyOnboardingTextGreen)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, horizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 30)
                .opacity(showContent ? 1 : 0)
                .animation(.easeOut(duration: 0.6).delay(0.25), value: showContent)

                Spacer()
                .frame(height: 30)

                VStack(spacing: 0) {
                TimelineItem(
                    icon: "lock.fill",
                    iconColor: labelyOnboardingPrimaryGreen,
                    title: "Today",
                    description: "Unlock Labely's scanner, risky ingredient alerts, clean swaps, and personalized food guidance.",
                    isLast: false,
                    showContent: showContent,
                    lineColor: labelyOnboardingPrimaryGreen,
                    lineHeight: 100,
                    iconTopPadding: 15,
                    textTopPadding: 25,
                    showLine: true
                )

                TimelineItem(
                    icon: "bell.fill",
                    iconColor: labelyOnboardingPrimaryGreen,
                    title: "In 2 days - Reminder",
                    description: "We'll send you a reminder that your free trial is ending soon.",
                    isLast: false,
                    showContent: showContent,
                    lineColor: labelyOnboardingPrimaryGreen,
                    lineHeight: 80,
                    iconTopPadding: 15,
                    textTopPadding: 25,
                    showLine: true
                )

                TimelineItem(
                    icon: "plus",
                    iconColor: labelyOnboardingPrimaryGreen,
                    title: "In 7 days - Billing Starts",
                    description: "You'll be charged unless you cancel anytime before.",
                    isLast: true,
                    showContent: showContent,
                    lineColor: labelyOnboardingPrimaryGreen,
                    lineHeight: 80,
                    iconTopPadding: 15,
                    textTopPadding: 25,
                    showLine: true
                        )
                    }
                    .padding(.horizontal, horizontalPadding)
            .opacity(showContent ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.55), value: showContent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var finalPaywallBottomBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if remoteConfig.hardPaywall {
                    noPaymentDueBadge
                }

                if currentPaywallStep == 1 {
                    Button(action: advanceToTimelinePaywall) {
                        HStack(spacing: 10) {
                            if prefetchingTimeline {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            }
                            Text(prefetchingTimeline ? "Loading..." : (remoteConfig.hardPaywall ? "Try for $0.00" : "Try Labely"))
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(prefetchingTimeline ? Color.gray : labelyOnboardingPrimaryGreen))
                    }
                    .buttonStyle(LabelyOnboardingPressableButtonStyle())
                    .disabled(prefetchingTimeline)

                    if !remoteConfig.hardPaywall {
                        Text("No commitment, cancel anytime.")
                            .font(.system(size: 14))
                            .foregroundColor(labelyOnboardingTextGreen.opacity(0.62))
                    }
                } else {
                    Button(action: { Task { await purchaseYearly() } }) {
                        HStack(spacing: 10) {
                            if isPurchasing || storeManager.isLoadingProducts || storeManager.subscriptions.isEmpty {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            }
                            Text(isPurchasing ? "Processing..." : (storeManager.subscriptions.isEmpty ? "Loading..." : (remoteConfig.hardPaywall ? "Try for $0.00" : "Start my 7-Day Free Trial")))
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill((isPurchasing || storeManager.subscriptions.isEmpty) ? Color.gray : labelyOnboardingPrimaryGreen))
                    }
                    .buttonStyle(LabelyOnboardingPressableButtonStyle())
                    .disabled(isPurchasing || storeManager.subscriptions.isEmpty)

                    if !remoteConfig.hardPaywall {
                        Text(renewalDisclaimerText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white.opacity(0.96), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        .opacity(showContent ? 1 : 0)
        .animation(.easeOut(duration: 0.45).delay(0.2), value: showContent)
    }

    private func handleFinalPaywallBack() {
        if currentPaywallStep == 2 {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentPaywallStep = 1
            }
        } else {
            onBack()
        }
    }

    private func advanceToTimelinePaywall() {
        guard !prefetchingTimeline else { return }
        Task { @MainActor in
            prefetchingTimeline = true
            _ = await storeManager.loadProductsWithRetry()
            prefetchingTimeline = false
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPaywallStep = 2
            }
        }
    }

    private var noPaymentDueBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(labelyOnboardingTextGreen)
            Text("No Payment Due Now")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(labelyOnboardingTextGreen)
        }
    }

    private var renewalDisclaimerText: String {
        guard let p = annualProduct else {
            return remoteConfig.hardPaywall
                ? "7 days FREE, then billed annually at the App Store price."
                : "Free trial, then billed annually at the App Store price."
        }
        let perMo = Self.formattedApproxMonthly(from: p)
        if remoteConfig.hardPaywall {
            return "7 days FREE, then \(p.displayPrice) per year (\(perMo))"
        }
        return "Billed \(p.displayPrice) per year (\(perMo))"
    }

    private static func formattedApproxMonthly(from product: Product) -> String {
        let annual = NSDecimalNumber(decimal: product.price).doubleValue
        let perMonth = annual / 12.0
        return String(format: "$%.2f /mo", perMonth)
    }

    private var singleYearlyPlanCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if remoteConfig.hardPaywall {
                Text("7-DAY FREE TRIAL")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(labelyOnboardingLaunchGreen)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Yearly")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
                    if let p = annualProduct {
                        Text("\(p.displayPrice) /yr")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.55))
                    } else {
                        Text(storeManager.isLoadingProducts ? "Loading price…" : "— /yr")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.black.opacity(0.45))
                    }
                }
                Spacer()
                if let p = annualProduct {
                    Text(Self.formattedApproxMonthly(from: p))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(labelyOnboardingTextGreen)
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(labelyOnboardingPrimaryGreen, lineWidth: 2.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var footerLinks: some View {
        HStack(spacing: 10) {
            Button("Terms") {
                showingTermsOfService = true
            }
            Text("·")
                .foregroundColor(Color.black.opacity(0.35))
            Button("Privacy Policy") {
                showingPrivacyPolicy = true
            }
            Text("·")
                .foregroundColor(Color.black.opacity(0.35))
            Button("Restore") {
                Task { await restorePurchasesFromFinalPaywall() }
            }
            .disabled(isRestoring)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(Color.black.opacity(0.45))
    }

    private func finalPaywallTestimonialCard(imageName: String, name: String, handle: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                OnboardingReviewerAvatarView(
                    materialBasename: labelyOnboardingReviewerPortraitBasename(displayName: name),
                    legacyAssetName: imageName,
                    initial: String(name.first ?? "?"),
                    accentColor: Color(red: 0.42, green: 0.50, blue: 0.44),
                    size: 48
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
                    Text(handle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.black.opacity(0.45))
                }

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(testimonialGold)
                    }
                }
            }

            Text(body)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    @MainActor
    private func purchaseYearly() async {
        guard !isPurchasing else { return }
        isPurchasing = true

        do {
            MixpanelService.shared.trackSubscriptionViewed(planType: "yearly")
            let loaded = await storeManager.loadProductsWithRetry()
            if !loaded {
                errorMessage = "Unable to load subscription products. Please check your connection and try again."
                showError = true
                isPurchasing = false
                return
            }

            guard let subscription = annualProduct else {
                errorMessage = "Unable to load subscription. Please try again."
                showError = true
                isPurchasing = false
                return
            }

            let result = try await subscription.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let price = Double(truncating: NSDecimalNumber(decimal: subscription.price))
                    MixpanelService.shared.trackSubscriptionPurchased(planType: "yearly", price: price)
                    if #available(iOS 15.4, *) {
                        SKAdNetwork.updatePostbackConversionValue(63) { err in
                            if let err { print("⚠️ SKAdNetwork: \(err)") }
                        }
                    } else if #available(iOS 14.0, *) {
                        SKAdNetwork.updateConversionValue(63)
                    }
                    PendingMetaEventService.shared.storePendingPurchase(
                        transactionId: String(transaction.id),
                        price: price,
                        planType: "yearly",
                        currency: "USD"
                    )
                    await transaction.finish()
                    await storeManager.updateSubscriptionStatus()
                    authManager.markSubscriptionCompleted()
                    isPurchasing = false
                    if !authManager.isLoggedIn {
                        navigateToCreateAccount = true
                    } else {
                        onFinished()
                    }
                case .unverified:
                    throw StoreError.failedVerification
                }
            case .pending:
                throw StoreError.pending
            case .userCancelled:
                isPurchasing = false
                showWinback = true
            @unknown default:
                throw StoreError.unknown
            }
        } catch StoreError.pending {
            errorMessage = "Purchase is pending"
            showError = true
            isPurchasing = false
        } catch {
            errorMessage = "Failed to make purchase"
            showError = true
            isPurchasing = false
        }
    }

    @MainActor
    private func purchaseTwoPaywallSelection() async {
        if catalogYearlyPlanSelected {
            await purchaseYearly()
        } else {
            await purchaseWeekly()
        }
    }

    @MainActor
    private func purchaseWeekly() async {
        guard !isPurchasing else { return }
        isPurchasing = true

        do {
            MixpanelService.shared.trackSubscriptionViewed(planType: "weekly")
            let loaded = await storeManager.loadProductsWithRetry()
            if !loaded {
                errorMessage = "Unable to load subscription products. Please check your connection and try again."
                showError = true
                isPurchasing = false
                return
            }

            guard let subscription = weeklyProduct else {
                errorMessage = "Weekly plan isn’t available on this storefront yet."
                showError = true
                isPurchasing = false
                return
            }

            let result = try await subscription.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let price = Double(truncating: NSDecimalNumber(decimal: subscription.price))
                    MixpanelService.shared.trackSubscriptionPurchased(planType: "weekly", price: price)
                    if #available(iOS 15.4, *) {
                        SKAdNetwork.updatePostbackConversionValue(55) { err in
                            if let err { print("⚠️ SKAdNetwork: \(err)") }
                        }
                    } else if #available(iOS 14.0, *) {
                        SKAdNetwork.updateConversionValue(55)
                    }
                    PendingMetaEventService.shared.storePendingPurchase(
                        transactionId: String(transaction.id),
                        price: price,
                        planType: "weekly",
                        currency: "USD"
                    )
                    await transaction.finish()
                    await storeManager.updateSubscriptionStatus()
                    authManager.markSubscriptionCompleted()
                    isPurchasing = false
                    if !authManager.isLoggedIn {
                        navigateToCreateAccount = true
                    } else {
                        onFinished()
                    }
                case .unverified:
                    throw StoreError.failedVerification
                }
            case .pending:
                throw StoreError.pending
            case .userCancelled:
                isPurchasing = false
                showWinback = true
            @unknown default:
                throw StoreError.unknown
            }
        } catch StoreError.pending {
            errorMessage = "Purchase is pending"
            showError = true
            isPurchasing = false
        } catch {
            errorMessage = "Failed to make purchase"
            showError = true
            isPurchasing = false
        }
    }

    @MainActor
    private func restorePurchasesFromFinalPaywall() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await storeManager.updateSubscriptionStatus()
            guard storeManager.isSubscribed else {
                errorMessage = "No active subscription was found to restore."
                showError = true
                return
            }

            authManager.markSubscriptionCompleted()
            if !authManager.isLoggedIn {
                navigateToCreateAccount = true
            }
        } catch {
            errorMessage = "Failed to restore purchases"
            showError = true
        }
    }
}

private enum SafeguardsLoadingHaptics {
    private static let generator = UIImpactFeedbackGenerator(style: .heavy)
    static func countTick() {
        generator.impactOccurred(intensity: 1.0)
    }
}

private struct SafeguardsLoadingOnboardingView: View {
    let onBack: () -> Void
    let onFinished: () -> Void

    @State private var progress: CGFloat = 0
    @State private var progressText = "0%"
    @State private var statusText = "Initializing your safeguards..."
    @State private var showChecklist = false
    @State private var checkItems: [Bool] = [false, false, false, false, false]
    @State private var didComplete = false
    @State private var loadCancelled = false

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    private let checklistTitles = [
        "Toxins",
        "Seed oils",
        "Clean swaps",
        "Allergens",
        "Label scanner"
    ]

    /// Percent → (status line, optional checklist index to mark done). Mirrors legacy `LoadingView` freeze pacing.
    private let freezePoints: [Int: (String, Int)] = [
        22: ("Mapping toxins & risky additives...", 0),
        40: ("Profiling seed oil patterns...", 1),
        58: ("Preparing clean swap paths...", 2),
        76: ("Activating allergen alerts...", 3),
        94: ("Turning on label scanner...", 4)
    ]

    var body: some View {
        ZStack {
            Color(
                red: CGFloat(0xF8) / 255,
                green: CGFloat(0xF7) / 255,
                blue: CGFloat(0xF2) / 255
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                    }
                    .buttonStyle(.plain)

                    GeometryReader { g in
                        let spacing: CGFloat = 3
                        let total = 6
                        let segW = (g.size.width - CGFloat(total - 1) * spacing) / CGFloat(total)
                        HStack(spacing: spacing) {
                            ForEach(0..<total, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(i < total - 1 ? labelyOnboardingPrimaryGreen : labelyOnboardingPrimaryGreen.opacity(0.2))
                                    .frame(width: segW, height: 5)
                            }
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)

                Spacer(minLength: 12)

                Text(progressText)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(labelyOnboardingTextGreen)

                Text("We're setting everything up for you")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(labelyOnboardingTextGreen.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                Spacer(minLength: 20)

                VStack(spacing: 14) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.65))
                                .frame(height: 8)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.39, green: 0.69, blue: 0.37),
                                            Color(red: 0.68, green: 0.82, blue: 0.47),
                                            Color(red: 0.99, green: 0.84, blue: 0.36)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * progress), height: 8)
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, horizontalPadding)

                    Text(statusText)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Activating your safeguards:")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)

                    ForEach(Array(checklistTitles.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .center) {
                            Text("• \(item)")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.12))
                            Spacer()
                            if checkItems[index] {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(labelyOnboardingPrimaryGreen))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, horizontalPadding + 4)
                .opacity(showChecklist ? 1 : 0)
                .animation(.easeOut(duration: 0.45), value: showChecklist)

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            guard !didComplete else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                guard !loadCancelled else { return }
                showChecklist = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                runCount(from: 1)
            }
        }
        .onDisappear {
            loadCancelled = true
        }
    }

    private func runCount(from current: Int) {
        if loadCancelled { return }
        if current > 100 {
            DispatchQueue.main.async {
                guard !loadCancelled else { return }
                if !checkItems[4] { checkItems[4] = true }
                statusText = "You're all set!"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard !loadCancelled, !didComplete else { return }
                didComplete = true
                onFinished()
            }
            return
        }

        if let (message, checkIndex) = freezePoints[current] {
            DispatchQueue.main.async {
                guard !loadCancelled else { return }
                statusText = message
                if checkIndex >= 0 && checkIndex < checkItems.count {
                    checkItems[checkIndex] = true
                }
                progress = CGFloat(current) / 100.0
                progressText = "\(current)%"
            }
            let pause: Double = current >= 94 ? 1.35 : 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                runCount(from: current + 1)
            }
            return
        }

        DispatchQueue.main.async {
            guard !loadCancelled else { return }
            progress = CGFloat(current) / 100.0
            progressText = "\(current)%"
            SafeguardsLoadingHaptics.countTick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            runCount(from: current + 1)
        }
    }
}

// MARK: - "Which additives do you want to avoid most?" (step 9)

private enum LabelyAdditiveChoice: Int, CaseIterable, Identifiable {
    case seedOils, artificialAdditives, heavyMetals, allOfTheAbove
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .seedOils:             return "Seed Oils"
        case .artificialAdditives:  return "Artificial Additives"
        case .heavyMetals:          return "Heavy Metals"
        case .allOfTheAbove:        return "All of the above"
        }
    }

    var icon: String {
        switch self {
        case .seedOils:             return "drop.fill"
        case .artificialAdditives:  return "atom"
        case .heavyMetals:          return "scalemass.fill"
        case .allOfTheAbove:        return "checkmark.seal.fill"
        }
    }

    var description: String {
        switch self {
        case .seedOils:
            return "Labely flags products with refined seed oils (canola, soy, sunflower, etc.) and suggests cleaner alternatives for you and your family."
        case .artificialAdditives:
            return "Labely screens for synthetic dyes, preservatives, and flavor enhancers that may impact health, and helps you find better options."
        case .heavyMetals:
            return "Labely tests products based on community votes to detect heavy metal contamination. We alert you to potential risks and help you find safer alternatives for you and your family."
        case .allOfTheAbove:
            return "Labely covers it all—seed oils, artificial additives, and heavy metals—so you can shop with full confidence."
        }
    }
}

private struct AdditivesToAvoidOnboardingView: View {
    let onBack: () -> Void
    let onContinue: (LabelyAdditiveChoice) -> Void

    @State private var expandedChoice: LabelyAdditiveChoice? = nil

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    var body: some View {
        GeometryReader { geo in
            let optionsMinHeight = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.white)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")

                        GeometryReader { g in
                            let spacing: CGFloat = 3
                            let segW = (g.size.width - spacing) / 2
                            HStack(spacing: spacing) {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(labelyOnboardingPrimaryGreen)
                                    .frame(width: segW, height: 5)
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(Color.white.opacity(0.42))
                                    .frame(width: segW, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text("Which additives do you\nwant to avoid most?")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(spacing: 10) {
                                ForEach(LabelyAdditiveChoice.allCases) { choice in
                                    AdditiveDropdownRow(
                                        choice: choice,
                                        isExpanded: expandedChoice == choice,
                                        onTap: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                                expandedChoice = (expandedChoice == choice) ? nil : choice
                                            }
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: optionsMinHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: {
                            if let expandedChoice {
                                onContinue(expandedChoice)
                            }
                        }) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(expandedChoice == nil ? Color.white.opacity(0.5) : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    Capsule()
                                        .fill(expandedChoice == nil ? labelyOnboardingPrimaryGreen.opacity(0.45) : labelyOnboardingPrimaryGreen)
                                )
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                        .disabled(expandedChoice == nil)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
    }
}

private struct AdditiveDropdownRow: View {
    let choice: LabelyAdditiveChoice
    let isExpanded: Bool
    let onTap: () -> Void

    private var cardFill: Color {
        isExpanded ? labelyOnboardingPrimaryGreen.opacity(0.14) : Color.white
    }

    private var cardStroke: Color {
        isExpanded ? labelyOnboardingPrimaryGreen : Color.black.opacity(0.06)
    }

    private var cardStrokeWidth: CGFloat {
        isExpanded ? 2.5 : 1
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: choice.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isExpanded ? labelyOnboardingPrimaryGreen : labelyOnboardingTextGreen)
                        .frame(width: 28)

                    Text(choice.label)
                        .font(.system(size: 16, weight: isExpanded ? .bold : .semibold))
                        .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.10))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isExpanded ? labelyOnboardingPrimaryGreen : Color(red: 0.50, green: 0.50, blue: 0.50))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)

                if isExpanded {
                    Divider()
                        .padding(.horizontal, 18)

                    Text(choice.description)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(red: 0.30, green: 0.30, blue: 0.30))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardFill)
                    .shadow(color: Color.black.opacity(isExpanded ? 0.10 : 0.06), radius: isExpanded ? 12 : 8, x: 0, y: isExpanded ? 4 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: cardStrokeWidth)
            )
        }
        .buttonStyle(LabelyOnboardingPressableButtonStyle())
    }
}

// MARK: - Mascot splash (step 0) — slogan, then `main` hero video (Thrifty `main.mp4` height); video ends → fade → next

private struct NewLabelyMascotIntroView: View {
    /// Called after the video fades out, then the splash background fades out.
    let onFinishSplash: () -> Void

    private let videoFadeOutDuration: TimeInterval = 0.45
    private let backgroundFadeOutDuration: TimeInterval = 0.4

    @State private var showMarketingVideo = false
    @State private var videoOpacity: Double = 1
    @State private var backgroundOpacity: Double = 1

    var body: some View {
        ZStack {
            labelyOnboardingLaunchGreen
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if !showMarketingVideo {
                    VStack(spacing: 6) {
                        Text("Live cleaner.")
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text("Feel better")
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundColor(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                } else {
                    LabelyThriftyStyleMainMarketingVideoBlock(
                        loops: false,
                        onPlayToEnd: runExitFadeThenFinish,
                        hostBackgroundUIColor: labelySplashScreenUIColor,
                        uiOpacity: videoOpacity,
                        bottomPadding: 0
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .layoutPriority(1)
                    .padding(.horizontal, 12)
                }
                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.45)) {
                    showMarketingVideo = true
                }
            }
        }
    }

    private func runExitFadeThenFinish() {
        withAnimation(.easeOut(duration: videoFadeOutDuration)) {
            videoOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + videoFadeOutDuration) {
            withAnimation(.easeOut(duration: backgroundFadeOutDuration)) {
                backgroundOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + backgroundFadeOutDuration) {
                onFinishSplash()
            }
        }
    }
}

// MARK: - Welcome / continue (step 1), modeled on `ContentView` landing

private enum NewOnboardingWelcomeTypingHaptic {
    static let generator = UIImpactFeedbackGenerator(style: .heavy)
}

private struct NewOnboardingWelcomeTypingCaret: View {
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 0.48)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let on = Int(phase / 0.48) % 2 == 0
            Capsule()
                .fill(labelyOnboardingSloganGreen)
                .frame(width: 3, height: height)
                .opacity(on ? 1 : 0.22)
        }
    }
}

private struct NewOnboardingWelcomeScreen: View {
    let onContinue: () -> Void
    let onSignIn: () -> Void
    @StateObject private var authManager = AuthenticationManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sloganLine1 = "Live cleaner."
    private static let sloganLine2 = "Feel better"
    private static let sloganFont = Font.system(size: 40, weight: .bold, design: .default)
    private static let perCharacterDelayNs: UInt64 = 52_000_000
    private static let betweenLinesPauseNs: UInt64 = 580_000_000

    @State private var line1Typed = ""
    @State private var line2Typed = ""
    @State private var caretPhase: CaretPhase = .beforeTyping
    @State private var restChromeOpacity: Double = 0
    @State private var restChromeOffset: CGFloat = 22
    @State private var showMainMarketingVideo = false
    @State private var typingTask: Task<Void, Never>?

    private enum CaretPhase {
        case beforeTyping
        case line1
        case pauseBetweenLines
        case line2
        case finished
    }

    var body: some View {
        VStack(spacing: 0) {
            if showMainMarketingVideo {
                welcomeSloganCompletedStatic
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }

            ZStack {
                LabelyThriftyStyleMainMarketingVideoBlock(
                    loops: true,
                    onPlayToEnd: nil,
                    hostBackgroundUIColor: .white,
                    bottomPadding: 0,
                    clipCornerRadius: labelyOnboardingWelcomeHeroVideoCornerRadius
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showMainMarketingVideo ? 1 : 0)

                // Opaque veil + typing centered; video runs muted underneath during typing so the first frames are buffered.
                Color.white
                    .opacity(showMainMarketingVideo ? 0 : 1)
                    .allowsHitTesting(false)

            welcomeSloganTypingBlock
                .padding(.horizontal, 24)
                    .opacity(showMainMarketingVideo ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(labelyOnboardingPrimaryGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
                .padding(.top, 6)

                if !authManager.isLoggedIn {
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(.system(size: 15))
                            .foregroundColor(labelyOnboardingTextGreen)
                        Button(action: onSignIn) {
                            Text("Sign in")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(labelyOnboardingTextGreen)
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .opacity(restChromeOpacity)
            .offset(y: -restChromeOffset * 0.35)
            .allowsHitTesting(restChromeOpacity > 0.65)
        }
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            startWelcomeSequenceIfNeeded()
        }
        .onDisappear {
            typingTask?.cancel()
            typingTask = nil
        }
    }

    private var welcomeSloganTypingBlock: some View {
        let caretH: CGFloat = 34
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(line1Typed)
                    .font(Self.sloganFont)
                    .foregroundColor(labelyOnboardingSloganGreen)
                    .kerning(-0.3)
                if caretPhase == .line1 || caretPhase == .pauseBetweenLines {
                    NewOnboardingWelcomeTypingCaret(height: caretH)
                        .padding(.leading, 2)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(line2Typed)
                    .font(Self.sloganFont)
                    .foregroundColor(labelyOnboardingSloganGreen)
                    .kerning(-0.3)
                if caretPhase == .line2 {
                    NewOnboardingWelcomeTypingCaret(height: caretH)
                        .padding(.leading, 2)
                }
            }
            .frame(minHeight: 44)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Self.sloganLine1) \(Self.sloganLine2)"))
    }

    /// Full “Live cleaner. / Feel better” copy above the hero video (same styling as the typing phase, without the caret).
    private var welcomeSloganCompletedStatic: some View {
        VStack(spacing: 2) {
            Text(Self.sloganLine1)
                .font(Self.sloganFont)
                .foregroundColor(labelyOnboardingSloganGreen)
                .kerning(-0.3)
            Text(Self.sloganLine2)
                .font(Self.sloganFont)
                .foregroundColor(labelyOnboardingSloganGreen)
                .kerning(-0.3)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Self.sloganLine1) \(Self.sloganLine2)"))
    }

    private func startWelcomeSequenceIfNeeded() {
        typingTask?.cancel()
        if reduceMotion {
            line1Typed = Self.sloganLine1
            line2Typed = Self.sloganLine2
            caretPhase = .finished
            showMainMarketingVideo = true
            withAnimation(.easeOut(duration: 0.4)) {
                restChromeOpacity = 1
                restChromeOffset = 0
            }
            return
        }

        line1Typed = ""
        line2Typed = ""
        caretPhase = .beforeTyping
        restChromeOpacity = 0
        restChromeOffset = 22
        showMainMarketingVideo = false

        typingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            caretPhase = .line1
            NewOnboardingWelcomeTypingHaptic.generator.prepare()

            for count in 1 ... Self.sloganLine1.count {
                guard !Task.isCancelled else { return }
                if count > 1 {
                    try? await Task.sleep(nanoseconds: Self.perCharacterDelayNs)
                }
                line1Typed = String(Self.sloganLine1.prefix(count))
                NewOnboardingWelcomeTypingHaptic.generator.impactOccurred()
            }

            guard !Task.isCancelled else { return }
            caretPhase = .pauseBetweenLines
            try? await Task.sleep(nanoseconds: Self.betweenLinesPauseNs)

            guard !Task.isCancelled else { return }
            caretPhase = .line2
            NewOnboardingWelcomeTypingHaptic.generator.prepare()

            for count in 1 ... Self.sloganLine2.count {
                guard !Task.isCancelled else { return }
                if count > 1 {
                    try? await Task.sleep(nanoseconds: Self.perCharacterDelayNs)
                }
                line2Typed = String(Self.sloganLine2.prefix(count))
                NewOnboardingWelcomeTypingHaptic.generator.impactOccurred()
            }

            guard !Task.isCancelled else { return }
            caretPhase = .finished

            try? await Task.sleep(nanoseconds: 400_000_000)

            withAnimation(.easeOut(duration: 0.5)) {
                showMainMarketingVideo = true
            }
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.72, dampingFraction: 0.88)) {
                restChromeOpacity = 1
                restChromeOffset = 0
            }
        }
    }
}

// MARK: - Choose your team (step 2) — `onboarding-material/bg` + team cards

private enum LabelyOnboardingTeamChoice: String, CaseIterable {
    case cleanLivingGirlie
    case holisticHealthBro
    case mamaBearProtector
    case wellnessWarriorDad

    var imageAssetName: String {
        switch self {
        case .cleanLivingGirlie: return "clean-living-girlie"
        case .holisticHealthBro: return "holidstic-health-bro"
        case .mamaBearProtector: return "mama-bear-protector"
        case .wellnessWarriorDad: return "wellness-warrior-dad"
        }
    }

    /// Two-line labels matching Figma.
    var titleLines: (String, String) {
        switch self {
        case .cleanLivingGirlie: return ("Clean-Living", "Girlie")
        case .holisticHealthBro: return ("Holistic Health", "Bro")
        case .mamaBearProtector: return ("Mama Bear", "Protector")
        case .wellnessWarriorDad: return ("Wellness Warrior", "Dad")
        }
    }

    var testimonialPortraitBasenames: (first: String, second: String) {
        switch self {
        case .cleanLivingGirlie: return ("girl1", "girl2")
        case .holisticHealthBro: return ("boy1", "boy2")
        case .mamaBearProtector: return ("mom1", "mom2")
        case .wellnessWarriorDad: return ("dad1", "dad2")
        }
    }
}

private struct ChooseTeamOnboardingView: View {
    var headingTitle: String = "Choose your team"
    let onBack: () -> Void
    let onSelectTeam: (LabelyOnboardingTeamChoice) -> Void

    private static let progressFraction: CGFloat = 0.22
    private static let teamStorageKey = "labely_onboarding_team_choice"

    private let gridSpacing: CGFloat = 14
    private let horizontalPadding: CGFloat = labelyV2OnboardingHeaderSideInset
    private let cardCornerRadius: CGFloat = 18
    @State private var didSelectTeam = false

    var body: some View {
        GeometryReader { geo in
            let gridWidth = geo.size.width - horizontalPadding * 2
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)

            ZStack {
                VStack(spacing: 0) {
                    chooseTeamHeaderRow()
                        .padding(.horizontal, horizontalPadding)

                    Text(headingTitle)
                        .font(.system(size: 30, weight: .bold, design: .default))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    Text("We'll personalize your experience")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(labelyChooseTeamSubtitleOlive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 10)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(minimum: 0), spacing: gridSpacing),
                                    GridItem(.flexible(minimum: 0), spacing: gridSpacing)
                                ],
                                spacing: gridSpacing
                            ) {
                                ForEach(LabelyOnboardingTeamChoice.allCases, id: \.rawValue) { team in
                                    teamCard(
                                        team,
                                        columnWidth: (gridWidth - gridSpacing) / 2,
                                        isSelected: false
                                    )
                                }
                            }
                            .frame(width: gridWidth)
                            .frame(maxWidth: .infinity)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
    }

    /// Same row layout as legacy onboarding (`HStack` back + track, `spacing: 16`); white arrow on hills background.
    @ViewBuilder
    private func chooseTeamHeaderRow() -> some View {
        HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                    Capsule()
                        .fill(labelyOnboardingPrimaryGreen)
                        .frame(width: max(5, w * Self.progressFraction))
                }
            }
            .frame(height: 5)
        }
        .padding(.top, 8)
    }

    private func teamCard(_ team: LabelyOnboardingTeamChoice, columnWidth: CGFloat, isSelected: Bool) -> some View {
        let lines = team.titleLines
        return Button {
            guard !didSelectTeam else { return }
            didSelectTeam = true
            UserDefaults.standard.set(team.rawValue, forKey: Self.teamStorageKey)
            onSelectTeam(team)
        } label: {
            VStack(spacing: 0) {
                OnboardingMaterialImage.swiftUIImage(named: team.imageAssetName)
                    .scaledToFit()
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: columnWidth * 0.72, maxHeight: columnWidth * 0.95)

                VStack(spacing: 2) {
                    Text(lines.0)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                    Text(lines.1)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                }
                .foregroundColor(Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.bottom, 14)
                .padding(.top, 4)
            }
            .frame(width: columnWidth)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(labelyOnboardingPictureCardFill)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(labelyOnboardingPrimaryGreen, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(LabelyOnboardingPressableButtonStyle())
        .allowsHitTesting(!didSelectTeam)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Cleaner products motivations (step 3) — select all that apply

private enum LabelyCleanerProductMotivation: String, CaseIterable, Hashable {
    case liveHealthier
    case betterSleep
    case clearerThinking
    case moreEnergy
    case happierSkin
    case healthierFamily

    var imageAssetName: String {
        switch self {
        case .liveHealthier: return "live-healthier"
        case .betterSleep: return "better-sleep"
        case .clearerThinking: return "clearer-thinking"
        case .moreEnergy: return "more-energy"
        case .happierSkin: return "happier-skin"
        case .healthierFamily: return "healthier-family"
        }
    }

    var label: String {
        switch self {
        case .liveHealthier: return "Live healthier"
        case .betterSleep: return "Better sleep"
        case .clearerThinking: return "Clearer thinking"
        case .moreEnergy: return "More energy"
        case .happierSkin: return "Happier skin"
        case .healthierFamily: return "Healthier family"
        }
    }
}

private struct CleanerProductsMotivationsOnboardingView: View {
    let onBack: () -> Void
    let onContinue: (Set<LabelyCleanerProductMotivation>) -> Void

    private static let motivationsStorageKey = "labely_onboarding_cleaner_motivations"

    private let gridSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = labelyV2OnboardingHeaderSideInset
    private let cardCornerRadius: CGFloat = 20
    private let segmentCount = 4
    private let filledSegmentCount = 1

    @State private var selected: Set<LabelyCleanerProductMotivation> = []

    var body: some View {
        GeometryReader { geo in
            let gridWidth = geo.size.width - horizontalPadding * 2
            let columnWidth = (gridWidth - gridSpacing) / 2
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)

            ZStack {
                VStack(spacing: 0) {
                    motivationsHeaderRow()
                        .padding(.horizontal, horizontalPadding)

                    Text("Why do you want to eat cleaner?")
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 18)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(minimum: 0), spacing: gridSpacing),
                                    GridItem(.flexible(minimum: 0), spacing: gridSpacing)
                                ],
                                spacing: gridSpacing
                            ) {
                                ForEach(LabelyCleanerProductMotivation.allCases, id: \.self) { motivation in
                                    motivationCard(motivation, columnWidth: columnWidth, isSelected: selected.contains(motivation))
                                }
                            }
                            .frame(width: gridWidth)
                            .frame(maxWidth: .infinity)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: commitAndContinue) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    Capsule()
                                        .fill(labelyOnboardingPrimaryGreen)
                                )
                                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                        .disabled(selected.isEmpty)
                        .opacity(selected.isEmpty ? 0.45 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
    }

    private func commitAndContinue() {
        let raw = selected.map(\.rawValue).sorted()
        UserDefaults.standard.set(raw, forKey: Self.motivationsStorageKey)
        onContinue(selected)
    }

    @ViewBuilder
    private func motivationsHeaderRow() -> some View {
        HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GeometryReader { g in
                segmentedProgressBar(fullWidth: g.size.width)
            }
            .frame(height: 5)
        }
        .padding(.top, 8)
    }

    private func segmentedProgressBar(fullWidth: CGFloat) -> some View {
        let spacing: CGFloat = 3
        let segmentBodyWidth = (fullWidth - CGFloat(segmentCount - 1) * spacing) / CGFloat(segmentCount)
        return HStack(spacing: spacing) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(index < filledSegmentCount ? labelyOnboardingPrimaryGreen : Color.white.opacity(0.42))
                    .frame(width: segmentBodyWidth, height: 5)
            }
        }
        .frame(width: fullWidth, height: 5)
    }

    private func motivationCard(_ motivation: LabelyCleanerProductMotivation, columnWidth: CGFloat, isSelected: Bool) -> some View {
        Button {
            if selected.contains(motivation) {
                selected.remove(motivation)
            } else {
                selected.insert(motivation)
            }
        } label: {
            VStack(spacing: 0) {
                OnboardingMaterialImage.swiftUIImage(named: motivation.imageAssetName)
                    .scaledToFit()
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: columnWidth * 0.58, maxHeight: columnWidth * 0.78)

                Text(motivation.label)
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundColor(labelyOnboardingTextGreen)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 12)
                    .padding(.top, 2)
            }
            .frame(width: columnWidth)
            .background(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(labelyOnboardingPictureCardFill)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(labelyOnboardingPrimaryGreen, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .buttonStyle(LabelyOnboardingPressableButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Testimonial data model

private struct LabelyOnboardingReview {
    let title: String
    let body: String
    let reviewer: String
    let accentColor: Color
    let portraitBasenameOverride: String?

    init(title: String, body: String, reviewer: String, accentColor: Color, portraitBasenameOverride: String? = nil) {
        self.title = title
        self.body = body
        self.reviewer = reviewer
        self.accentColor = accentColor
        self.portraitBasenameOverride = portraitBasenameOverride
    }

    var initial: String { String(reviewer.first ?? "?").uppercased() }
    /// Add `onboarding-material/<basename>.png` (square, ~512–1024px) for a realistic portrait; otherwise the colored initial circle shows.
    var portraitBasename: String { portraitBasenameOverride ?? labelyOnboardingReviewerPortraitBasename(displayName: reviewer) }

    func withPortraitBasename(_ basename: String) -> LabelyOnboardingReview {
        .init(title: title, body: body, reviewer: reviewer, accentColor: accentColor, portraitBasenameOverride: basename)
    }
}

private struct LabelyOnboardingTestimonialContent {
    let heading: String
    let firstSubtitle: String
    let secondSubtitle: String
    let first: LabelyOnboardingReview
    let second: LabelyOnboardingReview

    // Convenience init when both slides share the same subtitle
    init(heading: String, subtitle: String, first: LabelyOnboardingReview, second: LabelyOnboardingReview) {
        self.heading = heading
        self.firstSubtitle = subtitle
        self.secondSubtitle = subtitle
        self.first = first
        self.second = second
    }

    /// When the first and second testimonial slides use different subtitle lines under the heading.
    init(heading: String, firstSubtitle: String, secondSubtitle: String, first: LabelyOnboardingReview, second: LabelyOnboardingReview) {
        self.heading = heading
        self.firstSubtitle = firstSubtitle
        self.secondSubtitle = secondSubtitle
        self.first = first
        self.second = second
    }

    func applyingPortraits(for team: LabelyOnboardingTeamChoice) -> LabelyOnboardingTestimonialContent {
        let portraits = team.testimonialPortraitBasenames
        return .init(
            heading: heading,
            firstSubtitle: firstSubtitle,
            secondSubtitle: secondSubtitle,
            first: first.withPortraitBasename(portraits.first),
            second: second.withPortraitBasename(portraits.second)
        )
    }
}

private extension LabelyCleanerProductMotivation {
    func testimonialContent(for team: LabelyOnboardingTeamChoice) -> LabelyOnboardingTestimonialContent {
        let content: LabelyOnboardingTestimonialContent
        switch team {
        case .holisticHealthBro:
            content = holisticHealthBroContent
        case .mamaBearProtector:
            content = mamaBearProtectorContent
        case .wellnessWarriorDad:
            content = wellnessWarriorDadContent
        default:
            content = cleanLivingGirlieContent
        }
        return content.applyingPortraits(for: team)
    }

    // MARK: Clean-Living Girlie testimonials (Figma screens 1)

    private var cleanLivingGirlieContent: LabelyOnboardingTestimonialContent {
        switch self {
        case .liveHealthier:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "live healthier in under\n12 weeks.",
                first: .init(title: "Clean made easy",
                             body: "\"I scan, it tells me the safer pick. Independent testing = peace of mind without hours of research.\"",
                             reviewer: "Kara N.", accentColor: Color(red: 0.80, green: 0.42, blue: 0.30)),
                second: .init(title: "Healthier, faster",
                              body: "\"Olive turned 'eat clean' into a plan. Smart Swaps each week—no more guessing, just better choices.\"",
                              reviewer: "Sofia P.", accentColor: Color(red: 0.50, green: 0.34, blue: 0.28)))
        case .betterSleep:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "sleep better in under\n12 weeks.",
                first: .init(title: "Real rest again",
                             body: "\"Their Smart Swaps removed late-night triggers. I fall asleep faster and stay asleep.\"",
                             reviewer: "Priya R.", accentColor: Color(red: 0.62, green: 0.36, blue: 0.26)),
                second: .init(title: "Sleep came back",
                              body: "\"Swapped a few 'healthy' snacks Olive flagged. Two weeks later I'm sleeping through the night.\"",
                              reviewer: "Hannah L.", accentColor: Color(red: 0.44, green: 0.58, blue: 0.44)))
        case .clearerThinking:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "eliminate brain fog in\nunder 12 weeks.",
                first: .init(title: "Clear & steady",
                             body: "\"I stopped overthinking labels. Scan → save → focus. It's a relief.\"",
                             reviewer: "Mina W.", accentColor: Color(red: 0.62, green: 0.46, blue: 0.34)),
                second: .init(title: "Brain fog lifted",
                              body: "\"Olive's swaps took out the stealth junk. My mornings are clear again—no mid-day haze.\"",
                              reviewer: "Danielle C.", accentColor: Color(red: 0.44, green: 0.34, blue: 0.58)))
        case .moreEnergy:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "boost energy levels in\nunder 12 weeks.",
                first: .init(title: "All-day steady",
                             body: "\"Olive flagged 'healthy' foods spiking me. Two swaps later I'm cruising till dinner.\"",
                             reviewer: "Renee A.", accentColor: Color(red: 0.72, green: 0.46, blue: 0.34)),
                second: .init(title: "Energy is back",
                              body: "\"Week 1: swapped oils and cereal. Week 2: no afternoon slump. Olive nailed it.\"",
                              reviewer: "Clara J.", accentColor: Color(red: 0.54, green: 0.44, blue: 0.64)))
        case .happierSkin:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "achieve clearer skin in\nunder 12 weeks.",
                first: .init(title: "Clearer, finally",
                             body: "\"Not another cream—just cleaner products. The breakouts chilled out with Olive's swaps.\"",
                             reviewer: "Nadia F.", accentColor: Color(red: 0.74, green: 0.34, blue: 0.34)),
                second: .init(title: "Skin calmed down",
                              body: "\"Olive helped me cut dyes/emulsifiers I didn't know I was eating. Redness faded in weeks.\"",
                              reviewer: "Emily R.", accentColor: Color(red: 0.44, green: 0.58, blue: 0.34)))
        case .healthierFamily:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "live healthier and happier\nin under 12 weeks.",
                first: .init(title: "Confident choices",
                             body: "\"Independent testing > marketing. My kitchen finally matches my standards.\"",
                             reviewer: "Ariel D.", accentColor: Color(red: 0.72, green: 0.34, blue: 0.24)),
                second: .init(title: "Healthier home base",
                              body: "\"Olive took the stress out of shopping. I know what's safe—without reading every line.\"",
                              reviewer: "Tori S.", accentColor: Color(red: 0.44, green: 0.44, blue: 0.58)))
        }
    }

    // MARK: Holistic Health Bro testimonials (Figma screens 2)

    private var holisticHealthBroContent: LabelyOnboardingTestimonialContent {
        switch self {
        case .liveHealthier:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "live healthier in under\n12 weeks.",
                first: .init(title: "Cleaner routine, zero fluff",
                             body: "\"Independent data, straight answers. My staples are dialed without getting weird about food.\"",
                             reviewer: "Ryan C.", accentColor: Color(red: 0.62, green: 0.38, blue: 0.28)),
                second: .init(title: "Simple, solid upgrades",
                              body: "\"Olive flagged the junk and gave me replacements I'll actually buy. Cleaner cart in one trip.\"",
                              reviewer: "Evan T.", accentColor: Color(red: 0.44, green: 0.52, blue: 0.36)))
        case .betterSleep:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "sleep better in under\n12 weeks.",
                first: .init(title: "Sleep that sticks",
                             body: "\"One scan session and my evening routine is fixed. No more random restlessness.\"",
                             reviewer: "Kyle D.", accentColor: Color(red: 0.58, green: 0.40, blue: 0.30)),
                second: .init(title: "Fewer 2 a.m. wakeups",
                              body: "\"Olive caught the additives that were wrecking my sleep. Cleaner picks, deeper nights.\"",
                              reviewer: "Marcus G.", accentColor: Color(red: 0.40, green: 0.50, blue: 0.44)))
        case .clearerThinking:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "eliminate brain fog in\nunder 12 weeks.",
                first: .init(title: "Dialed in",
                             body: "\"Independent data > hype. Cleaner inputs, better output. It's that simple.\"",
                             reviewer: "Noah K.", accentColor: Color(red: 0.60, green: 0.38, blue: 0.28)),
                second: .init(title: "Sharper afternoons",
                              body: "\"Swapped three 'healthy' foods Olive flagged. Meetings feel focused and I don't crash.\"",
                              reviewer: "Jared S.", accentColor: Color(red: 0.42, green: 0.48, blue: 0.38)))
        case .moreEnergy:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "boost energy levels in\nunder 12 weeks.",
                first: .init(title: "Solid fuel only",
                             body: "\"Seed-oil traps are gone. I feel it in workouts and late meetings.\"",
                             reviewer: "Tyler V.", accentColor: Color(red: 0.64, green: 0.40, blue: 0.26)),
                second: .init(title: "No crash days",
                              body: "\"Scan → better option → sustained energy. Wild how fast this worked.\"",
                              reviewer: "Alex M.", accentColor: Color(red: 0.40, green: 0.50, blue: 0.46)))
        case .happierSkin:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "achieve clearer skin in\nunder 12 weeks.",
                first: .init(title: "Cleaner inputs, better skin",
                             body: "\"Olive flagged stuff I'd never notice. Easy swaps, legit results.\"",
                             reviewer: "Adam B.", accentColor: Color(red: 0.56, green: 0.38, blue: 0.30)),
                second: .init(title: "Skin improved",
                              body: "\"Didn't expect it. Dropped a couple of 'normal' snacks and my skin looks better.\"",
                              reviewer: "Mark T.", accentColor: Color(red: 0.44, green: 0.46, blue: 0.40)))
        case .healthierFamily:
            return .init(heading: "We've helped\nthousands of people",
                subtitle: "live healthier and happier\nin under 12 weeks.",
                first: .init(title: "Better for the household",
                             body: "\"One scan session and our staples are safer. Easy to maintain, zero drama.\"",
                             reviewer: "Neil C.", accentColor: Color(red: 0.54, green: 0.42, blue: 0.32)),
                second: .init(title: "Cleaner kitchen, fast",
                              body: "\"Olive gives straight answers. I buy with confidence now.\"",
                              reviewer: "Omar J.", accentColor: Color(red: 0.44, green: 0.48, blue: 0.38)))
        }
    }

    // MARK: Mama Bear Protector testimonials (Figma screens 3)

    private var mamaBearProtectorContent: LabelyOnboardingTestimonialContent {
        switch self {
        case .liveHealthier:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "live healthier in under\n12 weeks.",
                first: .init(title: "Healthier home, finally",
                             body: "\"Kid-Safe Mode + weekly swaps = a pantry I'm proud of. It feels good to stop second-guessing.\"",
                             reviewer: "Sarah M.", accentColor: Color(red: 0.60, green: 0.40, blue: 0.30)),
                second: .init(title: "Trust I can feel",
                              body: "\"Olive's independent testing changed how I shop. Safer choices without the label anxiety.\"",
                              reviewer: "Jennifer K.", accentColor: Color(red: 0.46, green: 0.50, blue: 0.44)))
        case .betterSleep:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "achieve clearer skin in\nunder 12 weeks.",
                first: .init(title: "Happier skin, happier kid",
                             body: "\"Kid-Safe picks reduced flare-ups. Seeing her comfortable is everything.\"",
                             reviewer: "Paige N.", accentColor: Color(red: 0.60, green: 0.38, blue: 0.30)),
                second: .init(title: "Calmer skin in weeks",
                              body: "\"We swapped two snack brands Olive flagged. Less redness and itching—huge relief.\"",
                              reviewer: "Donna R.", accentColor: Color(red: 0.46, green: 0.52, blue: 0.46)))
        case .clearerThinking:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "eliminate brain fog in\nunder 12 weeks.",
                first: .init(title: "School-day focus",
                             body: "\"Kid-Safe Mode helped us cut the noisy additives. Mornings are smoother and homework clicks.\"",
                             reviewer: "Alyssa G.", accentColor: Color(red: 0.60, green: 0.38, blue: 0.30)),
                second: .init(title: "Clearer days",
                              body: "\"We replaced a few snacks Olive flagged and saw calmer, more focused afternoons.\"",
                              reviewer: "Brianna T.", accentColor: Color(red: 0.46, green: 0.52, blue: 0.42)))
        case .moreEnergy:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "boost energy levels in\nunder 12 weeks.",
                first: .init(title: "Afternoons are easier",
                             body: "\"The 3 pm crashes disappeared once we used Olive's kid-safe swaps. Huge difference.\"",
                             reviewer: "Kelsey D.", accentColor: Color(red: 0.62, green: 0.38, blue: 0.28)),
                second: .init(title: "Steady kids, happier mom",
                              body: "\"We replaced two snack staples and everyone's energy is calmer—not wired, not wiped.\"",
                              reviewer: "Monica H.", accentColor: Color(red: 0.48, green: 0.50, blue: 0.44)))
        case .happierSkin:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "sleep better in under\n12 weeks.",
                first: .init(title: "Calmer nights",
                             body: "\"Kid-Safe picks cut the bedtime battles. Everyone settles easier—and sleeps longer.\"",
                             reviewer: "Lena W.", accentColor: Color(red: 0.62, green: 0.40, blue: 0.30)),
                second: .init(title: "Better sleep for all",
                              body: "\"We swapped a few snack and drink staples. Bedtime isn't a war zone anymore.\"",
                              reviewer: "Tanya F.", accentColor: Color(red: 0.48, green: 0.52, blue: 0.46)))
        case .healthierFamily:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "live healthier and happier\nin under 12 weeks.",
                first: .init(title: "Healthier home, finally",
                             body: "\"Kid-Safe Mode + weekly swaps = a pantry I'm proud of. It feels good to stop second-guessing.\"",
                             reviewer: "Sarah M.", accentColor: Color(red: 0.60, green: 0.40, blue: 0.30)),
                second: .init(title: "Trust I can feel",
                              body: "\"Olive's independent testing changed how I shop. Safer choices without the label anxiety.\"",
                              reviewer: "Jennifer K.", accentColor: Color(red: 0.46, green: 0.50, blue: 0.44)))
        }
    }

    // MARK: Wellness Warrior Dad testimonials (Figma screens 4)

    private var wellnessWarriorDadContent: LabelyOnboardingTestimonialContent {
        switch self {
        case .liveHealthier:
            return .init(heading: "We've helped\nthousands of families",
                firstSubtitle: "live healthier in under\n12 weeks.",
                secondSubtitle: "live healthier and happier\nin under 12 weeks.",
                first: .init(title: "No more returns",
                             body: "\"Olive killed the guesswork. My wife approves the cart and the kids actually eat the swaps.\"",
                             reviewer: "James M.", accentColor: Color(red: 0.44, green: 0.50, blue: 0.38)),
                second: .init(title: "Safer pantry, zero hassle",
                              body: "\"Scan, swap, done. We eat better without adding time to the trip.\"",
                              reviewer: "Kevin R.", accentColor: Color(red: 0.56, green: 0.42, blue: 0.30)))
        case .betterSleep:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "sleep better in under\n12 weeks.",
                first: .init(title: "Night routine solved",
                             body: "\"Cleaner pantry, fewer wakeups. This is the easiest win we've had as parents.\"",
                             reviewer: "Rob P.", accentColor: Color(red: 0.44, green: 0.50, blue: 0.40)),
                second: .init(title: "Kids sleep better",
                              body: "\"Olive flagged dyes/sweeteners. Swapped them out—bedtime is smoother and mornings are easier.\"",
                              reviewer: "Chris H.", accentColor: Color(red: 0.54, green: 0.42, blue: 0.30)))
        case .clearerThinking:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "eliminate brain fog in\nunder 12 weeks.",
                first: .init(title: "Less chaos, more calm",
                             body: "\"Cleaner snacks = better attention. Olive made it effortless to find the right replacements.\"",
                             reviewer: "Logan P.", accentColor: Color(red: 0.44, green: 0.50, blue: 0.42)),
                second: .init(title: "Focus wins",
                              body: "\"Swapped out the red-dye bombs. Teacher noticed a difference within two weeks.\"",
                              reviewer: "Nick R.", accentColor: Color(red: 0.54, green: 0.40, blue: 0.28)))
        case .moreEnergy:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "boost energy levels in\nunder 12 weeks.",
                first: .init(title: "Even keel",
                             body: "\"Cleaner pantry, fewer crashes. Olive's picks actually get eaten.\"",
                             reviewer: "Grant W.", accentColor: Color(red: 0.44, green: 0.50, blue: 0.40)),
                second: .init(title: "Better fuel for the crew",
                              body: "\"We scan once, buy faster, and the energy swings are gone. Game changer.\"",
                              reviewer: "Peter L.", accentColor: Color(red: 0.56, green: 0.40, blue: 0.28)))
        case .happierSkin:
            return .init(heading: "We've helped\nthousands of families",
                subtitle: "achieve clearer skin in\nunder 12 weeks.",
                first: .init(title: "Less itch, more smiles",
                             body: "\"Scan, swap, done. Didn't think food was the issue—now I'm sold.\"",
                             reviewer: "Victor H.", accentColor: Color(red: 0.46, green: 0.50, blue: 0.40)),
                second: .init(title: "Skin wins",
                              body: "\"Olive made it effortless to dodge the triggers. Our kid's skin looks way better.\"",
                              reviewer: "Shawn E.", accentColor: Color(red: 0.54, green: 0.42, blue: 0.30)))
        case .healthierFamily:
            return .init(heading: "We've helped\nthousands of families",
                firstSubtitle: "live healthier and happier\nin under 12 weeks.",
                secondSubtitle: "live healthier in under\n12 weeks.",
                first: .init(title: "Provider mode: on",
                             body: "\"I want the safest picks for my kids. Olive makes that the default.\"",
                             reviewer: "Anthony V.", accentColor: Color(red: 0.44, green: 0.52, blue: 0.40)),
                second: .init(title: "Family-first upgrades",
                              body: "\"Scan → safe pick. I'm in and out faster and the house is eating cleaner across the board.\"",
                              reviewer: "David S.", accentColor: Color(red: 0.54, green: 0.42, blue: 0.30)))
        }
    }
}

// MARK: - Testimonial onboarding screen (steps 4 & 5)

private struct TestimonialOnboardingView: View {
    let review: LabelyOnboardingReview
    let secondReview: LabelyOnboardingReview?
    let heading: String
    let goalSubtitle: String
    let totalSegments: Int
    let filledSegments: Int
    let isLastTestimonial: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    private let horizontalPadding: CGFloat = labelyV2OnboardingHeaderSideInset

    var body: some View {
        GeometryReader { geo in
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                VStack(spacing: 0) {
                    testimonialHeaderRow()
                        .padding(.horizontal, horizontalPadding)

                    VStack(spacing: 12) {
                        Text(heading)
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundColor(labelyOnboardingTextGreen)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.88)

                        Text(goalSubtitle)
                            .font(.system(size: 20, weight: .medium, design: .default))
                            .foregroundColor(labelyChooseTeamSubtitleOlive)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 20)
                                .layoutPriority(0)
                            VStack(spacing: 14) {
                                reviewCard(review)
                                if let secondReview {
                                    reviewCard(secondReview)
                                }
                            }
                                .padding(.horizontal, horizontalPadding)
                            Spacer(minLength: 0)
                                .layoutPriority(2)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: onNext) {
                            Text(isLastTestimonial ? "Continue" : "Next")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    Capsule()
                                        .fill(labelyOnboardingPrimaryGreen)
                                )
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func testimonialHeaderRow() -> some View {
        HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GeometryReader { g in
                let spacing: CGFloat = 3
                let segW = (g.size.width - CGFloat(totalSegments - 1) * spacing) / CGFloat(totalSegments)
                HStack(spacing: spacing) {
                    ForEach(0..<totalSegments, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(i < filledSegments ? labelyOnboardingPrimaryGreen : Color.white.opacity(0.42))
                            .frame(width: segW, height: 5)
                    }
                }
            }
            .frame(height: 5)
        }
        .padding(.top, 8)
    }

    private func reviewCard(_ review: LabelyOnboardingReview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.0))
                }
            }
            .padding(.bottom, 12)

            Text(review.title)
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.10))
                .padding(.bottom, 8)

            Text(review.body)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(Color(red: 0.28, green: 0.28, blue: 0.28))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .padding(.bottom, 18)

            HStack(spacing: 10) {
                OnboardingReviewerAvatarView(
                    materialBasename: review.portraitBasename,
                    initial: review.initial,
                    accentColor: review.accentColor,
                    size: 36
                )

                Text(review.reviewer)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Mascot splash video (`onboarding-material/labely-mascot-jumping.mov`, or `.mp4`)

private final class MascotVideoHostView: UIView {
    var playerLayer: AVPlayerLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

private struct MascotJumpingIntroView: UIViewRepresentable {
    /// Invoked once when playback reaches the end (main thread). If the file is missing, called shortly after mount.
    let onPlaybackFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackFinished: onPlaybackFinished)
    }

    func makeUIView(context: Context) -> UIView {
        let host = MascotVideoHostView()
        host.backgroundColor = labelySplashScreenUIColor

        guard let url = Self.bundleURLForMascotJumpingVideo() else {
            DispatchQueue.main.async {
                context.coordinator.fireFinishedIfNeeded()
            }
            return host
        }

        let player = AVPlayer(url: url)
        player.isMuted = true

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = labelySplashScreenCGColor

        host.layer.addSublayer(layer)
        host.playerLayer = layer

        context.coordinator.player = player
        context.coordinator.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            context.coordinator.fireFinishedIfNeeded()
        }

        player.play()
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? MascotVideoHostView)?.playerLayer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let token = coordinator.endObserver {
            NotificationCenter.default.removeObserver(token)
            coordinator.endObserver = nil
        }
        coordinator.player?.pause()
        coordinator.player = nil
    }

    private static func bundleURLForMascotJumpingVideo() -> URL? {
        let name = "labely-mascot-jumping"
        for ext in ["mov", "mp4"] {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "onboarding-material")
                ?? Bundle.main.url(forResource: name, withExtension: ext) {
                return u
            }
        }
        return nil
    }

    final class Coordinator {
        private let onPlaybackFinished: () -> Void
        private var didFireFinished = false
        var player: AVPlayer?
        var endObserver: NSObjectProtocol?

        init(onPlaybackFinished: @escaping () -> Void) {
            self.onPlaybackFinished = onPlaybackFinished
        }

        func fireFinishedIfNeeded() {
            guard !didFireFinished else { return }
            didFireFinished = true
            onPlaybackFinished()
        }
    }
}

// MARK: - "How Labely helps you achieve lasting change" (step 6)

private struct InsideLabelyOnboardingView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    /// Figma `#2b472d`.
    private let insideLabelyBackground = Color(
        red: CGFloat(0x2b) / 255,
        green: CGFloat(0x47) / 255,
        blue: CGFloat(0x2d) / 255
    )

    @State private var imageOpacity: Double = 0
    @State private var isExiting = false

    var body: some View {
        ZStack {
            insideLabelyBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.white)
                            .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.horizontal, labelyV2OnboardingHeaderSideInset)
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("How Labely helps you\nachieve lasting change")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                            .padding(.horizontal, 24)

                        OnboardingMaterialImage.swiftUIImage(named: "inside-labely")
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .opacity(imageOpacity)

                        Text("Achieve your goals faster, naturally.")
                            .font(.system(size: 15, weight: .regular).italic())
                            .foregroundColor(.white.opacity(0.80))
                            .multilineTextAlignment(.center)
                            .padding(.top, 20)
                            .padding(.horizontal, 32)
                            .padding(.bottom, 32)
                            .opacity(imageOpacity)
                    }
                }

                Button(action: handleContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(insideLabelyBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(LabelyOnboardingPressableButtonStyle())
                .disabled(isExiting)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // Background renders immediately; image fades in after a short delay
            withAnimation(.easeIn(duration: 0.5).delay(0.25)) {
                imageOpacity = 1
            }
        }
    }

    private func handleContinue() {
        guard !isExiting else { return }
        isExiting = true
        withAnimation(.easeOut(duration: 0.35)) {
            imageOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onContinue()
        }
    }
}

// MARK: - "Have you used other scanning apps before?" (step 7)

private struct ScanningAppsQuestionOnboardingView: View {
    let onBack: () -> Void
    let onAnswer: () -> Void   // Both Yes and No advance forward

    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    var body: some View {
        GeometryReader { geo in
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                VStack(spacing: 0) {
                    scanningHeaderRow
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 8)

                    Text("Have you used other\nscanning apps before?")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)

                            VStack(spacing: 14) {
                                ScanningAppAnswerButton(emoji: "👎", label: "No", action: onAnswer)
                                ScanningAppAnswerButton(emoji: "👍", label: "Yes", action: onAnswer)
                            }
                            .padding(.horizontal, horizontalPadding)

                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
    }

    private var scanningHeaderRow: some View {
        HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GeometryReader { g in
                let spacing: CGFloat = 3
                let segW = (g.size.width - spacing) / 2
                HStack(spacing: spacing) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(labelyOnboardingPrimaryGreen)
                        .frame(width: segW, height: 5)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Color.white.opacity(0.42))
                        .frame(width: segW, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

private struct ScanningAppAnswerButton: View {
    let emoji: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.system(size: 22))
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(labelyOnboardingTextGreen)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(LabelyOnboardingPressableButtonStyle())
    }
}

// MARK: - "Labely goes above and beyond other apps" (step 8)

private struct OlivePledgeOnboardingView: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    /// Tab + shield tint on the white card (unchanged from prior launch-green pledge styling).
    private let pledgeAccentGreen = labelyOnboardingLaunchGreen
    private let horizontalPadding = labelyV2OnboardingHeaderSideInset

    @State private var showPledgeCard = false

    var body: some View {
        GeometryReader { geo in
            let bandMin = labelyHillsOnboardingCenteredScrollMinHeight(screenHeight: geo.size.height)
            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: labelyV2OnboardingHeaderSpacing) {
                        Button(action: onBack) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.white)
                                .frame(width: labelyV2OnboardingBackButtonSize, height: labelyV2OnboardingBackButtonSize)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)

                    Text("Labely goes above\nand beyond other apps")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(labelyOnboardingTextGreen)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 20)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            labelyPledgeCard
                                .padding(.horizontal, horizontalPadding)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: bandMin)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LabelyOnboardingHillsBottomChrome {
                        Button(action: onContinue) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Capsule().fill(labelyOnboardingPrimaryGreen))
                        }
                        .buttonStyle(LabelyOnboardingPressableButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            OnboardingHillsBackdropView()
                .ignoresSafeArea(edges: .all)
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.06)) {
                showPledgeCard = true
            }
        }
    }

    private var labelyPledgeCard: some View {
        let topEdgeOverlap: CGFloat = 22
        return ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                    .frame(height: topEdgeOverlap + 6)
                pledgeBodyText
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(labelyOnboardingTextGreen)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 6)
            )

            HStack(alignment: .center, spacing: 10) {
                Text("The Labely Pledge:")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(pledgeAccentGreen)
                    )

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 46, height: 46)
                        .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 2)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(pledgeAccentGreen)
                }
            }
            .padding(.horizontal, 20)
            .offset(y: -topEdgeOverlap)
        }
        .opacity(showPledgeCard ? 1 : 0)
        .offset(y: showPledgeCard ? 0 : 18)
        .scaleEffect(showPledgeCard ? 1 : 0.97)
    }

    private var pledgeBodyText: Text {
        Text("We will ")
            + Text("NEVER")
            .fontWeight(.bold)
            .italic()
            + Text(" take a single ")
            + Text("penny from ANY brand")
            .fontWeight(.bold)
            .italic()
            + Text(" to alter their score.")
    }
}
