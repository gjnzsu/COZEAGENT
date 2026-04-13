# AI Gateway Integration Design

**Date:** 2026-04-13
**Status:** Approved
**Author:** Claude (Sonnet 4.6)

## Overview

Integrate the existing `ai-gateway-service` with `ai-market-studio` backend to centralize LLM provider management, enable cost optimization through multi-provider routing, and improve observability across all AI model calls.

## Background

### Current State
- **ai-market-studio backend** calls OpenAI API directly using the OpenAI SDK
- API keys are managed in backend Kubernetes secrets
- No ability to route to alternative providers (DeepSeek) without code changes
- No centralized monitoring of LLM usage

### Deployed Infrastructure
- **ai-gateway-service**: Already deployed on GKE in `ai-gateway` namespace
  - ClusterIP: `34.118.231.104`
  - Internal endpoint: `http://ai-gateway.ai-gateway.svc.cluster.local`
  - Provides OpenAI-compatible `/v1/chat/completions` API
  - Routes to OpenAI (`gpt-4o`, `gpt-4o-mini`) or DeepSeek (`deepseek-chat`)
  - Manages API keys internally via Kubernetes secrets

## Goals

1. **Centralize key management** — Remove OpenAI API keys from backend, manage only in gateway
2. **Enable dynamic model selection** — Backend can choose between `gpt-4o`, `gpt-4o-mini`, or `deepseek-chat` per request
3. **Zero code changes to agent logic** — Maintain OpenAI SDK compatibility
4. **Easy rollback** — Configuration-only change, can revert instantly
5. **Preserve local dev workflow** — Developers can still test with direct OpenAI or local gateway

## Non-Goals

- Smart model routing based on query complexity (future enhancement)
- Gateway code changes or custom routing logic
- Frontend changes (frontend only calls backend API)
- Changes to tool definitions or agent prompt

## Architecture

### Current Flow
```
┌─────────────────────┐
│  ai-market-studio   │
│  backend            │────────▶ api.openai.com
│  (FastAPI)          │
└─────────────────────┘
```

### New Flow
```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────┐
│  ai-market-studio   │────▶│  AI Gateway      │────▶│  OpenAI     │
│  backend            │     │  ClusterIP:80    │     │             │
│  (FastAPI)          │     └──────────────────┘     └─────────────┘
└─────────────────────┘            │
                                   │ (routes by model name)
                                   ▼
                             ┌─────────────┐
                             │  DeepSeek   │
                             └─────────────┘
```

### Integration Points

**Backend → Gateway:**
- Protocol: HTTP/1.1
- Endpoint: `http://ai-gateway.ai-gateway.svc.cluster.local/v1/chat/completions`
- Authentication: None required (gateway is internal-only ClusterIP)
- Request format: OpenAI-compatible JSON (no changes to existing code)

**Model Routing (handled by gateway):**
- `gpt-4o` → OpenAI GPT-4o
- `gpt-4o-mini` → OpenAI GPT-4o-mini
- `deepseek-chat` → DeepSeek Chat

## Detailed Design

### 1. Configuration Changes

#### Backend Config (`backend/config.py`)

Add `openai_base_url` field to `Settings` class:

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    openai_api_key: SecretStr
    openai_base_url: str = "https://api.openai.com/v1"  # NEW: configurable base URL
    openai_model: str = "gpt-4o"

    # ... rest unchanged
```

**Rationale:**
- Default to direct OpenAI for backward compatibility
- Allows local dev to work without gateway
- Can be overridden via environment variable in GKE

#### Kubernetes ConfigMap (`k8s/configmap.yaml`)

Add gateway URL:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-market-studio-config
data:
  USE_MOCK_CONNECTOR: "true"
  USE_MOCK_NEWS_CONNECTOR: "false"
  OPENAI_BASE_URL: "http://ai-gateway.ai-gateway.svc.cluster.local/v1"  # NEW
  OPENAI_MODEL: "gpt-4o"
  CORS_ORIGINS: "http://136.116.205.168,http://ai-market-studio-ui,http://localhost:8080"
  MAX_HISTORICAL_DAYS: "7"
  RAG_SERVICE_URL: "http://34.10.130.210"
```

#### Kubernetes Secret (`k8s/secret.yaml`)

Update to use dummy API key (gateway manages real keys):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-market-studio-secrets
type: Opaque
stringData:
  OPENAI_API_KEY: "dummy"  # Gateway doesn't validate this
  EXCHANGERATE_API_KEY: "<real-key>"
