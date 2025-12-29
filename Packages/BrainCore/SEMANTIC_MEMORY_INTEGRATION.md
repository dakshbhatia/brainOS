# Semantic Memory System - Integration Guide

## ✅ Implementation Complete

All semantic memory components have been successfully integrated into BrainCore:

### New Files Created

1. **Models** (Enhanced):
   - `ChatTurnData.swift` - Added: `qualityScore`, `embedding`, `parentMessageId`, `chunkIndex`, `tokenCount`
   - `ChatTurn.swift` - Added same memory properties

2. **Services**:
   - `EmbeddingService.swift` - OpenAI embedding generation with batch support
   - `ContextBuilder.swift` - Smart context window management
   - `MemoryStorage.swift` - Extended storage for tool memories and cross-session search
   - `SemanticMemoryCoordinator.swift` - High-level API for all memory features

3. **Managers**:
   - `MemoryManager.swift` - Core semantic search and quality assessment

---

## 🚀 Quick Start Integration

### Step 1: Initialize in AppDelegate or Main View

```swift
import BrainCore

class AppState: ObservableObject {
    let memoryCoordinator: SemanticMemoryCoordinator
    
    init() {
        // Get OpenAI key from your existing configuration
        let openAIKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey") ?? ""
        self.memoryCoordinator = SemanticMemoryCoordinator(openAIKey: openAIKey)
    }
}
```

### Step 2: Process New Messages (In ChatView or Message Handler)

```swift
// After a user or assistant message is added to session:
func handleNewMessage(_ turn: ChatTurn, sessionId: UUID) async {
    let turnData = await ChatTurnData(from: turn)
    
    // Process in background - generates embedding and quality score
    Task {
        await memoryCoordinator.processNewMessage(turnData, inSession: sessionId)
    }
}
```

### Step 3: Use Smart Context (Before API Calls)

```swift
// BEFORE sending to ChatEngine, build smart context:
func sendMessage(_ query: String, sessionId: UUID) async throws {
    // Get optimized context with semantic memory
    let smartContext = try await memoryCoordinator.buildSmartContext(
        query: query,
        sessionId: sessionId,
        strategy: .balanced  // or .recentHeavy / .semanticHeavy
    )
    
    // Convert to API format
    let messages = smartContext.map { turn in
        ChatMessage(
            role: turn.role.rawValue,
            content: turn.content
        )
    }
    
    // Send to engine as usual
    let request = ChatCompletionRequest(messages: messages, ...)
    let stream = try await chatEngine.streamChat(request: request)
    // ... handle stream
}
```

---

## 🎯 Key Features & Usage

### 1. Semantic Search Across All Sessions

```swift
// Find similar conversations from entire history
let results = try await memoryCoordinator.searchMemory(
    query: "How do I set up authentication?",
    limit: 5
)

for (message, similarity) in results {
    print("[\(similarity * 100)%] \(message.content)")
}
```

### 2. Tool Usage Learning

```swift
// Remember when tools are used
await memoryCoordinator.rememberToolUse(
    toolName: "BrainCalendar",
    query: "What meetings do I have tomorrow?",
    success: true
)

// Get intelligent suggestions for new queries
let suggestions = try await memoryCoordinator.suggestTools(
    for: "Show my schedule",
    limit: 3
)
// Returns: [("BrainCalendar", 0.92), ...]
```

### 3. Quality-Based Retrieval

```swift
// Get high-value messages from current session
let qualityMessages = memoryCoordinator.getQualityMessages(
    sessionId: currentSessionId,
    minQuality: 0.7
)

// Get session statistics
if let stats = memoryCoordinator.getSessionStats(sessionId: currentSessionId) {
    print("Embedded: \(stats.embeddedMessages)/\(stats.totalMessages)")
    print("Average Quality: \(stats.averageQuality)")
    print("Progress: \(Int(stats.embeddingProgress * 100))%")
}
```

### 4. Backfill Historical Sessions

```swift
// Run once to process all existing sessions
func backfillSemanticMemory() async {
    let sessions = ChatSessionStore.loadAll()
    
    for session in sessions {
        print("Processing session: \(session.title)")
        await memoryCoordinator.processSessionEmbeddings(sessionId: session.id)
    }
    
    print("✅ All sessions processed!")
}
```

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│          SemanticMemoryCoordinator                  │
│  (High-level API - Use this in your code)          │
└──────────────┬──────────────────────────────────────┘
               │
       ┌───────┴───────┬─────────────┬─────────────┐
       │               │             │             │
┌──────▼─────┐ ┌──────▼──────┐ ┌───▼────────┐ ┌──▼────────┐
│ Embedding  │ │   Memory    │ │  Context   │ │  Memory   │
│  Service   │ │   Manager   │ │  Builder   │ │  Storage  │
└────────────┘ └─────────────┘ └────────────┘ └───────────┘
     │              │                │              │
     │              │                │              │
     └──────────────┴────────────────┴──────────────┘
                         │
                ┌────────▼────────┐
                │  ChatTurnData   │
                │  (Enhanced)     │
                └─────────────────┘
