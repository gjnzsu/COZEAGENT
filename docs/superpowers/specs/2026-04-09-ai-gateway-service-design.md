# AI Gateway Service — Design Spec

## Context

Multiple AI services (ai-market-studio, AI Requirement Tool, etc.) independently call LLM providers (OpenAI, DeepSeek) with hardcoded API keys and no unified observability. We need a common AI Gateway that acts as a single entry point for all LLM calls.

**Goal:** Build ai-gateway-service as the shared gateway. Observability layer (ai-sre-observability) will follow in a separate phase.

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  AI Services    │     │  AI Gateway      │     │  LLM Providers  │
│  ai-market-     │────▶│  LiteLLM         │────▶│  OpenAI         │
│  studio, etc.   │     │  GKE             │     │  DeepSeek       │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

- **LiteLLM** — unified proxy for OpenAI + DeepSeek; handles retries, timeouts, load balancing
- **GKE** — same cluster as existing services; unified networking, monitoring, and security policies
- **OpenTelemetry** — auto-instrumented via LiteLLM's native OTel hooks; exports to OTel collector (future)
- **No auth in v1** — internal services only, network-level access control

---

## Repository

- **ai-gateway-service** (already cloned locally at `c:/SourceCode/../ai-gateway-service`)
- **ai-sre-observability** (future work)

---

## Functionality

### Core Features (v1)

1. **Unified OpenAI-compatible endpoint**
   - POST `/v1/chat/completions` — routes to OpenAI or DeepSeek based on `model` param
   - POST `/v1/completions` — passthrough for completion models
   - GET `/v1/models` — list available models

2. **Model routing**
   - `gpt-4o-*`, `gpt-4-turbo-*`, `gpt-3.5-turbo-*` → OpenAI
   - `deepseek-*` → DeepSeek
   - Configurable in `config.yaml`

3. **API key management**
   - All API keys stored in **GCP Secret Manager**
   - Keys injected as environment variables at runtime
   - No hardcoded keys in code or config files

4. **Health check**
   - GET `/health` — returns `{"status": "ok"}` for GKE readiness probe
   - GET `/readiness` — checks downstream provider connectivity

5. **Observability hooks**
   - LiteLLM emits OTel traces/spans for every request
   - Logs to Cloud Logging (stdout → GKE → Cloud Logging)
   - Metrics: request count, latency, error rate, token usage (where exposed by providers)

### What's NOT in v1

- Per-service API key auth or rate limiting
- Request/response caching
- Custom routing rules beyond model prefix matching
- Observability dashboard (deferred to ai-sre-observability)

---

## Configuration

### `config.yaml`

```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
  - model_name: deepseek-chat
    litellm_params:
      model: deepseek/deepseek-chat

environment: gke
port: 4000
```

### Environment Variables

| Variable | Source | Purpose |
|---|---|---|
| `OPENAI_API_KEY` | Secret Manager | OpenAI API key |
| `DEEPSEEK_API_KEY` | Secret Manager | DeepSeek API key |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Secret Manager | OTel collector endpoint (future) |

---

## Data Flow

1. Consumer service calls `https://<gateway-url>/v1/chat/completions` with OpenAI-compatible body
2. LiteLLM reads `model` param, routes to correct provider
3. Response returned in OpenAI-compatible format
4. OTel span logged for the request (trace_id extracted from response headers)
5. Errors return in OpenAI error format with appropriate HTTP status

---

## Deployment (GKE)

- **Dockerfile**: LiteLLM base image + config + health check
- **cloudbuild.yaml**: Build + push to Artifact Registry
- **Kubernetes manifests** (`k8s/`): Deployment + Service + HPA + Secret references
- **Secrets**: Referenced via Kubernetes Secret — no secret files in container image
- **Replicas**: 2 (ensure availability; adjust based on load)
- **Resource limits**: Set CPU/memory limits in Deployment manifest

---

## Testing

- **Unit**: LiteLLM config loads correctly, model routing logic works
- **Integration**: Call gateway endpoint, verify it routes to correct provider and returns valid response
- **Smoke test**: `curl` against `/health` and `/v1/models`

---

## File Structure

```
ai-gateway-service/
├── Dockerfile
├── config.yaml
├── requirements.txt
├── app/
│   └── main.py          # Optional: thin wrapper or custom routes if needed
├── tests/
│   ├── test_routing.py
│   └── test_health.py
├── cloudbuild.yaml
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── secret.yaml      # References GCP Secret Manager
└── README.md
```

---

## Dependencies

- `litellm>=1.0.0`
- `python-dotenv>=1.0.0`
- `httpx` (for health check downstream probes)

---

## Next Steps

1. Implement ai-gateway-service (this spec)
2. Deploy to GKE (existing cluster)
3. Smoke test with one consumer (e.g., ai-market-studio)
4. Then build ai-sre-observability (OTel collector + Prometheus + Grafana)
