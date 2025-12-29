# Brain Intelligence System Guide

**The proactive AI layer that transforms BrainOS from an LLM server into your digital brain.**

---

## Overview

While BrainOS serves as a local LLM server with OpenAI/MCP compatibility, it also includes an experimental **Brain Intelligence System** that monitors your life data, builds semantic memories, and proactively generates insights before you ask.

**Core Concept:** Instead of waiting for you to query information, BrainOS continuously learns from your Mac's data sources (messages, calendar, health, browsing) and surfaces relevant insights automatically.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Data Sources (Life)                      │
├────────────┬────────────┬──────────┬──────────┬─────────────┤
│  Messages  │  Calendar  │  Health  │  Safari  │  Location   │
└─────┬──────┴─────┬──────┴────┬─────┴────┬─────┴──────┬──────┘
      │            │           │          │            │
      v            v           v          v            v
┌─────────────────────────────────────────────────────────────┐
│       Background Ingestion (Every 30 Minutes)               │
│         Collects DataItems from all sources                 │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            v
┌─────────────────────────────────────────────────────────────┐
│     Parallel AI Memory Pipeline (3 Concurrent Workers)      │
│  - Generates summaries, entities, sentiment                 │
│  - Assigns importance scores (1-10)                         │
│  - Creates embeddings for semantic search                   │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            v
┌─────────────────────────────────────────────────────────────┐
│              Knowledge Base (Semantic Memory)               │
│  - Vector embeddings (Apple NLEmbedding)                    │
│  - Entity graph (SQLite)                                    │
│  - Structured memories with metadata                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            v
┌─────────────────────────────────────────────────────────────┐
│           Proactive Intelligence (Hourly Loop)              │
│  - Relationship analysis → Nudge notifications              │
│  - Health monitoring → Activity alerts                      │
│  - AI reflection → Insight notifications                    │
│  - Daily brief generation (7 AM)                            │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            v
┌─────────────────────────────────────────────────────────────┐
│                    User Interfaces                          │
│  - Brain Dashboard (Memory Stream, Brief, Nudges)           │
│  - Notifications (Relationship, Health, Insight)            │
│  - RAG-Enhanced Chat (Automatic Context Injection)          │
└─────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Background Ingestion Service

**File:** `Services/BackgroundIngestionService.swift`

**Purpose:** Periodically collects raw data from various macOS sources.

**How it works:**
1. Runs every 30 minutes (started in `BrainManager.start()`)
2. Gathers data from:
   - Messages (last 50 messages via `BrainMessagesManager`)
   - Safari history (last 20 pages via `BrainSafariManager`)
   - App usage (last 10 events via `BrainUsageManager`)
3. Converts raw data into `DataItem` objects
4. Sends batch to `MemoryGenerationPipeline` for AI processing

**Configuration:**
- Interval: 30 minutes (hardcoded in `ingestAll()`)
- Message limit: 50
- Safari limit: 20
- Usage limit: 10

**Status:** ✅ Fully implemented and running automatically on app launch.

---

### 2. Memory Generation Pipeline

**File:** `Services/MemoryGenerationPipeline.swift`

**Purpose:** Parallel AI processing of raw data into structured memories.

**How it works:**
1. Receives batch of `DataItem` objects
2. Processes 3 items concurrently using `TaskGroup`
3. For each item:
   - Builds specialized prompt based on data type
   - Calls MLX model for analysis (256 tokens, temp 0.7)
   - Parses response for: summary, entities, sentiment, importance
4. Stores generated memories in `BrainKnowledgeManager`

**Data Types Supported:**
- `.message` - Chat messages with sender and text
- `.calendarEvent` - Events with title, dates, location
- `.healthData` - Steps, sleep, activity metrics
- `.safariPage` - Browsing history with URL and title
- `.usageEvent` - App usage with duration
- `.location` - GPS coordinates with place name

**Output Format:**
```swift
GeneratedMemory(
    id: UUID(),
    text: "Original data",
    summary: "AI-generated summary",
    entities: ["Person", "Place", "Organization"],
    sentiment: "positive|neutral|negative",
    importance: 7, // 1-10 scale
    timestamp: Date(),
    sourceType: "message"
)
```

