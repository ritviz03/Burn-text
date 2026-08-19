//
//  RootView.swift
//

import SwiftUI

/// Holds the one screen that matters, plus a door out to Settings.
struct RootView: View {
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ComposeView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                // Let the page's own gradient run all the way up.
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .tint(.orange)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) { SettingsView() }
    }
}
