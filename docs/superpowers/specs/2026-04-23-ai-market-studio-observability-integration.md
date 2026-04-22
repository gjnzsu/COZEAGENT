# AI Market Studio + AI SRE Observability Integration - Design Specification

**Date:** 2026-04-23
**Author:** Claude (Opus 4.6)
**Status:** Approved

## Executive Summary

Integration of AI SRE Observability Platform into AI Market Studio to provide real-time LLM cost tracking, token usage monitoring, and performance visibility through Grafana dashboards.

**Approach:** Wrapper-based tracking of entire agent conversations (one metric per user query) with observability service deployed first, followed by SDK integration.

**Timeline:** 1-2 days for complete integration and dashboard setup.

## Problem Statement

### Current Pain Points

1. **No LLM cost visibility** - Token usage and costs are invisible; no budget tracking for GPT-4o calls
2. **No performance monitoring** - Cannot see agent conversation latency or identify expensive queries
3. **No error tracking** - LLM API errors are logged but not aggregated or visualized

### Success Criteria

- Real-time LLM cost tracking by model (gpt-4o, gpt-4o-mini, deepseek-chat)
- Token usage trends visible in Grafana dashboards
- Cost per user query metrics for business analysis
- <10ms performance overhead from SDK
- Graceful degradation if observability service is down

## Architecture Overview

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                    User Browser                              │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              AI Market Studio Backend                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  /api/chat endpoint                                   │  │
│  │    ↓                                                  │  │
│  │  run_agent() ← Wrapped with observability tracking   │  │
│  │    │                                                  │  │
│  │    ├─ Round 1: LLM call (accumulate tokens)          │  │
│  │    ├─ Round 2: LLM call (accumulate tokens)          │  │
│  │    └─ Round N: LLM call (accumulate tokens)          │  │
│  │         ↓                                             │  │
│  │    Send aggregated metric (total tokens, duration)   │  │
│  └──────────────────────────────────────────────────────┘  │
│                     │                                        │
│                     │ Async batch (every 5s)                │
│                     ▼                                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  ObservabilityClient (SDK)                           │  │
│  │  - Batches metrics                                   │  │
│  │  - Fire-and-forget                                   │  │
│  │  - Graceful degradation                              │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP POST /ingest
                     ▼
┌─────────────────────────────────────────────────────────────┐
│         AI SRE Observability Service                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  POST /ingest                                         │  │
│  │    ↓                                                  │  │
│  │  Calculate cost (tokens × pricing)                   │  │
│  │    ↓                                                  │  │
│  │  Update Prometheus metrics:                          │  │
│  │    - llm_requests_total                              │  │
│  │    - llm_tokens_total                                │  │
│  │    - llm_cost_usd_total                              │  │
│  │    - llm_request_duration_seconds                    │  │
│  └──────────────────────────────────────────────────────┘  │
│                     │                                        │
│                     │ GET /metrics (Prometheus scrape)       │
│                     ▼                                        │
└─────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Prometheus                                │
│  - Scrapes every 15s                                         │
│  - Stores time-series metrics                                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Grafana                                   │
│  - LLM Cost & Usage Dashboard                                │
│  - Service Overview Dashboard                                │
│  - Request Tracing Dashboard                                 │
└─────────────────────────────────────────────────────────────┘
```

### Communication Flow

1. User sends query to `/api/chat`
2. `run_agent()` wraps entire conversation with observability tracking
3. Agent makes 1-5 LLM calls (tool rounds), accumulating tokens
4. SDK sends aggregated metric (total tokens, duration, cost) to observability service
5. Observability service calculates cost and updates Prometheus metrics
6. Prometheus scrapes metrics every 15 seconds
7. Grafana dashboards visualize cost, usage, and performance

## Component 1: Observability Service Deployment

### Service Configuration

**Deployment Specifications:**
- **Image:** `gcr.io/gen-lang-client-0896070179/ai-sre-observability:latest`
- **Namespace:** `default` (same as ai-market-studio)
- **Replicas:** 1 (MVP - can scale to 2+ for production)
- **Resources:**
  - Requests: 256Mi memory, 200m CPU
  - Limits: 512Mi memory, 500m CPU
- **Port:** 8080
- **Service Type:** ClusterIP (internal only)
- **Internal URL:** `http://ai-sre-observability.default.svc.cluster.local:8080`

