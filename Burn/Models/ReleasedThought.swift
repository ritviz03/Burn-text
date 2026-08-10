//
//  ReleasedThought.swift
//

import Foundation
import SwiftData

/// A thought that has been burned.
///
/// Stored on device only — there is no account, no sync and no network call
/// anywhere in this app. Saving is opt-out via `Setting.keepsJournal`.
@Model
final class ReleasedThought {
    var text: String
    var releasedAt: Date

    init(text: String, releasedAt: Date = .now) {
        self.text = text
        self.releasedAt = releasedAt
    }
}
