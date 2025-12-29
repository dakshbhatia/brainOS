import SwiftUI

/// Interactive knowledge graph visualization showing entities and relationships
struct BrainKnowledgeGraphView: View {
    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []
    @State private var isLoading = true
    @State private var selectedNode: GraphNode? = nil
    @State private var searchQuery = ""
    @State private var hoveredNode: GraphNode? = nil
    @Environment(\.theme) private var theme
    
    // Layout state
    @State private var nodePositions: [UUID: CGPoint] = [:]
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(NSColor.controlBackgroundColor)
                
                if isLoading {
                    ProgressView("Building knowledge graph...")
                } else if nodes.isEmpty {
                    emptyState
                } else {
                    // Graph canvas
                    graphCanvas(size: geometry.size)
                }
                
                // Header overlay
                VStack {
                    headerSection
                    Spacer()
                    if let selected = selectedNode {
                        nodeDetailPanel(selected)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadGraphData()
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack {
            Text("Knowledge Graph")
                .font(.system(size: 16, weight: .semibold))
            
            Spacer()
            
            TextField("Search entities...", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            
            Button(action: loadGraphData) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No knowledge graph data yet")
                .font(.headline)
            Text("Interact with BrainOS to build your knowledge graph")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Graph Canvas
    private func graphCanvas(size: CGSize) -> some View {
        ZStack {
            // Draw edges first (behind nodes)
            ForEach(edges) { edge in
                if let source = nodePositions[edge.sourceId],
                   let target = nodePositions[edge.targetId] {
                    EdgeLine(
                        from: source,
                        to: target,
                        strength: edge.strength,
                        label: edge.relationType
                    )
                }
            }
            
            // Draw nodes
            ForEach(filteredNodes) { node in
                if let position = nodePositions[node.id] {
                    NodeView(
                        node: node,
                        isSelected: selectedNode?.id == node.id,
                        isHovered: hoveredNode?.id == node.id
                    )
                    .position(position)
                    .onTapGesture {
                        selectedNode = node
                    }
                    .onHover { hovering in
                        hoveredNode = hovering ? node : nil
                    }
                }
            }
        }
        .scaleEffect(scale)
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
        )
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = value
                }
        )
        .onAppear {
            initializeLayout(size: size)
        }
    }
    
    // MARK: - Node Detail Panel
    private func nodeDetailPanel(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: node.type.icon)
                    .foregroundStyle(node.type.color)
                Text(node.name)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { selectedNode = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            Text("Type: \(node.type.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let lastSeen = node.lastSeen {
                Text("Last seen: \(lastSeen, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text("Connections: \(connectionCount(for: node))")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !connectedNodes(to: node).isEmpty {
                Divider()
                Text("Connected to:")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(connectedNodes(to: node).prefix(5), id: \.id) { connected in
                            Button(action: { selectedNode = connected }) {
                                HStack {
                                    Image(systemName: connected.type.icon)
                                        .font(.caption2)
                                        .foregroundStyle(connected.type.color)
                                    Text(connected.name)
                                        .font(.caption)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 100)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(radius: 5)
        )
        .frame(width: 250)
        .padding()
    }
    
    // MARK: - Data Loading
    private var filteredNodes: [GraphNode] {
        if searchQuery.isEmpty {
            return nodes
        }
        return nodes.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }
    
    private func connectionCount(for node: GraphNode) -> Int {
        edges.filter { $0.sourceId == node.id || $0.targetId == node.id }.count
    }
    
    private func connectedNodes(to node: GraphNode) -> [GraphNode] {
        let connectedIds = edges
            .filter { $0.sourceId == node.id || $0.targetId == node.id }
            .flatMap { [$0.sourceId, $0.targetId] }
            .filter { $0 != node.id }
        
        return nodes.filter { connectedIds.contains($0.id) }
    }
    
    private func initializeLayout(size: CGSize) {
        // Simple force-directed layout initialization
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = 200
        
        for (index, node) in nodes.enumerated() {
            let angle = (CGFloat(index) / CGFloat(nodes.count)) * 2 * .pi
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            nodePositions[node.id] = CGPoint(x: x, y: y)
        }
    }
    
    private func loadGraphData() {
        isLoading = true
        
        Task {
            // Load entities and relationships from database
            let entities = await BrainDatabaseManager.shared.getAllEntities()
            let relationships = await BrainDatabaseManager.shared.getAllRelationships()
            
            await MainActor.run {
                // Convert to graph nodes
                self.nodes = entities.map { entity in
                    GraphNode(
                        name: entity.name,
                        type: EntityType(rawValue: entity.type) ?? .other,
                        lastSeen: entity.lastSeen
                    )
                }
                
                // Convert to graph edges
                self.edges = relationships.map { rel in
                    GraphEdge(
                        sourceId: nodes.first { $0.name == rel.sourceName }?.id ?? UUID(),
                        targetId: nodes.first { $0.name == rel.targetName }?.id ?? UUID(),
                        relationType: rel.type,
                        strength: Float(rel.strength)
                    )
                }
                
                self.isLoading = false
            }
        }
    }
}

// MARK: - Graph Components

struct NodeView: View {
    let node: GraphNode
    let isSelected: Bool
    let isHovered: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(node.type.color.opacity(isSelected || isHovered ? 1.0 : 0.7))
                .frame(width: isSelected ? 50 : 40, height: isSelected ? 50 : 40)
                .overlay(
                    Image(systemName: node.type.icon)
                        .font(.system(size: isSelected ? 16 : 12))
                        .foregroundStyle(.white)
                )
                .shadow(radius: isSelected || isHovered ? 5 : 2)
            
            Text(node.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 80)
        }
        .animation(.spring(response: 0.3), value: isSelected)
        .animation(.spring(response: 0.3), value: isHovered)
    }
}

struct EdgeLine: View {
    let from: CGPoint
    let to: CGPoint
    let strength: Float
    let label: String
    
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .stroke(
                Color.gray.opacity(Double(strength)),
                style: StrokeStyle(lineWidth: CGFloat(strength) * 2, lineCap: .round)
            )
            
            // Label at midpoint
            if !label.isEmpty {
                Text(label)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .cornerRadius(4)
                    .position(
                        x: (from.x + to.x) / 2,
                        y: (from.y + to.y) / 2
                    )
            }
        }
    }
}

// MARK: - Data Models

struct GraphNode: Identifiable {
    let id = UUID()
    let name: String
    let type: EntityType
    let lastSeen: Date?
}

struct GraphEdge: Identifiable {
    let id = UUID()
    let sourceId: UUID
    let targetId: UUID
    let relationType: String
    let strength: Float
}

enum EntityType: String, CaseIterable {
    case person, place, organization, event, other
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .person: return "person.fill"
        case .place: return "mappin.circle.fill"
        case .organization: return "building.2.fill"
        case .event: return "calendar.badge.clock"
        case .other: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .person: return .blue
        case .place: return .green
        case .organization: return .purple
        case .event: return .orange
        case .other: return .gray
        }
    }
}

#Preview {
    BrainKnowledgeGraphView()
}
