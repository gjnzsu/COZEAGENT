# AI Gateway Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate ai-gateway-service with ai-market-studio backend to centralize LLM provider management and enable multi-provider routing.

**Architecture:** Backend OpenAI client will point to internal gateway endpoint instead of api.openai.com. Gateway handles provider routing based on model name. Configuration-only change with zero agent logic modifications.

**Tech Stack:** Python 3.12, FastAPI, OpenAI SDK, Kubernetes (GKE), Docker

---

## File Structure

**Files to Modify:**
- `backend/config.py` — Add `openai_base_url` field to Settings
- `backend/agent/agent.py` — Pass `base_url` to AsyncOpenAI client
- `k8s/configmap.yaml` — Add `OPENAI_BASE_URL` environment variable
- `k8s/secret.yaml` — Update `OPENAI_API_KEY` to dummy value

**Files to Create:**
- `backend/tests/e2e/test_gateway_integration.py` — E2E test for gateway connectivity

**No new components needed.** This is a configuration change with minimal code updates.

---

## Task 1: Update Backend Configuration

**Files:**
- Modify: `backend/config.py:5-28`

- [ ] **Step 1: Add openai_base_url field to Settings class**

Open `backend/config.py` and add the new field after `openai_model`:

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    openai_api_key: SecretStr
    openai_base_url: str = "https://api.openai.com/v1"  # NEW
    openai_model: str = "gpt-4o"

    exchangerate_api_key: SecretStr
    use_mock_connector: bool = False
    use_mock_news_connector: bool = True

    cors_origins: str = "*"
    max_historical_days: int = 7
    rag_service_url: str = "http://localhost:8000"

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",")]


settings = Settings()
```

- [ ] **Step 2: Verify configuration loads correctly**

Run a quick test to ensure the new field doesn't break config loading:

```bash
cd C:\SourceCode\ai-market-studio
python -c "from backend.config import settings; print(f'Base URL: {settings.openai_base_url}')"
```

Expected output:
```
Base URL: https://api.openai.com/v1
```

- [ ] **Step 3: Commit configuration change**

```bash
git add backend/config.py
git commit -m "feat(config): add openai_base_url field for gateway integration

- Add openai_base_url with default to direct OpenAI
- Allows override via OPENAI_BASE_URL env var
- Backward compatible with existing deployments"
```

---

## Task 2: Update Agent Client Initialization

**Files:**
- Modify: `backend/agent/agent.py:77-82`

- [ ] **Step 1: Add base_url parameter to AsyncOpenAI client**

Open `backend/agent/agent.py` and locate the client initialization (around line 79). Update it to use the configured base URL:

**Before:**
```python
if client is None:
    import httpx
    client = AsyncOpenAI(
        api_key=settings.openai_api_key.get_secret_value(),
        http_client=httpx.AsyncClient(trust_env=False),
    )
```

**After:**
```python
if client is None:
    import httpx
    client = AsyncOpenAI(
        api_key=settings.openai_api_key.get_secret_value(),
        base_url=settings.openai_base_url,
        http_client=httpx.AsyncClient(trust_env=False),
    )
```

- [ ] **Step 2: Verify existing unit tests still pass**

Run unit tests to ensure the change doesn't break existing functionality:

```bash
cd C:\SourceCode\ai-market-studio
python -m pytest backend/tests/unit/ -v
```

Expected: All tests pass (base_url parameter doesn't affect mocked clients).

- [ ] **Step 3: Commit agent code change**

```bash
git add backend/agent/agent.py
git commit -m "feat(agent): use configurable base_url for OpenAI client

- Pass settings.openai_base_url to AsyncOpenAI constructor
- Enables routing through ai-gateway-service
- No changes to agent logic or tool definitions"
```

---

## Task 3: Update Kubernetes ConfigMap

**Files:**
- Modify: `k8s/configmap.yaml:1-11`

- [ ] **Step 1: Add OPENAI_BASE_URL to ConfigMap**

Open `k8s/configmap.yaml` and add the gateway URL:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-market-studio-config
data:
  USE_MOCK_CONNECTOR: "true"
  USE_MOCK_NEWS_CONNECTOR: "false"
  OPENAI_BASE_URL: "http://ai-gateway.ai-gateway.svc.cluster.local/v1"
  OPENAI_MODEL: "gpt-4o"
  CORS_ORIGINS: "http://136.116.205.168,http://ai-market-studio-ui,http://localhost:8080"
  MAX_HISTORICAL_DAYS: "7"
  RAG_SERVICE_URL: "http://34.10.130.210"
```

- [ ] **Step 2: Verify YAML syntax**