**Performance:**
- Concurrent workers: 3 (configurable via `maxConcurrentInferences`)
- Average latency: ~2-3s per memory
- Batch size: Unlimited (processes all items in batch)

**Status:** ✅ Fully implemented and processing data every 30 minutes.

---

### 3. Real-Time Event Stream (Beta)

**File:** `Services/RealTimeEventStream.swift`

**Purpose:** Actor-based event buffering for real-time data ingestion.

**How it works:**
1. Managers emit events via `RealTimeEventStream.shared.emit()`
2. Events buffered in actor-isolated array
3. Auto-flushes when:
   - Buffer reaches 10 events, OR
   - 30 seconds elapsed since last flush
4. Converts events to `DataItem` objects
5. Sends to `MemoryGenerationPipeline`

**Event Types:**
```swift
enum BrainEvent {
    case messageReceived(sender: String, text: String, timestamp: Date)
    case calendarEventStarting(title: String, startDate: Date, location: String?)
    case healthDataUpdated(type: String, value: Double, unit: String)
    case locationChanged(latitude: Double, longitude: Double, placeName: String?)
    case appUsageDetected(appName: String, startTime: Date)
    case safariPageVisited(url: String, title: String)
    case screenshotCaptured(path: String, timestamp: Date)
    case contactsChanged(changeType: String, contactName: String)
}
```

**Usage Example:**
```swift
// In BrainMessagesManager
await RealTimeEventStream.shared.emit(
    .messageReceived(sender: "Alice", text: "Hey!", timestamp: Date())
)
```

**Status:** ⚠️ Built but not integrated. Managers need to call `emit()` on data changes.

---

### 4. Semantic Memory & RAG

**Files:** 
- `Managers/BrainKnowledgeManager.swift` - Storage and retrieval
- `Services/ChatEngine.swift` - RAG integration

**Purpose:** Enable chat to automatically retrieve relevant context from past events.

**How it works:**

1. **Storage** (in `BrainKnowledgeManager.addMemory()`):
   ```swift
   let text = "Had lunch with Alice at cafe"
   let embedding = NLEmbedding.sentenceEmbedding(for: .english)
       .vector(for: text)
   // Store in SQLite: text + embedding blob
   ```

2. **Retrieval** (in `ChatEngine.injectRelevantMemories()`):
   ```swift
   // Extract query from last 3 user messages
   let query = "What did I do with Alice?"
   
   // Semantic search
   let memories = await BrainKnowledgeManager.shared.search(
       query: query, 
       limit: 5
   )
   // Returns: ["Had lunch with Alice at cafe", ...]
   
   // Inject into system prompt
   systemPrompt += """
   # RELEVANT CONTEXT FROM YOUR MEMORY
   1. Had lunch with Alice at cafe
   2. Alice mentioned new project deadline
   ...
   """
   ```

3. **Chat Response** uses context naturally:
   ```
   User: "What did I do with Alice?"
   AI: "You had lunch with Alice at a cafe, and she mentioned 
        a new project deadline."
   ```

**Search Method:**
- Apple NLEmbedding (local, private)
- Cosine similarity between query and stored embeddings
- Top 5 results by default

**Status:** ✅ Fully implemented. Every chat message automatically searches memory.

---

### 5. Brain Dashboard

**File:** `Views/BrainDashboardView.swift`

**Purpose:** Central hub for viewing memory stream, insights, and life context.

**Sections:**

1. **Header**
   - Brain avatar with pulse animation
   - User greeting (time-aware)
   - Learning status indicator (green/orange)

2. **Memory Stream Status**
   - Shows if background ingestion is active
   - Last ingestion timestamp
   - Memory count

3. **Daily Brief**
   - AI-generated 2-3 sentence summary
   - Includes: health, calendar, relationships, recent memories
   - Expandable for full content

4. **Recent Insights**
   - Top 3 high-importance memories from last 24 hours
   - Sorted by importance score

5. **Relationships Inbox**
   - Pending relationship nudges
   - Shows contact name, reason, suggested action
   - Priority indicators (high/medium/low)

