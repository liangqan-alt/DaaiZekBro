//
//  ContentView.swift
//  DaaiZekBro
//
//  Created by liangqan on 2026/5/20.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \Template.name) private var templates: [Template]
    @State private var seedStatus: SeedStatus = .loading

    var body: some View {
        NavigationViewWrapper {
            List {
                Section("Seed Data") {
                    LabeledContent("Status", value: seedStatus.message)
                    LabeledContent("Exercises", value: "\(exercises.count)")
                    LabeledContent("Templates", value: "\(templates.count)")
                }

                Section("Templates") {
                    ForEach(templates) { template in
                        LabeledContent(template.name, value: "\(template.exercises.count) exercises")
                    }
                }
            }
            .navigationTitle("PR-01 Seed Check")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .task {
                await writeSeedData()
            }
        }
    }

    @MainActor
    private func writeSeedData() async {
        do {
            try SeedData.writeAndDedup(in: modelContext)
            seedStatus = .ready
        } catch {
            seedStatus = .failed(error.localizedDescription)
        }
    }
}

private enum SeedStatus: Equatable {
    case loading
    case ready
    case failed(String)

    var message: String {
        switch self {
        case .loading:
            "Writing seed data..."
        case .ready:
            "Ready"
        case .failed(let errorMessage):
            "Failed: \(errorMessage)"
        }
    }
}

fileprivate struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            Text("Select a template")
        }
#else
        NavigationStack {
            content()
        }
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Exercise.self, Template.self, WorkoutSession.self, WorkoutSet.self],
            inMemory: true
        )
}