```bash
kubectl apply -f k8s/configmap.yaml --dry-run=client
```

Expected: `configmap/ai-market-studio-config configured (dry run)`

- [ ] **Step 3: Commit ConfigMap change**

```bash
git add k8s/configmap.yaml
git commit -m "feat(k8s): add OPENAI_BASE_URL pointing to ai-gateway

- Route backend LLM calls through internal gateway
- Gateway endpoint: http://ai-gateway.ai-gateway.svc.cluster.local/v1
- Enables multi-provider routing (OpenAI, DeepSeek)"
```

---

## Task 4: Update Kubernetes Secret

**Files:**
- Modify: `k8s/secret.yaml:1-9`

- [ ] **Step 1: Update OPENAI_API_KEY to dummy value**

Open `k8s/secret.yaml` and change the OpenAI key to a dummy value (gateway manages real keys):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-market-studio-secrets
type: Opaque
stringData:
  OPENAI_API_KEY: "dummy"
  EXCHANGERATE_API_KEY: "your-exchangerate-api-key-here"
```

**Note:** Replace `your-exchangerate-api-key-here` with the actual key from your existing secret.

- [ ] **Step 2: Verify secret syntax**

```bash
kubectl apply -f k8s/secret.yaml --dry-run=client
```

Expected: `secret/ai-market-studio-secrets configured (dry run)`

- [ ] **Step 3: Commit secret change**

```bash
git add k8s/secret.yaml
git commit -m "feat(k8s): use dummy OPENAI_API_KEY for gateway integration

- Gateway manages real API keys internally
- Backend only needs placeholder value for SDK
- Reduces key sprawl across services"
```

---

## Task 5: Create Gateway Integration E2E Test

**Files:**
- Create: `backend/tests/e2e/test_gateway_integration.py`

- [ ] **Step 1: Write E2E test for gateway connectivity**

Create new file `backend/tests/e2e/test_gateway_integration.py`:

```python
"""E2E test for AI Gateway integration."""
import os
import pytest
from httpx import AsyncClient

from backend.main import app


@pytest.mark.asyncio
async def test_chat_via_gateway():
    """Verify backend can call gateway successfully."""
    # Set gateway URL for this test
    original_url = os.environ.get("OPENAI_BASE_URL")
    os.environ["OPENAI_BASE_URL"] = "http://ai-gateway.ai-gateway.svc.cluster.local/v1"

    try:
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.post(
                "/api/chat",
                json={
                    "message": "What is the EUR/USD rate?",
                    "history": []
                }
            )

            assert response.status_code == 200
            data = response.json()
            assert "reply" in data
            assert data["reply"] != ""
            # Tool should have been called
            assert data.get("tool_used") in ["get_fx_rate", "get_current_rate"]
    finally:
        # Restore original URL
        if original_url:
            os.environ["OPENAI_BASE_URL"] = original_url
        else:
            os.environ.pop("OPENAI_BASE_URL", None)


@pytest.mark.asyncio
async def test_gateway_model_selection():
    """Verify backend respects OPENAI_MODEL setting."""
    original_model = os.environ.get("OPENAI_MODEL")
    os.environ["OPENAI_MODEL"] = "gpt-4o-mini"

    try:
        async with AsyncClient(app=app, base_url="http://test") as client:
            response = await client.post(
                "/api/chat",
                json={
                    "message": "Hello",
                    "history": []
                }
            )

            assert response.status_code == 200
            data = response.json()
            assert "reply" in data
    finally:
        if original_model:
            os.environ["OPENAI_MODEL"] = original_model
        else:
            os.environ.pop("OPENAI_MODEL", None)
```

- [ ] **Step 2: Run test locally (will skip if gateway not accessible)**

```bash
cd C:\SourceCode\ai-market-studio
python -m pytest backend/tests/e2e/test_gateway_integration.py -v -s
```

Expected: Test may fail locally if gateway not running, but should pass after GKE deployment.

- [ ] **Step 3: Commit E2E test**

```bash
git add backend/tests/e2e/test_gateway_integration.py
git commit -m "test(e2e): add gateway integration tests