6. **Context Cards**
   - Health: Step count, activity level
   - Location: Current place
   - Calendar: Upcoming events

**Refresh:**
- Auto-refreshes every 5 minutes
- Manual refresh via search button

**Status:** ✅ Fully implemented. Access via menu bar popover.

---

### 6. Relationship Agent

**File:** `Managers/RelationshipAgent.swift`

**Purpose:** Analyze conversation patterns and generate actionable relationship nudges.

**Analysis Process:**

1. **Fetch Recent Messages** (last 100 from past 30 days)
   ```swift
   let messages = try await BrainMessagesManager.shared
       .fetchRecentMessages(limit: 100)
   ```

2. **Group by Contact** and calculate:
   - Days since last interaction
   - Conversation direction (who messaged last)
   - Unanswered message count

3. **Detect Stale Contacts** (>7 days quiet)
   ```swift
   let staleContacts = await BrainDatabaseManager.shared
       .getStaleContacts(daysSince: 7)
   ```

4. **AI Analysis** via MLX model:
   - Input: Conversation summaries + stale contacts
   - Output: JSON array of nudges
   ```json
   [
     {
       "contactName": "Mom",
       "reason": "She asked about dinner 2 days ago and you haven't replied",
       "suggestion": "Reply: 'Sorry for delay! Dinner Sunday sounds great'",
       "priority": "high",
       "actionType": "reply"
     }
   ]
   ```

5. **Fallback Heuristics** if AI fails:
   - Prioritize contacts quiet >7 days
   - Generic suggestions like "Check in with X"

**Output:**
```swift
struct RelationshipNudge {
    let contactName: String
    let reason: String
    let suggestion: String?
    let priority: NudgePriority // high/medium/low
    let actionType: String? // reply/call/meetup
    let daysSinceContact: Int
}
```

**Status:** ✅ Fully implemented. Runs on dashboard load and hourly check.

---

### 7. Daily Brief Generation

**File:** `Managers/BrainManager.swift` (`generateBrief()`)

**Purpose:** AI-powered morning summary synthesizing all life context.

**Data Sources:**
1. User profile (name)
2. Current time and greeting
3. Health data (step count)
4. Relationship nudges (top 3)
5. Calendar events
6. Recent semantic memories (important events)

**AI Prompt Structure:**
```
System: You are BrainOS's briefing assistant. Generate a warm, 
        personal, actionable daily brief. 2-3 sentences max.

User: Generate a morning brief for Daksh:
      Current Time: Dec 28, 2025 8:00 AM
      Health: 0 steps today (just woke up)
      Relationships: Mom asked about dinner 2 days ago
      Calendar: Team standup at 4 PM
      Recent Context: Researching Swift actors, Project deadline Friday
```

**Example Output:**
> "Good morning, Daksh! You've got the team standup at 4 PM today. Don't forget to reply to Mom about dinner—she asked 2 days ago. With the project deadline Friday, consider blocking focus time for Swift actors work."

**Fallback** (if AI fails):
- Basic template with data substitution
- Example: "Good morning! You have 3 meetings today. Don't forget to reach out to Mom."

**Caching:**
- Generated at 7 AM via `performProactiveCheck()`
- Cached in UserDefaults
- Delivered as notification at 8 AM

**Status:** ✅ Fully implemented. Scheduled daily at 8 AM.

---

### 8. Proactive Notifications

**File:** `Services/NotificationService.swift`

**Purpose:** Multi-category notification system with contextual actions.

**Categories:**

1. **BRAINOS_RELATIONSHIP**
   - For social obligations and connection nudges
   - Actions: [Reply] [Call]
   - Critical sound for high-priority

2. **BRAINOS_HEALTH**
   - Activity and wellbeing alerts
   - Action: [Dismiss]
   - Default sound

3. **BRAINOS_INSIGHT**
   - AI-generated daily insights
   - Action: [Dismiss]
   - Default sound

**Methods:**

