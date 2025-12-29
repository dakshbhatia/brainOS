import SwiftUI

public struct RelationshipDashboardView: View {
    @State private var selectedId: String?
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            RelationshipListView(selectedId: $selectedId)
                .navigationTitle("Connections")
                .frame(minWidth: 250)
        } detail: {
            if let id = selectedId {
                RelationshipDetailView(profileId: id)
                    .id(id) // Ensure view refreshes on selection change
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue.gradient.opacity(0.3))
                    
                    Text("Your Social Web")
                        .font(.title2.weight(.bold))
                    
                    Text("Select a contact to view your shared history and relationship health.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.02))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { dismiss() }) {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
    }
}
