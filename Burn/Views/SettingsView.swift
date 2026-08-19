//
//  SettingsView.swift
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Setting.soundEnabled) private var soundEnabled = true
    @AppStorage(Setting.hapticsEnabled) private var hapticsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("The burn") {
                    Toggle("Sound", isOn: $soundEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