```

---

## 📊 Enhanced Message Properties

Every `ChatTurnData` now includes:

| Property | Type | Purpose |
|----------|------|---------|
| `qualityScore` | `Double?` | 0.0-1.0 score indicating message value for recall |
| `embedding` | `[Float]?` | 1536-dim vector for semantic search |
| `parentMessageId` | `UUID?` | Parent-child chunking support |
| `chunkIndex` | `Int?` | Chunk position in splitting strategy |
| `tokenCount` | `Int?` | Pre-calculated for context budget |

---

## 🎨 Context Strategies

Choose the right strategy for your use case:

### `.recentHeavy` (15 recent + 2 semantic)
- Best for: Ongoing conversations, follow-up questions
- Use when: User is in active back-and-forth dialogue

### `.balanced` (10 recent + 5 semantic) ⭐ DEFAULT
- Best for: Mixed use cases, general chat
- Use when: You're not sure - good all-arounder

### `.semanticHeavy` (5 recent + 8 semantic)
- Best for: Research queries, knowledge retrieval
- Use when: User asks "Remember when we talked about X?"

---

## 🔧 Configuration Options

### Customize Embedding Service

```swift
let embeddingService = EmbeddingService(
    apiKey: "your-key",
    model: "text-embedding-3-small",  // or text-embedding-3-large
    baseURL: "https://api.openai.com/v1"
)
```

### Customize Context Builder

```swift
let contextBuilder = ContextBuilder(
    memoryManager: memoryManager,
    maxTokens: 8000  // Adjust based on your model's context window
)
```

### Quality Assessment Tuning

Edit `MemoryManager.assessQuality()` to customize scoring:
- Length factors
- Tool usage bonus
- Code block detection
- Custom heuristics

---

## 🧪 Testing Your Integration

### 1. Test Embedding Generation

```swift
let coordinator = SemanticMemoryCoordinator(openAIKey: "sk-...")

// Create test message
let testMessage = ChatTurnData(
    role: .user,
    content: "How do I reset my password?"
)

// Process it
await coordinator.processNewMessage(testMessage, inSession: testSessionId)

// Verify embedding was created
if let session = ChatSessionStore.load(id: testSessionId),
   let turn = session.turns.first(where: { $0.id == testMessage.id }) {
    print("Embedding dimensions: \(turn.embedding?.count ?? 0)")  // Should be 1536
    print("Quality score: \(turn.qualityScore ?? 0.0)")
}
```

### 2. Test Semantic Search

```swift
// Add multiple messages with embeddings
// ... then search:

let results = try await coordinator.searchSession(
    query: "authentication problems",
    sessionId: testSessionId,
    limit: 3
)

for (message, score) in results {
    print("[\(score)] \(message.content.prefix(50))...")
}
```

### 3. Test Smart Context

```swift
let context = try await coordinator.buildSmartContext(
    query: "What was that API endpoint again?",
    sessionId: testSessionId,
    strategy: .semanticHeavy
)

print("Context size: \(context.count) messages")
```

---

## 🚨 Important Notes

1. **API Costs**: Embeddings cost tokens! `text-embedding-3-small` is ~$0.02 per 1M tokens
   - Process messages asynchronously/in background
   - Consider batching for efficiency

2. **Storage Growth**: Embeddings add ~6KB per message (1536 floats)
   - 1000 messages ≈ 6MB additional storage
   - JSON compression helps significantly

3. **First-Time Processing**: Backfilling existing sessions takes time
   - Run during onboarding or idle time
   - Show progress UI to user

4. **Quality Scores**: Heuristic-based, tune for your use case
   - Adjust thresholds in `MemoryManager.assessQuality()`
   - Consider user feedback for learning

5. **Context Window**: Default 8000 tokens is conservative
   - Increase for larger models (GPT-4: 128K)
   - Monitor actual usage vs limits

---

## 📈 Performance Tips

1. **Batch Embeddings**: Use `embedBatch()` when processing multiple messages
2. **Lazy Loading**: Only load embeddings when needed for search
3. **Cache Frequently Used**: Keep recent session data in memory
4. **Background Processing**: Use `Task.detached` for non-blocking updates
5. **Incremental Updates**: Process new messages immediately, backfill later

---

## 🎉 What You Get

✅ **Semantic Memory**: Find similar conversations automatically
✅ **Smart Context**: Optimal message selection for API calls  
✅ **Tool Learning**: Remember what works, suggest intelligently
✅ **Quality Assessment**: Identify valuable messages for recall
✅ **Zero Dependencies**: Uses existing OpenAI API access
✅ **Backward Compatible**: Existing sessions work without embeddings
✅ **Cross-Session Search**: Find information across entire history
✅ **Token Budget Management**: Pre-calculated for efficient context building

---

## 🔗 Next Steps

1. Add `SemanticMemoryCoordinator` to your app state
2. Hook `processNewMessage()` into your chat flow
3. Replace message history with `buildSmartContext()` for API calls
4. Run backfill script for existing sessions
5. Monitor quality scores and tune thresholds
6. Experiment with context strategies for your use cases

**You now have a production-ready semantic memory system!** 🚀