### Endpoints

1. **POST /ingest** - Receives metrics from SDK clients
2. **GET /metrics** - Prometheus scrape endpoint (text format)
3. **GET /health** - Health check (returns tracked services count)
4. **GET /services** - List all tracked services with last_seen timestamps

### Pricing Configuration

LLM pricing data stored in ConfigMap (`k8s/configmap.yaml`):

```yaml
pricing:
  openai:
    gpt-4o:
      prompt: 0.000005      # $5 per 1M tokens
      completion: 0.000015  # $15 per 1M tokens
    gpt-4o-mini:
      prompt: 0.00000015    # $0.15 per 1M tokens
      completion: 0.0000006 # $0.60 per 1M tokens
  deepseek:
    deepseek-chat:
      prompt: 0.00000014    # $0.14 per 1M tokens
      completion: 0.00000028 # $0.28 per 1M tokens
```

Cost calculation:
```python
cost = (prompt_tokens / 1_000_000) * pricing["prompt"] +
       (completion_tokens / 1_000_000) * pricing["completion"]
```

### Deployment Commands

```bash
# Build and push image
cd ai-sre-observability/service
docker build -t gcr.io/gen-lang-client-0896070179/ai-sre-observability:latest .
docker push gcr.io/gen-lang-client-0896070179/ai-sre-observability:latest

# Deploy to GKE
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Verify deployment
kubectl get pods -l app=ai-sre-observability
kubectl logs -l app=ai-sre-observability --tail=50
```

### Verification

```bash
# Port-forward for testing
kubectl port-forward svc/ai-sre-observability 8080:8080

# Test health endpoint
curl http://localhost:8080/health
# Expected: {"status":"ok","services_tracked":[],"metrics_received_last_minute":0}

# Test metrics endpoint
curl http://localhost:8080/metrics
# Expected: Prometheus text format (empty initially)

# Test manual metric ingestion
curl -X POST http://localhost:8080/ingest \
  -H "Content-Type: application/json" \
  -d '{
    "service_name": "test-service",
    "metric_type": "llm_call",
    "trace_id": "test-123",
    "timestamp": "2026-04-23T10:00:00Z",
    "data": {
      "provider": "openai",
      "model": "gpt-4o",
      "prompt_tokens": 100,
      "completion_tokens": 50,
      "duration_seconds": 1.5,
      "status": "success"
    }
  }'

# Verify metric appears
curl http://localhost:8080/metrics | grep llm_requests_total
```

## Component 2: SDK Integration into AI Market Studio

### Installation

**Add to `backend/requirements.txt`:**
```
ai-sre-observability-sdk==0.1.0
```

For development, install from local path:
```bash
cd ai-sre-observability/sdk
pip install -e .
```

For production, install from built wheel:
```bash
cd ai-sre-observability/sdk
python setup.py bdist_wheel
pip install dist/ai_sre_observability_sdk-0.1.0-py3-none-any.whl
```

### Initialization

**Modify `backend/main.py` (FastAPI startup):**

```python
import os
from ai_sre_observability import setup_observability

@app.on_event("startup")
async def startup_event():
    """Initialize application on startup."""
    # Existing startup code...

    # Initialize observability
    observability_url = os.getenv(
        "OBSERVABILITY_URL",
        "http://ai-sre-observability.default.svc.cluster.local:8080"
    )

    try:
        setup_observability(
            service_name="ai-market-studio",
            observability_url=observability_url,
            batch_interval=5.0,  # Send metrics every 5 seconds
            timeout=5.0
        )
        logger.info(f"Observability initialized: {observability_url}")
    except Exception as e:
        logger.warning(f"Failed to initialize observability: {e}")
        # Continue without observability - graceful degradation
```

### Agent Instrumentation

**Modify `backend/agent/agent.py`:**