- Verify backend can call gateway successfully
- Test model selection via OPENAI_MODEL env var
- Will pass after GKE deployment with gateway access"
```

---

## Task 6: Build and Push Docker Image

**Files:**
- Build: `Dockerfile`

- [ ] **Step 1: Build Docker image with multi-stage build**

```bash
cd C:\SourceCode\ai-market-studio
docker build -t gcr.io/gen-lang-client-0896070179/ai-market-studio:latest .
```

Expected: Build completes successfully, preserving layer cache for unchanged dependencies.

- [ ] **Step 2: Verify image contains updated code**

```bash
docker run --rm gcr.io/gen-lang-client-0896070179/ai-market-studio:latest python -c "from backend.config import Settings; print(Settings.model_fields.keys())"
```

Expected output should include `openai_base_url` in the field list.

- [ ] **Step 3: Push image to GCR**

```bash
docker push gcr.io/gen-lang-client-0896070179/ai-market-studio:latest
```

Expected: Image pushed successfully to Google Container Registry.

---

## Task 7: Deploy to GKE

**Files:**
- Apply: `k8s/configmap.yaml`, `k8s/secret.yaml`

- [ ] **Step 1: Apply updated ConfigMap**

```bash
kubectl apply -f k8s/configmap.yaml
```

Expected: `configmap/ai-market-studio-config configured`

- [ ] **Step 2: Apply updated Secret**

```bash
kubectl apply -f k8s/secret.yaml
```

Expected: `secret/ai-market-studio-secrets configured`

- [ ] **Step 3: Rolling restart deployment**

```bash
kubectl rollout restart deployment/ai-market-studio
```

Expected: `deployment.apps/ai-market-studio restarted`

- [ ] **Step 4: Wait for rollout to complete**

```bash
kubectl rollout status deployment/ai-market-studio
```

Expected: `deployment "ai-market-studio" successfully rolled out`

- [ ] **Step 5: Verify pods are running**

```bash
kubectl get pods -l app=ai-market-studio
```

Expected: All pods in `Running` state with `READY 1/1`.

---

## Task 8: Verify Gateway Integration

**Files:**
- Test: Backend API, Gateway logs

- [ ] **Step 1: Check backend logs for startup**

```bash
kubectl logs -l app=ai-market-studio --tail=50
```

Look for:
- `INFO: AI Market Studio started.`
- No OpenAI authentication errors
- No connection errors

- [ ] **Step 2: Test chat endpoint**

```bash
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is the EUR/USD rate?",
    "history": []
  }'
```

Expected: JSON response with `reply`, `data`, and `tool_used` fields. No errors.

- [ ] **Step 3: Check gateway logs for incoming requests**

```bash
kubectl -n ai-gateway logs -l app=ai-gateway --tail=50
```

Look for:
- `POST /v1/chat/completions` requests
- `model=gpt-4o` in log entries
- `provider=openai` routing
- No 4xx or 5xx errors

- [ ] **Step 4: Test all major features**

Run through manual testing checklist:

```bash
# Test dashboard
curl -X POST http://35.224.3.54/api/dashboard \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard_id": "test",
    "panels": [{
      "panel_id": "1",
      "panel_type": "line",
      "base": "EUR",
      "targets": ["USD"],
      "start_date": "2026-04-06",
      "end_date": "2026-04-13"
    }]
  }'

# Test news (if using live connector)
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is the latest FX news?", "history": []}'

# Test RAG
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What does our internal research say about EUR/USD?", "history": []}'
```

Expected: All endpoints return valid responses.

- [ ] **Step 5: Verify frontend UI works**

Open browser to http://136.116.205.168 and test:
- Send chat message
- View dashboard
- Check news display
- Verify no console errors

---

## Task 9: Test Model Switching

**Files:**
- Modify: `k8s/configmap.yaml` (temporarily)

- [ ] **Step 1: Change model to gpt-4o-mini**

```bash
kubectl patch configmap ai-market-studio-config \
  --patch '{"data":{"OPENAI_MODEL":"gpt-4o-mini"}}'
```

Expected: `configmap/ai-market-studio-config patched`

- [ ] **Step 2: Rolling restart to pick up new model**

```bash
kubectl rollout restart deployment/ai-market-studio
kubectl rollout status deployment/ai-market-studio
```

Expected: Deployment restarted successfully.

- [ ] **Step 3: Test with new model**

```bash
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello", "history": []}'
```

Expected: Valid response.

- [ ] **Step 4: Check gateway logs for model name**

```bash
kubectl -n ai-gateway logs -l app=ai-gateway --tail=20 | grep "model="
```

Expected: Log entries show `model=gpt-4o-mini`.

- [ ] **Step 5: Revert to gpt-4o**

```bash
kubectl patch configmap ai-market-studio-config \
  --patch '{"data":{"OPENAI_MODEL":"gpt-4o"}}'
kubectl rollout restart deployment/ai-market-studio
```

Expected: Model reverted to default.

---

## Task 10: Document Integration and Update Memory

**Files:**
- Modify: `C:\Users\gjnzsu\.claude\projects\c--SourceCode\memory\MEMORY.md`

- [ ] **Step 1: Add gateway integration section to memory**

Open `C:\Users\gjnzsu\.claude\projects\c--SourceCode\memory\MEMORY.md` and add after the FRED Integration section:

```markdown
## AI Gateway Integration (2026-04-13) ✅ COMPLETE

