//
//  RootView.swift
//

import SwiftUI

/// Holds the one screen that matters, plus two doors out of it.
struct RootView: View {
    @State private var showsJournal = false
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ComposeView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsJournal = true
                        } label: {
                            Image(systemName: "book.closed")
                        }
                        .accessibilityLabel("Released thoughts")
                    }
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
        .sheet(isPresented: $showsJournal) { JournalView() }
        .sheet(isPresented: $showsSettings) { SettingsView() }
    }
}