```python
from ai_sre_observability import get_client

async def run_agent(
    message: str,
    history: Optional[list[dict]] = None,
    connector: Optional[MarketDataConnector] = None,
    client: Optional[AsyncOpenAI] = None,
    news_connector: Optional[NewsConnectorBase] = None,
) -> dict:
    """Run the GPT-4o function-calling agent loop with observability tracking."""

    # Get observability client (graceful degradation)
    try:
        obs = get_client()
    except RuntimeError:
        obs = None
        logger.warning("Observability not initialized, skipping metrics")

    # Initialize OpenAI client
    if client is None:
        import httpx
        client = AsyncOpenAI(
            api_key=settings.openai_api_key.get_secret_value(),
            base_url=settings.openai_base_url,
            http_client=httpx.AsyncClient(trust_env=False),
        )

    # Build messages
    messages: list[ChatCompletionMessageParam] = [
        {"role": "system", "content": SYSTEM_PROMPT},
    ]
    if history:
        messages.extend(history)
    messages.append({"role": "user", "content": message})

    last_tool_used: Optional[str] = None
    last_tool_data = None
    total_prompt_tokens = 0
    total_completion_tokens = 0

    # Track entire agent conversation
    if obs:
        async with obs.track_llm_call(
            provider="openai",
            model=settings.openai_model
        ) as tracker:
            # Agent loop (existing code)
            for _ in range(MAX_TOOL_ROUNDS):
                logger.info(f"[Agent] Making request with model: {settings.openai_model}")
                response = await client.chat.completions.create(
                    model=settings.openai_model,
                    messages=messages,
                    tools=TOOL_DEFINITIONS,
                )

                # Accumulate tokens
                if response.usage:
                    total_prompt_tokens += response.usage.prompt_tokens
                    total_completion_tokens += response.usage.completion_tokens

                # ... existing tool call logic (unchanged) ...
                # [All existing code for handling tool calls, building messages, etc.]

            # Set accumulated totals
            tracker.prompt_tokens = total_prompt_tokens
            tracker.completion_tokens = total_completion_tokens
    else:
        # No observability - run agent normally (existing code)
        for _ in range(MAX_TOOL_ROUNDS):
            response = await client.chat.completions.create(
                model=settings.openai_model,
                messages=messages,
                tools=TOOL_DEFINITIONS,
            )
            # ... existing logic ...

    return {
        "reply": final_reply,
        "data": last_tool_data,
        "tool_used": last_tool_used
    }
```

**Key Implementation Details:**
- Wrap entire agent loop with `obs.track_llm_call()` context manager
- Accumulate tokens across all LLM rounds (1-5 calls per user query)
- Set final totals on tracker before context manager exits
- Graceful degradation: if observability not initialized, run agent normally
- No changes to existing tool call logic or message handling

## Component 3: Kubernetes Configuration

### Environment Variables

**Add to `ai-market-studio` deployment (`k8s/deployment.yaml`):**

```yaml
env:
- name: OBSERVABILITY_URL
  value: "http://ai-sre-observability.default.svc.cluster.local:8080"
```

### Service Discovery

The SDK automatically discovers the observability service via the internal Kubernetes DNS name. If the service is down, the SDK gracefully degrades (logs warning, continues operation).

### Deployment Commands

```bash
# Build and push new ai-market-studio image with SDK
cd ai-market-studio
docker build -t gcr.io/gen-lang-client-0896070179/ai-market-studio:latest .
docker push gcr.io/gen-lang-client-0896070179/ai-market-studio:latest

# Update deployment with OBSERVABILITY_URL env var
kubectl apply -f k8s/deployment.yaml

# Rolling restart
kubectl rollout restart deployment/ai-market-studio
kubectl rollout status deployment/ai-market-studio
```

### Verification

```bash
# Check ai-market-studio logs for observability initialization
kubectl logs -l app=ai-market-studio --tail=50 | grep -i observability
# Expected: "Observability initialized: http://ai-sre-observability..."

# Make a test query
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is EUR/USD?", "history": []}'

# Check observability service received metrics
kubectl port-forward svc/ai-sre-observability 8080:8080
curl http://localhost:8080/services
# Expected: {"services":[{"name":"ai-market-studio","last_seen":"...","metrics_count":1}]}

curl http://localhost:8080/metrics | grep ai-market-studio
# Expected: llm_requests_total{service="ai-market-studio",...} 1
```

## Component 4: Metrics & Dashboards

### Metrics Exposed

Once integrated, the observability service exposes these metrics for ai-market-studio:

```prometheus
# Total LLM requests (one per user query)
llm_requests_total{service="ai-market-studio",provider="openai",model="gpt-4o",status="success"} 1234

# Total tokens used
llm_tokens_total{service="ai-market-studio",provider="openai",model="gpt-4o",token_type="prompt"} 150000
llm_tokens_total{service="ai-market-studio",provider="openai",model="gpt-4o",token_type="completion"} 80000
llm_tokens_total{service="ai-market-studio",provider="openai",model="gpt-4o",token_type="total"} 230000

# Total cost in USD
llm_cost_usd_total{service="ai-market-studio",provider="openai",model="gpt-4o"} 12.45

# Request duration (histogram)
llm_request_duration_seconds{service="ai-market-studio",provider="openai",model="gpt-4o"} 2.3

# Errors (if any)
llm_errors_total{service="ai-market-studio",provider="openai",model="gpt-4o",error_type="RateLimitError"} 5
```

### Grafana Dashboard Views

**LLM Cost & Usage Dashboard** (`grafana/llm-cost-usage.json`):
1. **Total LLM Cost** - Cumulative cost across all providers
2. **Cost by Provider** - Pie chart showing cost distribution
3. **Cost by Model** - Bar gauge showing per-model costs
4. **LLM Request Rate** - Request throughput by provider and model
5. **Token Usage** - Token consumption rate (input/output)
6. **LLM Request Duration p95** - 95th percentile latency
7. **LLM Error Rate** - Error rate by provider and error type
8. **Cost Rate** - Real-time cost accumulation rate

**Service Overview Dashboard** (`grafana/service-overview.json`):
1. **Service Health** - Gauge showing service up/down status
2. **HTTP Request Rate** - Request throughput over time
3. **Active Services** - Count of currently running services
4. **HTTP Request Duration (p95)** - 95th percentile response times
5. **HTTP Requests In-Flight** - Current concurrent requests
6. **Error Rate (5xx)** - Server error rate with alerting

**Request Tracing Dashboard** (`grafana/request-tracing.json`):
1. **Request Flow by Service** - Node graph showing service-to-service flow
2. **Trace ID Search** - Table for searching traces by trace_id
3. **Request Latency by Service** - Heatmap showing latency distribution
4. **Top Slowest Requests** - Table of top 10 slowest LLM requests
5. **Request Success Rate** - Success rate by service over time
6. **Concurrent Requests** - Number of concurrent requests per service

### Dashboard Import

```bash
# Import via ConfigMap (Kubernetes)
kubectl create configmap grafana-dashboard-llm-cost \
  --from-file=ai-sre-observability/grafana/llm-cost-usage.json \
  -n monitoring

kubectl label configmap grafana-dashboard-llm-cost \
  grafana_dashboard=1 \
  -n monitoring

kubectl create configmap grafana-dashboard-service-overview \
  --from-file=ai-sre-observability/grafana/service-overview.json \
  -n monitoring

kubectl label configmap grafana-dashboard-service-overview \
  grafana_dashboard=1 \
  -n monitoring

kubectl create configmap grafana-dashboard-request-tracing \
  --from-file=ai-sre-observability/grafana/request-tracing.json \
  -n monitoring

kubectl label configmap grafana-dashboard-request-tracing \
  grafana_dashboard=1 \
  -n monitoring

# Restart Grafana to load dashboards
kubectl rollout restart deployment/grafana -n monitoring
```

## Component 5: Error Handling & Graceful Degradation

### SDK Error Handling

The SDK is designed to **never break the main application**:

**Scenario 1: Observability service is down**
```python
# SDK behavior:
- Logs warning: "Failed to send metrics: Connection refused"
- Continues batching metrics in memory (up to buffer limit)
- Retries on next batch interval (5 seconds)
- Application continues normally
```

**Scenario 2: Observability not initialized**
```python
# Agent code:
try:
    obs = get_client()
except RuntimeError:
    obs = None
    logger.warning("Observability not initialized, skipping metrics")

# Agent runs normally without tracking
```

**Scenario 3: Network timeout**
```python
# SDK behavior:
- Request times out after 5 seconds
- Logs warning: "Metric submission timeout"
- Drops batch and continues
- Application is not blocked
```

### Agent Error Tracking

If the agent itself fails (e.g., OpenAI API error), the SDK automatically tracks it:

```python
async with obs.track_llm_call(...) as tracker:
    try:
        response = await client.chat.completions.create(...)
    except Exception as e:
        # SDK automatically sets:
        # tracker.status = "error"
        # tracker.error_type = "RateLimitError" (or whatever exception type)
        raise
```

This appears in Grafana as:
```prometheus
llm_errors_total{service="ai-market-studio",provider="openai",model="gpt-4o",error_type="RateLimitError"} 1
```

### Performance Impact

- **Latency overhead:** <10ms per agent conversation (async, non-blocking)
- **Memory footprint:** ~10MB per service (batching buffer)
- **CPU overhead:** <1%
- **Network:** Batched requests every 5s (reduces HTTP overhead)

## Component 6: Deployment Timeline

### Phase 1: Deploy Observability Service (Day 1)

**Tasks:**
- [ ] Build and push observability service Docker image
- [ ] Deploy to GKE (ConfigMap, Deployment, Service)
- [ ] Verify health endpoint returns 200 OK
- [ ] Verify metrics endpoint returns Prometheus format
- [ ] Test manual metric ingestion via curl
- [ ] Configure Prometheus to scrape observability service

**Estimated time:** 2-3 hours

### Phase 2: Integrate SDK into AI Market Studio (Day 1-2)

**Tasks:**
- [ ] Install SDK package in ai-market-studio
- [ ] Add observability initialization to `backend/main.py`
- [ ] Wrap agent loop in `backend/agent/agent.py` with tracking
- [ ] Add OBSERVABILITY_URL to deployment env vars
- [ ] Test locally with port-forward
- [ ] Build and push new ai-market-studio image
- [ ] Deploy to GKE with rolling restart
- [ ] Verify metrics appear in observability service

**Estimated time:** 3-4 hours

### Phase 3: Grafana Dashboard Setup (Day 2)

**Tasks:**
- [ ] Import LLM Cost & Usage dashboard
- [ ] Import Service Overview dashboard
- [ ] Import Request Tracing dashboard
- [ ] Verify all panels render correctly
- [ ] Test filtering by service (ai-market-studio)
- [ ] Document dashboard usage

**Estimated time:** 1-2 hours

**Total estimated time:** 6-9 hours (1-2 days)

## Success Criteria

### Technical Metrics

- [ ] Observability service deployed and healthy (uptime > 99%)
- [ ] AI Market Studio sending metrics successfully (no SDK errors in logs)
- [ ] Metrics appear in Prometheus within 30 seconds of query
- [ ] All 3 Grafana dashboards rendering data correctly
- [ ] SDK overhead < 10ms per agent conversation
- [ ] No increase in ai-market-studio error rate after integration

### Business Metrics

- [ ] Can see total LLM cost for ai-market-studio in Grafana
- [ ] Can see cost breakdown by model (gpt-4o vs gpt-4o-mini)
- [ ] Can see token usage trends over time
- [ ] Can see average cost per user query
- [ ] Can identify most expensive queries via Request Tracing dashboard

### Operational Metrics

- [ ] Observability service handles 100+ metrics/minute without issues
- [ ] SDK gracefully degrades if observability service is down
- [ ] Can debug slow queries using trace_id correlation
- [ ] Dashboards update in real-time (15-30 second delay max)

## Rollback Plan

### If Integration Causes Issues

**Step 1: Disable SDK tracking**
```bash
# Remove OBSERVABILITY_URL from deployment
kubectl patch deployment ai-market-studio \
  --type=json \
  -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/env"}]'

# Rolling restart
kubectl rollout restart deployment/ai-market-studio
```

**Step 2: Revert to previous image**
```bash
# Rollback to previous deployment
kubectl rollout undo deployment/ai-market-studio

# Verify rollback
kubectl rollout status deployment/ai-market-studio
```

**Step 3: Keep observability service running**
- Observability service can stay deployed (no harm)
- Can be used for future integrations
- No cost impact (minimal resources)

## Monitoring & Alerts

### Post-Deployment Monitoring

**Week 1: Watch for issues**
- Monitor ai-market-studio logs for SDK errors
- Check observability service logs for ingestion errors
- Verify Grafana dashboards update correctly
- Monitor ai-market-studio latency (should not increase)

