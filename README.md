# BrainOS

**The Operating System for Optimized Living.**

BrainOS is a native macOS AI operating system built on a fork of BrainOS. It transforms your Mac into a proactive personal agent that understands your life data—health, finance, relationships, and visual memory—while keeping everything 100% local and private.

---

## The 2026 Vision

BrainOS isn't just an LLM runner; it's your digital brain.

- **Core Runtime** — Native Swift + MLX for blazing Apple Silicon inference.
- **Data Ingestion** — Seamlessly connects to HealthKit, Calendar, Photos, Messages, and Finance.
- **Proactive Agents** — Silent agents that monitor your "Life Health" and provide daily briefs.
- **Semantic Memory** — Local vector store for screenshots, photos, and transactions.
- **Raycast-style Dashboard** — A beautiful, glanceable interface for your optimized life.

---

## Features

- **MLX Runtime** — Optimized local inference for Apple Silicon.
- **MCP Native** — Every data source is a tool for your agents.
- **Life Plugins** — Built-in support for Health, Photos, and Screenshots.
- **Proactive Intelligence** — Relationship nudges, health insights, and spending alerts.
- **Privacy First** — Everything stays on your device. No cloud required.

---

## Getting Started

```bash
# Clone the repo
git clone https://github.com/dakshbhatia/BrainOS.git
cd BrainOS

# Build app (requires Xcode)
make app

# Or run via CLI
make serve
```

Launch from Spotlight (`⌘ Space` → "BrainOS").

- **Apple Foundation Models** — Use the system model on macOS 26+ (Tahoe)

### Highlights

| Feature                  | Description                                                     |
| ------------------------ | --------------------------------------------------------------- |
| **Local LLM Server**     | Run Llama, Qwen, Gemma, Mistral, and more locally               |
| **Remote Providers**     | Anthropic, OpenAI, OpenRouter, Ollama, LM Studio, or custom     |
| **OpenAI Compatible**    | `/v1/chat/completions` with streaming and tool calling          |
| **Anthropic Compatible** | `/messages` endpoint for Claude Code and Anthropic SDK clients  |
| **MCP Server**           | Connect to Cursor, Claude Desktop, and other MCP clients        |
| **Remote MCP Providers** | Aggregate tools from external MCP servers                       |
| **Tools & Plugins**      | Browser automation, file system, git, web search, and more      |
| **Personas**             | Custom AI assistants with unique prompts, tools, and themes     |
| **Custom Themes**        | Create, import, and export themes with full color customization |
| **Developer Tools**      | Request insights, API explorer, and live endpoint testing       |
| **Menu Bar Chat**        | Chat overlay with session history, context tracking (`⌘;`)      |
| **Model Manager**        | Download and manage models from Hugging Face                    |

---

## Quick Start

### 1. Start the Server

Launch BrainOS from Spotlight or run:

```bash
BrainOS serve
```

The server starts on port `1337` by default.

### 2. Connect an MCP Client

Add to your MCP client configuration (e.g., Cursor, Claude Desktop):

```json
{
  "mcpServers": {
    "BrainOS": {
      "command": "BrainOS",
      "args": ["mcp"]
    }
  }
}
```

### 3. Add a Remote Provider (Optional)

Open the Management window (`⌘ Shift M`) → **Providers** → **Add Provider**.

Choose from presets (OpenAI, Ollama, LM Studio, OpenRouter) or configure a custom endpoint.

---

## Key Features

### Local Models (MLX)

Run models locally with optimized Apple Silicon inference:

```bash
# Download a model
BrainOS run llama-3.2-3b-instruct-4bit

# Use via API
curl http://127.0.0.1:1337/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "llama-3.2-3b-instruct-4bit", "messages": [{"role": "user", "content": "Hello!"}]}'
```

### Remote Providers

Connect to remote APIs to access cloud models alongside local ones.

**Supported presets:**

- **Anthropic** — Claude models with native API support
- **OpenAI** — GPT-4o, o1, and other OpenAI models
- **OpenRouter** — Access multiple providers through one API
- **Ollama** — Connect to a local or remote Ollama instance
- **LM Studio** — Use LM Studio as a backend
- **Custom** — Any OpenAI-compatible endpoint

Features:

- Secure API key storage (macOS Keychain)
- Custom headers for authentication
- Auto-connect on launch
- Connection health monitoring

See [Remote Providers Guide](docs/REMOTE_PROVIDERS.md) for details.

### MCP Server

BrainOS is a full MCP (Model Context Protocol) server. Connect it to any MCP client to give AI agents access to your installed tools.

| Endpoint          | Description            |
| ----------------- | ---------------------- |
| `GET /mcp/health` | Check MCP availability |
| `GET /mcp/tools`  | List active tools      |
| `POST /mcp/call`  | Execute a tool         |

### Remote MCP Providers

Connect to external MCP servers and aggregate their tools into BrainOS:

- Discover and register tools from remote MCP endpoints
- Configurable timeouts and streaming
- Tools are namespaced by provider (e.g., `provider_toolname`)
- Secure token storage

See [Remote MCP Providers Guide](docs/REMOTE_MCP_PROVIDERS.md) for details.

### Tools & Plugins