```

**Rationale:**
- OpenAI SDK requires *something* in `api_key` field
- Gateway ignores this value and uses its own managed keys
- Keeps backend code simple (no conditional logic)

### 2. Code Changes

#### Agent Client Initialization (`backend/agent/agent.py`)

Update line 79-82 to use configurable base URL:

**Before:**
```python
client = AsyncOpenAI(
    api_key=settings.openai_api_key.get_secret_value(),
    http_client=httpx.AsyncClient(trust_env=False),
)
```

**After:**
```python
client = AsyncOpenAI(
    api_key=settings.openai_api_key.get_secret_value(),
    base_url=settings.openai_base_url,  # NEW: use configured URL
    http_client=httpx.AsyncClient(trust_env=False),
)
```

**That's it.** No other code changes needed.

### 3. Model Selection Strategy

The backend can dynamically select models by changing `settings.openai_model`:

**Current default:** `gpt-4o`

**Available options:**
- `gpt-4o` — High-capability general purpose (OpenAI)
- `gpt-4o-mini` — Fast, cost-effective (OpenAI)
- `deepseek-chat` — Reasoning-heavy workloads, cost savings (DeepSeek)

**How to change:**
1. Update `OPENAI_MODEL` in `k8s/configmap.yaml`
2. Rolling restart: `kubectl rollout restart deployment/ai-market-studio`

**Future enhancement:** Add smart routing logic in backend to choose model based on query complexity (not in this design).

### 4. Local Development Workflow

Developers have two options:

**Option A: Direct OpenAI (default)**
```bash
# backend/.env
OPENAI_API_KEY=sk-real-key-here
OPENAI_BASE_URL=https://api.openai.com/v1
```

**Option B: Local Gateway**
```bash
# Terminal 1: Run gateway locally
cd ai-gateway-service
export OPENAI_API_KEY=sk-real-key-here
export DEEPSEEK_API_KEY=sk-deepseek-key-here
python -m app.main

# Terminal 2: Run backend pointing to local gateway
cd ai-market-studio
# backend/.env
OPENAI_API_KEY=dummy
OPENAI_BASE_URL=http://localhost:4000/v1
```

No code changes needed to switch between modes.

## Deployment Plan

### Phase 1: Code & Config Changes

1. Update `backend/config.py` — add `openai_base_url` field
2. Update `backend/agent/agent.py` — use `settings.openai_base_url`
3. Update `k8s/configmap.yaml` — add `OPENAI_BASE_URL` pointing to gateway
4. Update `k8s/secret.yaml` — set `OPENAI_API_KEY=dummy`

### Phase 2: Build & Push

```bash
cd ai-market-studio

# Build with multi-stage Docker (preserves layer cache)
docker build -t gcr.io/gen-lang-client-0896070179/ai-market-studio:latest .

# Push to GCR
docker push gcr.io/gen-lang-client-0896070179/ai-market-studio:latest
```

### Phase 3: Deploy to GKE

```bash
# Apply updated ConfigMap and Secret
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml

# Rolling restart to pick up changes
kubectl rollout restart deployment/ai-market-studio
kubectl rollout status deployment/ai-market-studio

# Verify pods are running
kubectl get pods -l app=ai-market-studio
```

### Phase 4: Verification

**1. Check backend logs:**
```bash
kubectl logs -l app=ai-market-studio --tail=50 -f
```

Look for:
- No OpenAI authentication errors
- Successful chat completions
- Tool calls working normally

**2. Test chat endpoint:**
```bash
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What is the EUR/USD rate?",
    "history": []
  }'
```

Expected: Normal response with FX data.

**3. Check gateway logs:**
```bash
kubectl -n ai-gateway logs -l app=ai-gateway --tail=50 -f
```

Look for:
- Incoming requests from `ai-market-studio` backend
- Successful routing to OpenAI
- No 4xx/5xx errors

**4. Test model switching:**
```bash
# Change to gpt-4o-mini
kubectl patch configmap ai-market-studio-config \
  --patch '{"data":{"OPENAI_MODEL":"gpt-4o-mini"}}'

kubectl rollout restart deployment/ai-market-studio

# Test again
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello", "history": []}'
```

Expected: Response generated by `gpt-4o-mini` (check gateway logs for model name).

## Rollback Plan

If issues occur, revert to direct OpenAI immediately:

```bash
# Revert ConfigMap
kubectl patch configmap ai-market-studio-config \
  --patch '{"data":{"OPENAI_BASE_URL":"https://api.openai.com/v1"}}'

# Restore real OpenAI key in secret
kubectl patch secret ai-market-studio-secrets \
  --patch '{"stringData":{"OPENAI_API_KEY":"sk-real-key-here"}}'

