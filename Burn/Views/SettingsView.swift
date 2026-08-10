//
//  SettingsView.swift
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage(Setting.soundEnabled) private var soundEnabled = true
    @AppStorage(Setting.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(Setting.keepsJournal) private var keepsJournal = true

    @State private var showsClearConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("The burn") {
                    Toggle("Sound", isOn: $soundEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                }

                Section {
                    Toggle("Keep a journal", isOn: $keepsJournal)
                } header: {
                    Text("Afterwards")
                } footer: {
                    Text("With this off, a burned thought is gone for good — nothing is written to disk.")
                }

                Section {
                    Button("Clear journal", role: .destructive) {
                        showsClearConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear the journal?",
                isPresented: $showsClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive, action: clearJournal)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every released thought will be deleted. This cannot be undone.")
            }
        }
    }

    private func clearJournal() {
        try? modelContext.delete(model: ReleasedThought.self)
        try? modelContext.save()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: ReleasedThought.self, inMemory: true)
}