```swift
// Relationship nudge
await notificationService.postRelationshipNudge(
    contactName: "Mom",
    reason: "She asked about dinner 2 days ago",
    suggestion: "Reply: 'Sounds great!'",
    priority: "high"
)

// Health alert
await notificationService.postHealthAlert(
    message: "Only 1,500 steps today. Take a 10-minute walk?",
    urgent: false
)

// Daily insight
await notificationService.postDailyInsight(
    title: "Project Deadline Approaching",
    body: "Your notes mention Friday deadline. Consider scheduling focus time."
)

// Scheduled daily brief (recurring)
notificationService.scheduleDailyBrief(
    hour: 8,
    minute: 0,
    brief: "Good morning! ..."
)
```

**Status:** ✅ Fully implemented. Triggers from hourly proactive check.

---

### 9. Proactive Intelligence Loop

**File:** `Managers/BrainManager.swift` (`performProactiveCheck()`)

**Purpose:** Hourly analysis loop that triggers all proactive features.

**Schedule:**

- Runs every hour (started in `BrainManager.start()`)
- Time-based triggers:
  - **7:00 AM** - Generate and cache daily brief
  - **8:00 AM** - Scheduled daily brief notification fires
  - **2:00 PM** - Afternoon activity check (<2000 steps)
  - **6:00 PM** - Evening activity check (<5000 steps)
  - **11:00 PM** - Generate daily journal entry (future)

**Process Flow:**

```swift
func performProactiveCheck() async {
    let hour = Calendar.current.component(.hour, from: Date())
    
    // 1. Relationship Analysis
    let nudges = await RelationshipAgent.shared.analyzeRecentInteractions()
    for nudge in nudges where nudge.priority == .high {
        await notificationService.postRelationshipNudge(...)
    }
    
    // 2. Health Monitoring (time-based)
    if hour == 14 { // 2 PM
        await checkHealthAndNotify(threshold: 2000, message: "...")
    }
    if hour == 18 { // 6 PM
        await checkHealthAndNotify(threshold: 5000, message: "...")
    }
    
    // 3. AI Reflection Task (insights)
    await runReflectionTask()
    
    // 4. Brief Generation (morning only)
    if hour == 7 {
        await generateAndCacheDailyBrief()
    }
}
```

**AI Reflection** (`runReflectionTask()`):
- Gathers: activity, relationships, calendar, memories
- AI prompt: "Identify HIGH-IMPACT situations requiring action"
- Filters noise (only actionable insights)
- Sends notification if insight found

**Status:** ✅ Fully implemented. Runs automatically every hour.

---

### 10. Python Environment Manager (Beta)

**File:** `Services/PythonEnvironmentManager.swift`

**Purpose:** Auto-setup Python virtual environment for voice sidecar.

**Capabilities:**

1. **Create Virtual Environment**
   ```swift
   await PythonEnvironmentManager.shared.ensureVoiceEnvironment()
   // Creates ~/.brainos_voice_venv if not exists
   ```

2. **Install Dependencies**
   ```swift
   await PythonEnvironmentManager.shared.installVoiceDependencies()
   // Installs: fastapi, uvicorn, pydantic
   ```

3. **Generate voice_server.py**
   ```swift
   await PythonEnvironmentManager.shared.ensureVoiceScript()
   // Creates FastAPI server script if missing
   ```

4. **Full Setup**
   ```swift
   await PythonEnvironmentManager.shared.setupCompleteEnvironment()
   // Chains all setup steps
   ```

5. **Status Check**
   ```swift
   let status = await PythonEnvironmentManager.shared.getSetupStatus()
   print(status.isReady) // true if all components ready
   ```

**Status:** ⚠️ Built but not integrated. Needs to be called in `AppDelegate.applicationDidFinishLaunching()`.

---

### 11. Voice Service (Beta)

**Files:**
- `Services/VoiceService.swift` - Swift sidecar manager
- `scripts/voice_server.py` - FastAPI TTS/STT server

**Purpose:** Local text-to-speech and speech-to-text via Python sidecar.

**Voice Server Features:**
- FastAPI server on port 8001 (configurable)
- Chatterbox TTS model (Resemble AI)
- Apple Silicon MPS acceleration
- OpenAI-compatible `/v1/audio/speech` endpoint

