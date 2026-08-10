//
//  BurnApp.swift
//

import SwiftData
import SwiftUI

@main
struct BurnApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: ReleasedThought.self)
    }
}
