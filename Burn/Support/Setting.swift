//
//  Setting.swift
//

import Foundation

/// `UserDefaults` keys for the handful of switches the app exposes.
///
/// Centralised so a typo in one view cannot silently create a second, unrelated
/// preference. Defaults live at each `@AppStorage` declaration.
enum Setting {
    static let soundEnabled = "settings.soundEnabled"
    static let hapticsEnabled = "settings.hapticsEnabled"
    static let keepsJournal = "settings.keepsJournal"
}