**Week 2+: Analyze cost trends**
- Review daily LLM costs in Grafana
- Identify expensive query patterns
- Optimize model selection (gpt-4o vs gpt-4o-mini)
- Set up cost threshold alerts if needed

### Recommended Alerts (Future)

```yaml
# Alert if daily cost exceeds threshold
- alert: HighLLMCost
  expr: increase(llm_cost_usd_total{service="ai-market-studio"}[1d]) > 50
  annotations:
    summary: "AI Market Studio LLM cost exceeded $50/day"

# Alert if error rate spikes
- alert: HighLLMErrorRate
  expr: rate(llm_errors_total{service="ai-market-studio"}[5m]) > 0.1
  annotations:
    summary: "AI Market Studio LLM error rate > 10%"
```

## Implementation Checklist

### Pre-Deployment

- [ ] Review design specification
- [ ] Verify ai-sre-observability service is built and tested
- [ ] Verify SDK package is ready (built wheel or local install)
- [ ] Backup current ai-market-studio deployment config
- [ ] Notify team of deployment window

### Phase 1: Deploy Observability Service

- [ ] Build observability service image
- [ ] Push image to GCR
- [ ] Apply ConfigMap with pricing data
- [ ] Apply Deployment manifest
- [ ] Apply Service manifest
- [ ] Verify pod is running and healthy
- [ ] Test /health endpoint
- [ ] Test /metrics endpoint
- [ ] Test manual metric ingestion
- [ ] Configure Prometheus scrape config

### Phase 2: Integrate SDK

- [ ] Install SDK in ai-market-studio locally
- [ ] Add observability initialization to main.py
- [ ] Wrap agent loop with tracking
- [ ] Test locally with port-forward
- [ ] Verify metrics appear in observability service
- [ ] Build new ai-market-studio image
- [ ] Push image to GCR
- [ ] Update deployment with OBSERVABILITY_URL
- [ ] Apply deployment manifest
- [ ] Rolling restart deployment
- [ ] Monitor logs for errors
- [ ] Test end-to-end with real query
- [ ] Verify metrics in Prometheus

### Phase 3: Setup Dashboards

- [ ] Import LLM Cost & Usage dashboard
- [ ] Import Service Overview dashboard
- [ ] Import Request Tracing dashboard
- [ ] Verify all panels show data
- [ ] Test filtering by service
- [ ] Document dashboard usage
- [ ] Share dashboard links with team

### Post-Deployment

- [ ] Monitor for 24 hours
- [ ] Review cost metrics
- [ ] Check for performance impact
- [ ] Document any issues
- [ ] Update runbook if needed

## Design Summary

This integration provides:

1. **Cost Visibility** - Track LLM spending per user query in real-time
2. **Performance Monitoring** - See token usage, latency, and error rates
3. **Graceful Degradation** - SDK never breaks the main application
4. **Easy Deployment** - Deploy observability first, integrate SDK second
5. **Grafana Dashboards** - Pre-built dashboards for cost analysis
6. **Future-Ready** - Can add HTTP metrics, business metrics later

### Key Design Decisions

- ✅ Track entire agent conversation as one metric (cost per query)
- ✅ Deploy observability service first (safer, testable independently)
- ✅ Wrapper-based tracking (minimal code changes)
- ✅ Align with existing Grafana dashboards
- ✅ Fire-and-forget SDK (no blocking, graceful degradation)

### Trade-offs

**Pros:**
- Clean cost-per-query metrics for business analysis
- Minimal code changes (wrap one function)
- Works with existing dashboards
- Easy to test and deploy incrementally
- No performance impact on main application

**Cons:**
- No visibility into individual tool rounds (can't see which tool call was expensive)
- Requires separate observability service deployment
- Adds network dependency (mitigated by graceful degradation)

### Future Enhancements

1. **HTTP Request Tracking** - Add HTTP endpoint metrics to Service Overview dashboard
2. **Business Metrics** - Track PDF exports, dashboard generations, RAG queries
3. **Individual Round Tracking** - Optional detailed tracking for debugging
4. **Cost Alerts** - Prometheus alerts for cost thresholds
5. **OpenTelemetry Migration** - Upgrade to full distributed tracing

---

**Next Steps:**
1. Review and approve this specification
2. Create implementation plan with detailed tasks
3. Begin Phase 1 deployment (observability service)