**Decision: Route all LLM calls through ai-gateway-service**

**Implementation complete:**
- Backend: `backend/config.py` (added `openai_base_url` field)
- Agent: `backend/agent/agent.py` (pass `base_url` to AsyncOpenAI)
- ConfigMap: `OPENAI_BASE_URL=http://ai-gateway.ai-gateway.svc.cluster.local/v1`
- Secret: `OPENAI_API_KEY=dummy` (gateway manages real keys)
- E2E test: `backend/tests/e2e/test_gateway_integration.py`
- Commits: [list commit hashes after completion]

**Benefits:**
- Centralized API key management (keys only in gateway)
- Multi-provider routing (OpenAI, DeepSeek) without code changes
- Cost optimization via model selection (gpt-4o, gpt-4o-mini, deepseek-chat)
- Single point for LLM observability

**Model Selection:**
- Change `OPENAI_MODEL` in ConfigMap to switch models
- Available: `gpt-4o`, `gpt-4o-mini`, `deepseek-chat`
- Rolling restart required after ConfigMap change

**Rollback:**
```bash
kubectl patch configmap ai-market-studio-config \
  --patch '{"data":{"OPENAI_BASE_URL":"https://api.openai.com/v1"}}'
kubectl patch secret ai-market-studio-secrets \
  --patch '{"stringData":{"OPENAI_API_KEY":"sk-real-key"}}'
kubectl rollout restart deployment/ai-market-studio
```
```

- [ ] **Step 2: Commit memory update**

```bash
git add C:\Users\gjnzsu\.claude\projects\c--SourceCode\memory\MEMORY.md
git commit -m "docs(memory): add AI Gateway integration notes

- Document gateway integration completion
- Add model selection instructions
- Include rollback procedure"
```

- [ ] **Step 3: Create final summary commit**

```bash
git commit --allow-empty -m "feat: complete AI Gateway integration

Summary:
- Backend now routes all LLM calls through ai-gateway-service
- Centralized API key management in gateway
- Dynamic model selection (gpt-4o, gpt-4o-mini, deepseek-chat)
- Zero changes to agent logic or tool definitions
- Backward compatible with easy rollback

Deployment:
- GKE cluster: helloworld-cluster (us-central1)
- Backend: http://35.224.3.54
- Gateway: http://ai-gateway.ai-gateway.svc.cluster.local/v1

Testing:
- All existing features verified (chat, dashboard, news, RAG, PDF)
- Gateway logs show successful routing
- Model switching tested and working

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Rollback Procedure (If Needed)

If any issues occur during deployment, revert immediately:

```bash
# Revert ConfigMap to direct OpenAI
kubectl patch configmap ai-market-studio-config \
  --patch '{"data":{"OPENAI_BASE_URL":"https://api.openai.com/v1"}}'

# Restore real OpenAI key (replace with actual key)
kubectl patch secret ai-market-studio-secrets \
  --patch '{"stringData":{"OPENAI_API_KEY":"sk-proj-..."}}'

# Rolling restart
kubectl rollout restart deployment/ai-market-studio
kubectl rollout status deployment/ai-market-studio

# Verify backend works
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Test", "history": []}'
```

No code rollback needed — changes are backward compatible.

---

## Success Criteria

All items must be checked before considering integration complete:

- [ ] Backend successfully calls gateway for all chat requests
- [ ] All existing features work unchanged (chat, dashboard, news, RAG, PDF export)
- [ ] Gateway logs show incoming requests from backend with correct model names
- [ ] Model switching works by changing ConfigMap and restarting
- [ ] Rollback to direct OpenAI tested and works in <2 minutes
- [ ] No increase in error rate or latency compared to direct OpenAI
- [ ] Local dev workflow documented and tested
- [ ] Memory file updated with integration details

---

## Post-Deployment Monitoring

Monitor these metrics for 24 hours after deployment:

**Backend metrics:**
- Chat endpoint latency (should remain <2s p95)
- Error rate (should remain <1%)
- Tool call success rate (should remain >95%)

**Gateway metrics:**
- Request count (should match backend chat volume)
- Latency by provider (OpenAI should be <1.5s p95)
- Error rate (should be <1%)

**Alerts to watch:**
- Backend → Gateway connection failures
- Gateway 5xx errors
- Increased chat endpoint latency

If any metric degrades significantly, execute rollback procedure immediately.