# Rolling restart
kubectl rollout restart deployment/ai-market-studio
```

**No code rollback needed** — the change is backward-compatible.

## Testing Strategy

### Unit Tests

No new unit tests required. Existing tests in `backend/tests/unit/` will pass unchanged because:
- Tests inject a mock `AsyncOpenAI` client
- `base_url` parameter doesn't affect mock behavior

### Integration Tests

Update `backend/tests/e2e/test_chat_api.py` to verify gateway integration:

```python
@pytest.mark.asyncio
async def test_chat_via_gateway():
    """Verify backend can call gateway successfully."""
    # Set OPENAI_BASE_URL to gateway endpoint
    # Make chat request
    # Assert response is valid
    # Check gateway logs for incoming request
```

### Manual Testing Checklist

- [ ] Chat endpoint returns valid responses
- [ ] Tool calls (get_fx_rate, get_historical_rates, etc.) work normally
- [ ] Dashboard generation works
- [ ] News fetching works
- [ ] RAG queries work
- [ ] PDF export works
- [ ] Frontend UI displays responses correctly
- [ ] Gateway logs show incoming requests
- [ ] Model switching works (change ConfigMap, restart, test)

## Error Handling

### Gateway Unavailable

**Scenario:** Gateway pod is down or unreachable.

**Behavior:**
- OpenAI SDK will raise `httpx.ConnectError`
- Backend catches this in `run_agent()` and returns 500 error
- Frontend displays error message to user

**Mitigation:**
- Gateway has 2 replicas for high availability
- Kubernetes will restart failed pods automatically
- If both replicas fail, rollback to direct OpenAI

### Invalid Model Name

**Scenario:** Backend requests a model not configured in gateway (e.g., `gpt-5`).

**Behavior:**
- Gateway returns 400 error: "Model not found"
- Backend catches this and returns error to user

**Mitigation:**
- Only use models listed in gateway's `config.yaml`
- Add validation in backend config to restrict `OPENAI_MODEL` to known values (future enhancement)

### Gateway Timeout

**Scenario:** Gateway takes too long to respond (>30s).

**Behavior:**
- OpenAI SDK raises `httpx.ReadTimeout`
- Backend returns 500 error

**Mitigation:**
- Gateway has reasonable timeout settings (30s default)
- If timeouts persist, investigate gateway performance or upstream provider issues

## Observability

### Metrics to Monitor

**Backend:**
- Chat endpoint latency (should remain similar)
- Error rate (should not increase)
- Tool call success rate

**Gateway:**
- Request count by model
- Latency by provider (OpenAI vs DeepSeek)
- Error rate by provider
- Token usage by model

### Logging

**Backend logs:**
```
INFO: Tool call: get_fx_rate args={'base': 'EUR', 'target': 'USD'}
```

**Gateway logs:**
```
INFO: POST /v1/chat/completions model=gpt-4o tokens=150 latency=1.2s provider=openai
```

### Alerts (Future)

- Gateway error rate > 5%
- Gateway latency > 5s (p95)
- Backend → Gateway connection failures

## Security Considerations

### API Key Management

**Before:** OpenAI keys stored in `ai-market-studio-secrets`
**After:** OpenAI keys stored only in `ai-gateway-secrets`

**Benefit:** Reduced key sprawl, single point of rotation.

### Network Security

- Gateway is ClusterIP (internal-only), not exposed to internet
- Backend → Gateway traffic stays within GKE cluster
- No additional firewall rules needed

### Secrets Rotation

To rotate OpenAI API key:

```bash
# Update gateway secret
kubectl -n ai-gateway patch secret ai-gateway-secrets \
  --patch '{"stringData":{"OPENAI_API_KEY":"sk-new-key"}}'

# Rolling restart gateway
kubectl -n ai-gateway rollout restart deployment/ai-gateway
```

Backend doesn't need to be restarted (it uses dummy key).

## Future Enhancements

### 1. Smart Model Routing

Add logic in backend to choose model based on query complexity:

```python
def select_model(message: str, tool_calls: int) -> str:
    if tool_calls > 2 or len(message) > 500:
        return "gpt-4o"  # Complex queries
    return "gpt-4o-mini"  # Simple queries
```

### 2. Cost Tracking

Add per-request cost calculation based on token usage and model pricing.

### 3. A/B Testing

Route a percentage of traffic to DeepSeek to compare quality vs cost.

### 4. Fallback Logic

If primary provider fails, automatically retry with fallback provider.

## Success Criteria

- [ ] Backend successfully calls gateway for all chat requests
- [ ] All existing features work unchanged (chat, dashboard, news, RAG, PDF export)
- [ ] Gateway logs show incoming requests from backend
- [ ] Model switching works by changing ConfigMap
- [ ] Rollback to direct OpenAI works in <2 minutes
- [ ] No increase in error rate or latency
- [ ] Local dev workflow remains simple

## References

- [ai-gateway-service README](../../../ai-gateway-service/README.md)
- [OpenAI SDK Documentation](https://github.com/openai/openai-python)
- [LiteLLM Proxy Documentation](https://docs.litellm.ai/docs/proxy/quick_start)
