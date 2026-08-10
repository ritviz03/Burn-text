//
//  JournalView.swift
//

import SwiftData
import SwiftUI

/// What has already been let go.
struct JournalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ReleasedThought.releasedAt, order: .reverse)
    private var thoughts: [ReleasedThought]

    var body: some View {
        NavigationStack {
            Group {
                if thoughts.isEmpty {
                    ContentUnavailableView(
                        "Nothing released yet",
                        systemImage: "flame",
                        description: Text("Thoughts you burn will be listed here.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Released")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(thoughts) { thought in
                VStack(alignment: .leading, spacing: 6) {
                    Text(thought.text)
                    Text(thought.releasedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: delete)
        }
    }

    private func delete(at offsets: IndexSet) {
        // Resolve every object before deleting any of them: deleting from the
        // query the indices point into would invalidate the ones not yet used.
        for thought in offsets.map({ thoughts[$0] }) {
            modelContext.delete(thought)
        }
        try? modelContext.save()
    }
}

#Preview {
    JournalView()
        .modelContainer(for: ReleasedThought.self, inMemory: true)
}