Install tools from the [central registry](https://github.com/dinoki-ai/BrainOS-tools) or create your own.

**Official System Tools:**

| Plugin               | Tools                                                                     |
| -------------------- | ------------------------------------------------------------------------- |
| `BrainOS.filesystem` | `read_file`, `write_file`, `list_directory`, `search_files`, and more     |
| `BrainOS.browser`    | `browser_navigate`, `browser_click`, `browser_type`, `browser_screenshot` |
| `BrainOS.git`        | `git_status`, `git_log`, `git_diff`, `git_branch`                         |
| `BrainOS.search`     | `search`, `search_news`, `search_images` (DuckDuckGo)                     |
| `BrainOS.fetch`      | `fetch`, `fetch_json`, `fetch_html`, `download`                           |
| `BrainOS.time`       | `current_time`, `format_date`                                             |

```bash
# Install from registry
BrainOS tools install BrainOS.browser

# List installed tools
BrainOS tools list

# Create your own plugin
BrainOS tools create MyPlugin --language swift
```

See the [Plugin Authoring Guide](docs/PLUGIN_AUTHORING.md) for details.

### Personas

Create custom AI assistant personalities with unique behaviors, capabilities, and styles.

Each persona can have:

- **Custom System Prompt** — Define unique instructions and personality
- **Tool Configuration** — Enable or disable specific tools per persona
- **Visual Theme** — Assign a custom theme that activates with the persona
- **Model & Generation Settings** — Set default model, temperature, and max tokens
- **Import/Export** — Share personas as JSON files

Use cases:

- **Code Assistant** — Focused on programming with code-related tools enabled
- **Daily Planner** — Calendar and reminders integration
- **Research Helper** — Web search and note-taking tools enabled
- **Creative Writer** — Higher temperature, no tool access for pure generation

Access via Management window (`⌘ Shift M`) → **Personas**.

### Developer Tools

Built-in tools for debugging and development:

**Insights** — Monitor all API requests in real-time:

- Request/response logging with full payloads
- Filter by method (GET/POST) and source (Chat UI/HTTP API)
- Performance stats: success rate, average latency, errors
- Inference metrics: tokens, speed (tok/s), model used

**Server Explorer** — Interactive API reference:

- Live server status and health
- Browse all available endpoints
- Test endpoints directly with editable payloads
- View formatted responses

Access via Management window (`⌘ Shift M`) → **Insights** or **Server**.

See [Developer Tools Guide](docs/DEVELOPER_TOOLS.md) for details.

---

## CLI Reference

| Command                  | Description                                  |
| ------------------------ | -------------------------------------------- |
| `BrainOS serve`          | Start the server (default port 1337)         |
| `BrainOS serve --expose` | Start exposed on LAN                         |
| `BrainOS stop`           | Stop the server                              |
| `BrainOS status`         | Check server status                          |
| `BrainOS ui`             | Open the menu bar UI                         |
| `BrainOS list`           | List downloaded models                       |
| `BrainOS run <model>`    | Interactive chat with a model                |
| `BrainOS mcp`            | Start MCP stdio transport                    |
| `BrainOS tools <cmd>`    | Manage plugins (install, list, search, etc.) |

**Tip:** Set `OSU_PORT` to override the default port.

---

## API Endpoints

Base URL: `http://127.0.0.1:1337` (or your configured port)

| Endpoint                    | Description                         |
| --------------------------- | ----------------------------------- |
| `GET /health`               | Server health                       |
| `GET /v1/models`            | List models (OpenAI format)         |
| `GET /v1/tags`              | List models (Ollama format)         |
| `POST /v1/chat/completions` | Chat completions (OpenAI format)    |
| `POST /messages`            | Chat completions (Anthropic format) |
| `POST /chat`                | Chat (Ollama format, NDJSON)        |

All endpoints support `/v1`, `/api`, and `/v1/api` prefixes.

See the [OpenAI API Guide](docs/OpenAI_API_GUIDE.md) for tool calling, streaming, and SDK examples.

---

## Use with OpenAI SDKs

Point any OpenAI-compatible client at BrainOS:

```python
from openai import OpenAI

client = OpenAI(base_url="http://127.0.0.1:1337/v1", api_key="BrainOS")

response = client.chat.completions.create(
    model="llama-3.2-3b-instruct-4bit",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)
```

---

## Requirements

- macOS 15.5+ (Apple Foundation Models require macOS 26)
- Apple Silicon (M1 or newer)
- Xcode 16.4+ (to build from source)

Models are stored at `~/MLXModels` by default. Override with `OSU_MODELS_DIR`.

---

## Build from Source

```bash
git clone https://github.com/dinoki-ai/BrainOS.git
cd BrainOS
open BrainOS.xcworkspace
# Build and run the "BrainOS" target
```

---

## Contributing

**We're looking for contributors!** BrainOS is actively developed and we welcome help in many areas:

- Bug fixes and performance improvements
- New plugins and tool integrations
- Documentation and tutorials
- UI/UX enhancements
- Testing and issue triage

### Get Started

1. Check out [Good First Issues](https://github.com/dinoki-ai/BrainOS/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
2. Read the [Contributing Guide](docs/CONTRIBUTING.md)
3. Join our [Discord](https://discord.gg/dinoki) to connect with the team

See [docs/FEATURES.md](docs/FEATURES.md) for a complete feature inventory and architecture overview.

---

## Community

- **[Documentation](https://docs.BrainOS.ai/)** — Guides and tutorials
- **[Discord](https://discord.gg/dinoki)** — Chat with the community
- **[Plugin Registry](https://github.com/dinoki-ai/BrainOS-tools)** — Browse and contribute tools
- **[Contributing Guide](docs/CONTRIBUTING.md)** — How to contribute

If you find BrainOS useful, please star the repo and share it!
