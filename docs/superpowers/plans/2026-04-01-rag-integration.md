# RAG Sidecar Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate `ai-rag-service` as a research sidecar for `ai-market-studio` to answer natural language questions about internal docs.

**Architecture:** Add a RAG connector to Studio backend, register a new LLM tool `get_internal_research`, and update the UI to display research insights with source citations.

**Tech Stack:** Python (FastAPI), Pydantic, OpenAI API, HTTPX, HTML/JS (Frontend).

---

### Task 1: Configuration & Settings

**Files:**
- Modify: `backend/config.py`
- Modify: `k8s/configmap.yaml`

- [ ] **Step 1: Update Settings model**

Add `rag_service_url` to the `Settings` class in `backend/config.py`.

```python
class Settings(BaseSettings):
    # ... existing fields
    rag_service_url: str = "http://localhost:8000"
```

- [ ] **Step 2: Update K8s ConfigMap**

Add `RAG_SERVICE_URL` to `k8s/configmap.yaml`.

```yaml
data:
  # ... existing data
  RAG_SERVICE_URL: "http://ai-rag-service:8000"
```

- [ ] **Step 3: Commit**

```bash
git add backend/config.py k8s/configmap.yaml
git commit -m "feat: add RAG_SERVICE_URL configuration"
```

### Task 2: RAG Connector & Tool Definitions

**Files:**
- Create: `backend/connectors/rag_connector.py`
- Modify: `backend/agent/tools.py`
- Test: `backend/tests/unit/test_rag_connector.py`

- [ ] **Step 1: Implement RAG Connector**

Create `backend/connectors/rag_connector.py` using `httpx` to query the `ai-rag-service`.

```python
import httpx
from backend.config import settings

class RAGConnector:
    def __init__(self, url: str = settings.rag_service_url):
        self.url = url

    async def query_research(self, question: str) -> dict:
        async with httpx.AsyncClient() as client:
            try:
                resp = await client.post(f"{self.url}/query", json={"question": question}, timeout=10.0)
                resp.raise_for_status()
                return resp.json()
            except Exception as e:
                return {"error": str(e)}
```

- [ ] **Step 2: Define `get_internal_research` tool**

Add the tool schema to `TOOL_DEFINITIONS` in `backend/agent/tools.py`.

```python
{
    "type": "function",
    "function": {
        "name": "get_internal_research",
        "description": "Search internal research documents (PDFs, Jira, Confluence) for market insights.",
        "parameters": {
            "type": "object",
            "properties": {
                "question": {"type": "string", "description": "The specific query to search in internal docs."}
            },
            "required": ["question"]
        }
    }
}
```

- [ ] **Step 3: Update `dispatch_tool`**

Handle the `get_internal_research` tool in `backend/agent/tools.py`.

```python
elif tool_name == "get_internal_research":
    rag = RAGConnector()
    return await rag.query_research(arguments.get("question"))
```

- [ ] **Step 4: Commit**

```bash
git add backend/connectors/rag_connector.py backend/agent/tools.py
git commit -m "feat: implement RAG connector and register get_internal_research tool"
```

### Task 3: UI Implementation

**Files:**
- Modify: `frontend/index.html` (Frontend code)
- Modify: `backend/agent/agent.py` (LLM Response Formatting)

- [ ] **Step 1: UI Source Display Logic**

Update the chat message rendering logic in `frontend/index.html` to handle the `rag` response data type.

```javascript
if (data.type === "rag") {
    const sourcesHtml = data.sources.map(s => `<li>${s.name}</li>`).join("");
    messageContent += `<div class="rag-sources">Sources:<ul>${sourcesHtml}</ul></div>`;
}
```

- [ ] **Step 2: LLM Tool Summary Integration**

Update `_summarise_tool_result` in `backend/agent/agent.py` to handle RAG response formatting.

```python
if result.get("type") == "rag":
    sources_list = [s["name"] for s in result.get("sources", [])]
    return {"type": "rag", "sources": sources_list}
```

- [ ] **Step 3: Update LLM System Prompt**

Add `get_internal_research` to the `SYSTEM_PROMPT` in `backend/agent/agent.py`.

```python
- When the user asks for internal research, analyst reports, or internal docs, use the get_internal_research tool.
```

- [ ] **Step 4: Commit**

```bash
git add frontend/index.html backend/agent/agent.py
git commit -m "feat: frontend display for RAG sources and LLM tool summary integration"
```

### Task 4: Final Verification

**Files:**
- Test: `backend/tests/e2e/test_rag_integration.py` (New E2E test)

- [ ] **Step 1: Write E2E Test**

Create a new test file `backend/tests/e2e/test_rag_integration.py` to verify the end-to-end integration.

```python
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_rag_query_tool_call(client: AsyncClient):
    response = await client.post("/api/chat", json={"message": "What is the internal research on USD?", "history": []})
    assert response.status_code == 200
    assert "tool_used" in response.json()
    assert response.json()["tool_used"] == "get_internal_research"
```

- [ ] **Step 2: Run Tests**

Run the E2E test suite to verify the integration.

Run: `pytest backend/tests/e2e/test_rag_integration.py -v`
Expected: PASS (with mock rag-service if available, otherwise check for 503/404)

- [ ] **Step 3: Final Commit**

```bash
git add backend/tests/e2e/test_rag_integration.py
git commit -m "test: add E2E integration test for RAG tool"
```
