//
//  LanguageManager.swift
//  Invoice
//
//  Labely’s UI is English-only. `AppLanguage` is retained for Open Food Facts API parameters — use `.english` for product search and lookups.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }
    var code: String { rawValue }
}