**Swift Integration:**
```swift
VoiceService.shared.start() // Launches Python server
VoiceService.shared.stop()  // Terminates server
VoiceService.shared.health() // Checks if responsive
```

**API Example:**
```bash
curl http://127.0.0.1:8001/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello from BrainOS", "voice_id": "default", "speed": 1.0}' \
  --output speech.mp3
```

**Status:** ⚠️ Implemented but not integrated. Voice button in UI not connected.

---

## Configuration

### User Preferences

**Location:** `UserDefaults.standard`

```swift
// User profile
UserDefaults.standard.set("Daksh", forKey: "userName")

// Cached brief
UserDefaults.standard.set("Good morning! ...", forKey: "cachedDailyBrief")
UserDefaults.standard.set(Date(), forKey: "cachedBriefTime")
```

### Service Settings

**Background Ingestion:**
- Interval: 30 minutes (hardcoded in `BackgroundIngestionService`)
- Can be changed in `ingestAll()` sleep duration

**Memory Pipeline:**
- Concurrent workers: 3 (change `maxConcurrentInferences` in `MemoryGenerationPipeline`)
- Max tokens: 256 (change in `generateMemory()`)
- Temperature: 0.7 (change in `generateMemory()`)

**Proactive Check:**
- Interval: 1 hour (hardcoded in `BrainManager.start()`)
- Activity thresholds: 2000 steps (2 PM), 5000 steps (6 PM)
- Brief generation: 7 AM
- Brief notification: 8 AM

---

## Data Flow Examples

### Example 1: Message Ingestion → Chat RAG

```
1. User receives iMessage: "Mom: Don't forget dinner on Sunday!"
   ↓
2. Background Ingestion (30 min later)
   - Fetches last 50 messages
   - Finds: "Don't forget dinner on Sunday!" from Mom
   ↓
3. Memory Pipeline
   - AI generates: summary="Dinner reminder from Mom on Sunday"
   - Entities: ["Mom", "Sunday", "dinner"]
   - Importance: 8
   - Creates embedding vector
   ↓
4. Stores in BrainKnowledgeManager
   - SQLite row: text, summary, entities, importance, timestamp
   - Embedding blob for semantic search
   ↓
5. User opens chat and asks: "What did Mom say about Sunday?"
   ↓
6. ChatEngine.injectRelevantMemories()
   - Query embedding: "What did Mom say about Sunday?"
   - Searches knowledge base (cosine similarity)
   - Finds: "Dinner reminder from Mom on Sunday"
   ↓
7. System prompt enhanced:
   """
   # RELEVANT CONTEXT FROM YOUR MEMORY
   1. Message from Mom: Don't forget dinner on Sunday!
   """
   ↓
8. AI responds: "Mom reminded you about dinner on Sunday."
```

### Example 2: Relationship Nudge Flow

```
1. User hasn't replied to Sarah in 3 days
   ↓
2. Hourly Proactive Check triggers
   ↓
3. RelationshipAgent.analyzeRecentInteractions()
   - Fetches last 100 messages
   - Groups by contact: Sarah (last message 3d ago, from her)
   - Detects: User hasn't replied
   ↓
4. AI Analysis
   - Prompt: "Sarah: 'Are you free this weekend?' (3 days ago)"
   - AI generates: {
       "contactName": "Sarah",
       "reason": "She asked about weekend plans 3 days ago",
       "suggestion": "Reply: 'Sorry for delay! I'm free Saturday'",
       "priority": "high"
     }
   ↓
5. High-priority nudge → Notification
   - NotificationService.postRelationshipNudge()
   - macOS notification with [Reply] [Call] actions
   ↓
6. Dashboard also shows nudge
   - BrainDashboardView displays in Relationships Inbox
```

### Example 3: Daily Brief Generation

