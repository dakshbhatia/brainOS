//
//  SemanticMemorySettingsView.swift
//  BrainOS
//
//  Settings UI for semantic memory configuration and backfill
//

import SwiftUI

struct SemanticMemorySettingsView: View {
    @StateObject private var embeddingService = AutoEmbeddingService.shared
    @State private var isBackfilling = false
    @State private var backfillProgress: String = ""
    @State private var stats: AutoEmbeddingService.Stats?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(embeddingService.isConfigured ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(embeddingService.isConfigured ? "Semantic memory active" : "Not configured (needs OpenAI provider)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // Statistics
            if let stats = stats {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Messages indexed: \(stats.embeddedMessages) / \(stats.totalMessages)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if stats.totalMessages > 0 {
                        ProgressView(value: stats.embeddingProgress)
                            .progressViewStyle(.linear)
                            .frame(height: 4)
                    }
                }
            }
            
            // Backfill button
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await runBackfill()
                    }
                }) {
                    HStack(spacing: 6) {
                        if isBackfilling {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                        }
                        Text(isBackfilling ? "Indexing..." : "Index All Conversations")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isBackfilling || !embeddingService.isConfigured)
                
                if !backfillProgress.isEmpty {
                    Text(backfillProgress)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Help text
            Text("Semantic memory enables AI to recall relevant past conversations and suggest tools based on context.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            refreshStats()
        }
    }
    
    private func refreshStats() {
        Task { @MainActor in
            stats = embeddingService.getStats()
        }
    }
    
    private func runBackfill() async {
        isBackfilling = true
        backfillProgress = "Starting..."
        
        await AutoEmbeddingService.shared.backfillAllSessions()
        
        backfillProgress = "Complete!"
        isBackfilling = false
        refreshStats()
        
        // Clear message after 3 seconds
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        backfillProgress = ""
    }
}

#Preview {
    SemanticMemorySettingsView()
        .padding()
        .frame(width: 400)
}
