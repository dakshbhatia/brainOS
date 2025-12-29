import SwiftUI

public struct RelationshipListView: View {
    @Binding var selectedId: String?
    @State private var searchText = ""
    @State private var profiles: [RelationshipProfile] = []
    @State private var isLoading = false
    
    public init(selectedId: Binding<String?>) {
        self._selectedId = selectedId
    }
    
    var filteredProfiles: [RelationshipProfile] {
        if searchText.isEmpty {
            return profiles
        } else {
            return profiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search contacts...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(12)
            
            // List
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if profiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No contacts found")
                        .font(.headline)
                    Text("Interactions from iMessage will appear here automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredProfiles, selection: $selectedId) { profile in
                    RelationshipRow(profile: profile)
                        .tag(profile.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            loadProfiles()
        }
    }
    
    private func loadProfiles() {
        isLoading = true
        Task {
            // Rebuild profiles to ensure they are fresh
            _ = await RelationshipAgent.shared.buildRelationshipProfiles()
            let all = await BrainDatabaseManager.shared.getAllRelationshipProfiles()
            
            await MainActor.run {
                self.profiles = all.sorted { $0.relationshipScore > $1.relationshipScore }
                self.isLoading = false
            }
        }
    }
}

struct RelationshipRow: View {
    let profile: RelationshipProfile
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar Placeholder
            ZStack {
                Circle()
                    .fill(Color.blue.gradient.opacity(0.2))
                    .frame(width: 40, height: 40)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(profile.name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(profile.trajectory.emoji)
                        .font(.caption2)
                }
                
                HStack {
                    Text(profile.tier.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(profile.relationshipScore))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(scoreColor)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }
    
    private var scoreColor: Color {
        if profile.relationshipScore > 70 { return .green }
        if profile.relationshipScore > 40 { return .blue }
        return .orange
    }
}