```
1. 7:00 AM - Proactive Check triggers
   ↓
2. BrainManager.generateAndCacheDailyBrief()
   ↓
3. Gathers context:
   - Steps: 0 (just woke up)
   - Nudges: ["Reply to Sarah", "Call Mom about dinner"]
   - Calendar: ["Team standup 4 PM", "1-on-1 with boss 2 PM"]
   - Memories: ["Project deadline Friday", "Swift actors research"]
   ↓
4. AI generates brief:
   "Good morning! You've got 2 meetings today including your 1-on-1 
    at 2 PM. Don't forget to reply to Sarah about weekend plans. 
    With Friday's deadline approaching, consider blocking focus time."
   ↓
5. Caches in UserDefaults
   ↓
6. 8:00 AM - Scheduled notification fires
   - Delivers cached brief as notification
   - User wakes up to actionable summary
```

---

## Troubleshooting

### Memory Pipeline Not Processing

**Symptoms:** Dashboard shows "0 memories indexed", no semantic search results

**Diagnosis:**
```swift
// Check if background ingestion is running
let isRunning = await BackgroundIngestionService.shared.isRunning
print("Ingestion running: \(isRunning)")

// Check last ingestion time
// (Logged in Console.app with "BrainOS" filter)
```

**Solutions:**
1. Verify at least one MLX model is downloaded (`BrainOS list`)
2. Check Console.app for "MemoryPipeline" errors
3. Manually trigger: `await BackgroundIngestionService.shared.ingestAll()`

### RAG Not Working in Chat

**Symptoms:** Chat doesn't use past context, generic responses

**Diagnosis:**
```swift
// Search memory manually
let results = await BrainKnowledgeManager.shared.search(
    query: "test query",
    limit: 5
)
print("Found memories: \(results.count)")
```

**Solutions:**
1. Ensure memories exist (check dashboard memory count)
2. Verify Apple NLEmbedding is available (macOS 13+)
3. Query must be semantically similar to stored memories

### Notifications Not Appearing

**Symptoms:** No relationship/health/insight notifications

**Diagnosis:**
```bash
# Check notification permissions
open "x-apple.systempreferences:com.apple.preference.notifications"
# Find BrainOS, ensure "Allow Notifications" is ON
```

**Solutions:**
1. Grant notification permissions in System Settings
2. Check if proactive loop is running: hourly logs in Console.app
3. Verify nudges exist: open Dashboard → Relationships Inbox

### Voice Server Won't Start

**Symptoms:** `VoiceService.shared.start()` fails silently

**Diagnosis:**
```swift
// Check environment setup
let status = await PythonEnvironmentManager.shared.getSetupStatus()
print("Venv exists: \(status.venvExists)")
print("Script exists: \(status.scriptExists)")
print("Dependencies: \(status.dependenciesInstalled)")
```

**Solutions:**
1. Run: `await PythonEnvironmentManager.shared.setupCompleteEnvironment()`
2. Check Python 3 is installed: `python3 --version`
3. Manually test: `~/.brainos_voice_venv/bin/python scripts/voice_server.py`

---

## Performance Considerations

### Memory Pipeline

- **Latency:** ~2-3s per memory (MLX inference)
- **Throughput:** 3 items processed concurrently
- **Batch size:** Unlimited (all items in 30-min window)
- **Typical load:** 50 messages + 20 Safari pages + 10 usage events = 80 items
- **Processing time:** ~80 items ÷ 3 workers × 2.5s = ~67 seconds per batch

### Semantic Search

- **Latency:** <100ms for 1000 memories
- **Algorithm:** Cosine similarity (Apple NLEmbedding)
- **Scalability:** Linear with memory count
- **Optimization:** Pre-computed embeddings stored as BLOB

### Background Impact

- **CPU:** Spikes during AI inference (every 30 min for ~1 minute)
- **Memory:** ~500MB for loaded MLX model
- **Disk:** ~1KB per memory (text + embedding)
- **Network:** None (fully local)

---

## Future Enhancements

### Phase 3: UI/UX (Planned)

- [ ] **Knowledge Graph Visualization** - Interactive entity relationship graph
- [ ] **Timeline View** - Chronological life events with filtering
- [ ] **Voice Interface** - Integrate voice sidecar with UI controls
- [ ] **Futuristic Theme** - Glass panels, neon accents, holographic effects

### Phase 4: Advanced Intelligence (Planned)

- [ ] **First-Run Wizard** - Initial 7-day memory build from historical data
- [ ] **Multi-Modal Embeddings** - Vision + text for photo analysis
- [ ] **Reranking** - Cross-encoder reranking for better RAG accuracy
- [ ] **Custom Entity Extractors** - Train on user's specific context
- [ ] **Predictive Insights** - "You usually call Mom on Sundays"
- [ ] **Memory Deduplication** - Detect and merge similar memories
- [ ] **Analytics Dashboard** - Charts, graphs, trends over time

### Integration TODOs

- [ ] Connect `RealTimeEventStream` to data managers for instant ingestion
- [ ] Integrate `PythonEnvironmentManager` auto-setup in `AppDelegate`
- [ ] Auto-warm primary model on app launch (reduce first-inference delay)
- [ ] Add voice button to chat interface with TTS/STT

---

## Code Reference

### Key Files

| File | Purpose | Status |
|------|---------|--------|
| `Services/MemoryGenerationPipeline.swift` | Parallel AI processing | ✅ Stable |
| `Services/BackgroundIngestionService.swift` | Data collection | ✅ Stable |
| `Services/RealTimeEventStream.swift` | Event buffering | ⚠️ Built, not integrated |
| `Managers/BrainKnowledgeManager.swift` | Memory storage/retrieval | ✅ Stable |
| `Services/ChatEngine.swift` | RAG integration | ✅ Stable |
| `Managers/BrainManager.swift` | Proactive intelligence loop | ✅ Stable |
| `Managers/RelationshipAgent.swift` | Social pattern analysis | ✅ Stable |
| `Services/NotificationService.swift` | Multi-category notifications | ✅ Stable |
| `Views/BrainDashboardView.swift` | Intelligence hub UI | ✅ Stable |
| `Services/PythonEnvironmentManager.swift` | Voice environment setup | ⚠️ Built, not integrated |
| `Services/VoiceService.swift` | Voice sidecar manager | ⚠️ Built, not integrated |

### Key Data Models

```swift
// DataItem (input to pipeline)
enum DataItem: Sendable {
    case message(text: String, sender: String, timestamp: Date)
    case calendarEvent(title: String, startDate: Date, endDate: Date, location: String?)
    case healthData(type: String, value: Double, unit: String, timestamp: Date)
    case safariPage(url: String, title: String, visitTime: Date)
    case usageEvent(appName: String, duration: TimeInterval, timestamp: Date)
    case location(latitude: Double, longitude: Double, placeName: String?, timestamp: Date)
}

// GeneratedMemory (output from pipeline)
struct GeneratedMemory: Sendable {
    let id: UUID
    let text: String
    let summary: String
    let entities: [String]
    let sentiment: String?
    let importance: Int // 1-10
    let timestamp: Date
    let sourceType: String
}

// RelationshipNudge (output from agent)
struct RelationshipNudge {
    let contactName: String
    let reason: String
    let suggestion: String?
    let priority: NudgePriority // high/medium/low
    let actionType: String? // reply/call/meetup
    let daysSinceContact: Int
}

// BrainEvent (real-time stream)
enum BrainEvent: Sendable {
    case messageReceived(sender: String, text: String, timestamp: Date)
    case calendarEventStarting(title: String, startDate: Date, location: String?)
    case healthDataUpdated(type: String, value: Double, unit: String)
    case locationChanged(latitude: Double, longitude: Double, placeName: String?)
    case appUsageDetected(appName: String, startTime: Date)
    case safariPageVisited(url: String, title: String)
}
```

---

## Summary

The Brain Intelligence System transforms BrainOS from a passive LLM server into a proactive digital assistant. By continuously monitoring life data, building semantic memories, and generating insights automatically, it aims to surface the right information at the right time—before you have to ask.

**Current Status:** Core functionality (Phases 1 & 2) is fully implemented and operational. Real-time streaming and voice integration are built but pending final integration. Advanced UI and analytics features are planned for future phases.

**Privacy:** All processing happens locally on your Mac. No data is sent to cloud services. Embeddings are generated using Apple's NLEmbedding. MLX models run on Apple Silicon.

For questions or contributions, see the main [CONTRIBUTING.md](CONTRIBUTING.md) guide.
