# AI Market Studio + AI SRE Observability Integration - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate AI SRE Observability Platform into AI Market Studio to track LLM costs, token usage, and performance metrics in real-time via Grafana dashboards.

**Architecture:** Deploy observability service first (FastAPI + Prometheus metrics), then integrate SDK into ai-market-studio backend to wrap agent conversations with tracking. SDK batches metrics every 5 seconds and sends to observability service, which calculates costs and exposes Prometheus metrics for Grafana visualization.

**Tech Stack:** FastAPI, Prometheus, Grafana, Docker, GKE, Python SDK (httpx, pydantic)

---

## File Structure

### AI SRE Observability Service (already built)
- `ai-sre-observability/service/main.py` - FastAPI service (exists)
- `ai-sre-observability/service/config.py` - Config loader (exists)
- `ai-sre-observability/service/models.py` - Pydantic models (exists)
- `ai-sre-observability/service/metrics.py` - Prometheus metrics (exists)
- `ai-sre-observability/service/cost_calculator.py` - Cost calculation (exists)
- `ai-sre-observability/k8s/configmap.yaml` - Pricing config (exists)
- `ai-sre-observability/k8s/deployment.yaml` - K8s deployment (exists)
- `ai-sre-observability/k8s/service.yaml` - K8s service (exists)
- `ai-sre-observability/service/Dockerfile` - Multi-stage build (exists)

### AI SRE Observability SDK (already built)
- `ai-sre-observability/sdk/ai_sre_observability/__init__.py` - Public API (exists)
- `ai-sre-observability/sdk/ai_sre_observability/client.py` - Client (exists)
- `ai-sre-observability/sdk/ai_sre_observability/decorators.py` - Decorators (exists)
- `ai-sre-observability/sdk/ai_sre_observability/models.py` - Models (exists)
- `ai-sre-observability/sdk/ai_sre_observability/transport.py` - Transport (exists)
- `ai-sre-observability/sdk/setup.py` - Package setup (exists)

### AI Market Studio (to be modified)
- Modify: `ai-market-studio/backend/main.py` - Add observability initialization
- Modify: `ai-market-studio/backend/agent/agent.py` - Wrap agent with tracking
- Modify: `ai-market-studio/backend/requirements.txt` - Add SDK dependency
- Modify: `ai-market-studio/k8s/deployment.yaml` - Add OBSERVABILITY_URL env var
- Modify: `ai-market-studio/Dockerfile` - No changes needed (pip install handles SDK)

---

## Phase 1: Deploy Observability Service to GKE

### Task 1: Build and Push Observability Service Image

**Files:**
- Build: `ai-sre-observability/service/Dockerfile`
- Push to: `gcr.io/gen-lang-client-0896070179/ai-sre-observability:latest`

- [ ] **Step 1: Authenticate with GCR**

```bash
gcloud auth configure-docker
```

Expected: "Docker configuration file updated"

- [ ] **Step 2: Build observability service image**

```bash
cd c:/SourceCode/ai-sre-observability
docker build -t gcr.io/gen-lang-client-0896070179/ai-sre-observability:latest -f service/Dockerfile .
```

Expected: "Successfully built [image-id]"
Expected: "Successfully tagged gcr.io/gen-lang-client-0896070179/ai-sre-observability:latest"

- [ ] **Step 3: Push image to GCR**

```bash
docker push gcr.io/gen-lang-client-0896070179/ai-sre-observability:latest
```

Expected: "latest: digest: sha256:... size: ..."

- [ ] **Step 4: Verify image in GCR**

```bash
gcloud container images list --repository=gcr.io/gen-lang-client-0896070179 | grep ai-sre-observability
```

Expected: "gcr.io/gen-lang-client-0896070179/ai-sre-observability"

---

### Task 2: Deploy Observability Service to GKE

**Files:**
- Apply: `ai-sre-observability/k8s/configmap.yaml`
- Apply: `ai-sre-observability/k8s/deployment.yaml`
- Apply: `ai-sre-observability/k8s/service.yaml`

- [ ] **Step 1: Get GKE cluster credentials**

```bash
gcloud container clusters get-credentials helloworld-cluster --region us-central1 --project gen-lang-client-0896070179
```

Expected: "Fetching cluster endpoint and auth data"
Expected: "kubeconfig entry generated for helloworld-cluster"

- [ ] **Step 2: Apply ConfigMap with pricing data**

```bash
cd c:/SourceCode/ai-sre-observability
kubectl apply -f k8s/configmap.yaml
```

Expected: "configmap/ai-sre-observability-config created" or "configured"

- [ ] **Step 3: Apply Deployment manifest**

```bash
kubectl apply -f k8s/deployment.yaml
```

Expected: "deployment.apps/ai-sre-observability created" or "configured"

- [ ] **Step 4: Apply Service manifest**

```bash
kubectl apply -f k8s/service.yaml
```

Expected: "service/ai-sre-observability created" or "configured"

- [ ] **Step 5: Verify pod is running**

```bash
kubectl get pods -l app=ai-sre-observability
```

Expected: "ai-sre-observability-[hash] 1/1 Running 0 [age]"

- [ ] **Step 6: Check pod logs for startup**

```bash
kubectl logs -l app=ai-sre-observability --tail=20
```

Expected: "Starting AI SRE Observability Platform..."
Expected: "Application started successfully"

---

### Task 3: Verify Observability Service Health

**Files:**
- Test: Observability service endpoints via port-forward

- [ ] **Step 1: Port-forward observability service**

```bash
kubectl port-forward svc/ai-sre-observability 8080:8080
```

Expected: "Forwarding from 127.0.0.1:8080 -> 8080"

(Keep this running in a separate terminal for the following steps)

- [ ] **Step 2: Test health endpoint**

```bash
curl http://localhost:8080/health
```

Expected: `{"status":"ok","services_tracked":[],"metrics_received_last_minute":0}`

- [ ] **Step 3: Test metrics endpoint**

```bash
curl http://localhost:8080/metrics
```

Expected: Prometheus text format output (may be empty initially)
Expected: Contains "# HELP" and "# TYPE" lines

- [ ] **Step 4: Test manual metric ingestion**

```bash
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
```

Expected: `{"status":"success","trace_id":"test-123"}`

- [ ] **Step 5: Verify metric appears in /metrics**

```bash
curl http://localhost:8080/metrics | grep llm_requests_total
```

Expected: `llm_requests_total{service="test-service",provider="openai",model="gpt-4o",status="success"} 1`

- [ ] **Step 6: Stop port-forward**

Press Ctrl+C in the port-forward terminal

---

## Phase 2: Integrate SDK into AI Market Studio

### Task 4: Install SDK in AI Market Studio

**Files:**
- Modify: `ai-market-studio/backend/requirements.txt`

- [ ] **Step 1: Add SDK to requirements.txt**

Add this line to `ai-market-studio/backend/requirements.txt`:

```
ai-sre-observability-sdk @ file:///c:/SourceCode/ai-sre-observability/sdk
```

(For production, replace with: `ai-sre-observability-sdk==0.1.0` after publishing to PyPI)

- [ ] **Step 2: Install SDK locally for testing**

```bash
cd c:/SourceCode/ai-sre-observability/sdk
pip install -e .
```

Expected: "Successfully installed ai-sre-observability-sdk-0.1.0"

- [ ] **Step 3: Verify SDK import works**

```bash
python -c "from ai_sre_observability import setup_observability, get_client; print('SDK imported successfully')"
```

Expected: "SDK imported successfully"

---

### Task 5: Add Observability Initialization to Backend

**Files:**
- Modify: `ai-market-studio/backend/main.py:42-49`

- [ ] **Step 1: Add import at top of main.py**

Add after line 8 (`from backend.router import router`):

```python
import os
from ai_sre_observability import setup_observability
```

- [ ] **Step 2: Add observability initialization to lifespan**

Replace the `lifespan` function (lines 42-49) with:

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize connectors
    if not getattr(app.state, 'connector', None):
        app.state.connector = create_connector()
    if not getattr(app.state, 'news_connector', None):
        app.state.news_connector = create_news_connector()

    # Initialize observability
    observability_url = os.getenv(
        "OBSERVABILITY_URL",
        "http://ai-sre-observability.default.svc.cluster.local:8080"
    )

    try:
        setup_observability(
            service_name="ai-market-studio",
            observability_url=observability_url,
            batch_interval=5.0,
            timeout=5.0
        )
        logger.info(f"Observability initialized: {observability_url}")
    except Exception as e:
        logger.warning(f"Failed to initialize observability: {e}")
        # Continue without observability - graceful degradation

    logger.info("AI Market Studio started.")
    yield
    logger.info("AI Market Studio shutting down.")
```

- [ ] **Step 3: Verify syntax**

```bash
cd c:/SourceCode/ai-market-studio
python -m py_compile backend/main.py
```

Expected: No output (success)

---

### Task 6: Wrap Agent Loop with Observability Tracking

**Files:**
- Modify: `ai-market-studio/backend/agent/agent.py:1-100`

- [ ] **Step 1: Add import at top of agent.py**

Add after line 11 (`from backend.agent.tools import TOOL_DEFINITIONS, dispatch_tool, AgentError`):

```python
from ai_sre_observability import get_client
```

- [ ] **Step 2: Modify run_agent function signature (no changes needed)**

The function signature stays the same. We'll add tracking inside the function body.

- [ ] **Step 3: Add observability client initialization**

After line 76 (the docstring), add:

```python
    # Get observability client (graceful degradation)
    try:
        obs = get_client()
    except RuntimeError:
        obs = None
        logger.warning("Observability not initialized, skipping metrics")
```

- [ ] **Step 4: Add token accumulation variables**

After the `last_tool_data = None` line (around line 93), add:

```python
    total_prompt_tokens = 0
    total_completion_tokens = 0
```

- [ ] **Step 5: Wrap agent loop with tracking context**

Find the `for _ in range(MAX_TOOL_ROUNDS):` loop (around line 95).

Replace the loop with this structure:

```python
    # Track entire agent conversation
    if obs:
        async with obs.track_llm_call(
            provider="openai",
            model=settings.openai_model
        ) as tracker:
            # Agent loop
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

                # ... rest of existing agent logic (tool calls, etc.) ...
                # [Keep all existing code unchanged - just indent it]

            # Set accumulated totals
            tracker.prompt_tokens = total_prompt_tokens
            tracker.completion_tokens = total_completion_tokens
    else:
        # No observability - run agent normally
        for _ in range(MAX_TOOL_ROUNDS):
            # ... existing agent loop code ...
```

- [ ] **Step 6: Verify syntax**

```bash
cd c:/SourceCode/ai-market-studio
python -m py_compile backend/agent/agent.py
```

Expected: No output (success)

### Task 7: Test SDK Integration Locally

**Files:**
- Test: Local ai-market-studio with port-forwarded observability service

- [ ] **Step 1: Start observability service port-forward**

```bash
kubectl port-forward svc/ai-sre-observability 8080:8080
```

Expected: "Forwarding from 127.0.0.1:8080 -> 8080"

(Keep this running in a separate terminal)

- [ ] **Step 2: Set environment variable for local testing**

```bash
export OBSERVABILITY_URL=http://localhost:8080
```

- [ ] **Step 3: Start ai-market-studio backend locally**

```bash
cd c:/SourceCode/ai-market-studio
uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

Expected: "INFO: AI Market Studio started."
Expected: "INFO: Observability initialized: http://localhost:8080"

- [ ] **Step 4: Make a test query**

```bash
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is EUR/USD?", "history": []}'
```

Expected: JSON response with `reply`, `data`, `tool_used` fields

- [ ] **Step 5: Verify metrics in observability service**

```bash
curl http://localhost:8080/services
```

Expected: `{"services":[{"name":"ai-market-studio","last_seen":"...","metrics_count":1}]}`

- [ ] **Step 6: Check metrics endpoint**

```bash
curl http://localhost:8080/metrics | grep ai-market-studio
```

Expected: `llm_requests_total{service="ai-market-studio",provider="openai",model="gpt-4o",status="success"} 1`
Expected: `llm_tokens_total{service="ai-market-studio",...}`
Expected: `llm_cost_usd_total{service="ai-market-studio",...}`

- [ ] **Step 7: Stop local backend**

Press Ctrl+C in the uvicorn terminal

- [ ] **Step 8: Stop port-forward**

Press Ctrl+C in the port-forward terminal

---

### Task 8: Add OBSERVABILITY_URL to Deployment

**Files:**
- Modify: `ai-market-studio/k8s/deployment.yaml:18-33`

- [ ] **Step 1: Add env section to deployment**

Find the `ai-market-studio` container spec (around line 18).

After the `envFrom:` section (around line 26), add:

```yaml
          env:
            - name: OBSERVABILITY_URL
              value: "http://ai-sre-observability.default.svc.cluster.local:8080"
```

The full container spec should look like:

```yaml
        - name: ai-market-studio
          image: gcr.io/gen-lang-client-0896070179/ai-market-studio:latest
          ports:
            - containerPort: 8000
          envFrom:
            - configMapRef:
                name: ai-market-studio-config
            - secretRef:
                name: ai-market-studio-secrets
          env:
            - name: OBSERVABILITY_URL
              value: "http://ai-sre-observability.default.svc.cluster.local:8080"
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
```

- [ ] **Step 2: Verify YAML syntax**

```bash
cd c:/SourceCode/ai-market-studio
kubectl apply -f k8s/deployment.yaml --dry-run=client
```

Expected: "deployment.apps/ai-market-studio configured (dry run)"

---

### Task 9: Build and Deploy Updated AI Market Studio

**Files:**
- Build: `ai-market-studio/Dockerfile`
- Push to: `gcr.io/gen-lang-client-0896070179/ai-market-studio:latest`

- [ ] **Step 1: Build new ai-market-studio image**

```bash
cd c:/SourceCode/ai-market-studio
docker build -t gcr.io/gen-lang-client-0896070179/ai-market-studio:latest .
```

Expected: "Successfully built [image-id]"
Expected: "Successfully tagged gcr.io/gen-lang-client-0896070179/ai-market-studio:latest"

- [ ] **Step 2: Push image to GCR**

```bash
docker push gcr.io/gen-lang-client-0896070179/ai-market-studio:latest
```

Expected: "latest: digest: sha256:... size: ..."

- [ ] **Step 3: Apply updated deployment**

```bash
kubectl apply -f k8s/deployment.yaml
```

Expected: "deployment.apps/ai-market-studio configured"

- [ ] **Step 4: Rolling restart deployment**

```bash
kubectl rollout restart deployment/ai-market-studio
```

Expected: "deployment.apps/ai-market-studio restarted"

- [ ] **Step 5: Wait for rollout to complete**

```bash
kubectl rollout status deployment/ai-market-studio --timeout=300s
```

Expected: "deployment \"ai-market-studio\" successfully rolled out"

- [ ] **Step 6: Verify new pods are running**

```bash
kubectl get pods -l app=ai-market-studio
```

Expected: "ai-market-studio-[new-hash] 2/2 Running 0 [age]"

---

### Task 10: Verify End-to-End Integration

**Files:**
- Test: Production ai-market-studio with observability service

- [ ] **Step 1: Check ai-market-studio logs for observability init**

```bash
kubectl logs -l app=ai-market-studio -c ai-market-studio --tail=50 | grep -i observability
```

Expected: "INFO: Observability initialized: http://ai-sre-observability.default.svc.cluster.local:8080"

- [ ] **Step 2: Make a test query to production**

```bash
curl -X POST http://35.224.3.54/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is EUR/USD?", "history": []}'
```

Expected: JSON response with `reply`, `data`, `tool_used` fields

- [ ] **Step 3: Port-forward observability service**

```bash
kubectl port-forward svc/ai-sre-observability 8080:8080
```

Expected: "Forwarding from 127.0.0.1:8080 -> 8080"

- [ ] **Step 4: Check services endpoint**

```bash
curl http://localhost:8080/services
```

Expected: `{"services":[{"name":"ai-market-studio","last_seen":"2026-04-23T...","metrics_count":1}]}`

- [ ] **Step 5: Verify metrics are being collected**

```bash
curl http://localhost:8080/metrics | grep -A 5 "ai-market-studio"
```

Expected: Multiple metrics with `service="ai-market-studio"` label
Expected: `llm_requests_total`, `llm_tokens_total`, `llm_cost_usd_total`

- [ ] **Step 6: Make multiple queries to accumulate metrics**

```bash
for i in {1..5}; do
  curl -X POST http://35.224.3.54/api/chat \
    -H "Content-Type: application/json" \
    -d '{"message": "What is GBP/USD?", "history": []}' \
    -s > /dev/null
  echo "Query $i sent"
  sleep 2
done
```

Expected: "Query 1 sent" ... "Query 5 sent"

- [ ] **Step 7: Verify metrics increased**

```bash
curl http://localhost:8080/metrics | grep 'llm_requests_total{service="ai-market-studio"'
```

Expected: Counter value >= 6 (1 from step 2 + 5 from step 6)

- [ ] **Step 8: Check cost metrics**

```bash
curl http://localhost:8080/metrics | grep 'llm_cost_usd_total{service="ai-market-studio"'
```

Expected: Non-zero cost value (e.g., `llm_cost_usd_total{...} 0.0123`)

- [ ] **Step 9: Stop port-forward**

Press Ctrl+C in the port-forward terminal

---

## Phase 3: Setup Grafana Dashboards

### Task 11: Import Grafana Dashboards

**Files:**
- Import: `ai-sre-observability/grafana/llm-cost-usage.json`
- Import: `ai-sre-observability/grafana/service-overview.json`
- Import: `ai-sre-observability/grafana/request-tracing.json`

- [ ] **Step 1: Create ConfigMap for LLM Cost dashboard**

```bash
cd c:/SourceCode/ai-sre-observability
kubectl create configmap grafana-dashboard-llm-cost \
  --from-file=grafana/llm-cost-usage.json \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

Expected: "configmap/grafana-dashboard-llm-cost created" or "configured"

- [ ] **Step 2: Label ConfigMap for auto-discovery**

```bash
kubectl label configmap grafana-dashboard-llm-cost \
  grafana_dashboard=1 \
  -n monitoring \
  --overwrite
```

Expected: "configmap/grafana-dashboard-llm-cost labeled"

- [ ] **Step 3: Create ConfigMap for Service Overview dashboard**

```bash
kubectl create configmap grafana-dashboard-service-overview \
  --from-file=grafana/service-overview.json \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

Expected: "configmap/grafana-dashboard-service-overview created" or "configured"

- [ ] **Step 4: Label Service Overview ConfigMap**

```bash
kubectl label configmap grafana-dashboard-service-overview \
  grafana_dashboard=1 \
  -n monitoring \
  --overwrite
```

Expected: "configmap/grafana-dashboard-service-overview labeled"

- [ ] **Step 5: Create ConfigMap for Request Tracing dashboard**

```bash
kubectl create configmap grafana-dashboard-request-tracing \
  --from-file=grafana/request-tracing.json \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

Expected: "configmap/grafana-dashboard-request-tracing created" or "configured"

- [ ] **Step 6: Label Request Tracing ConfigMap**

```bash
kubectl label configmap grafana-dashboard-request-tracing \
  grafana_dashboard=1 \
  -n monitoring \
  --overwrite
```

Expected: "configmap/grafana-dashboard-request-tracing labeled"

- [ ] **Step 7: Restart Grafana to load dashboards**

```bash
kubectl rollout restart deployment/grafana -n monitoring
```

Expected: "deployment.apps/grafana restarted"

- [ ] **Step 8: Wait for Grafana to be ready**

```bash
kubectl rollout status deployment/grafana -n monitoring --timeout=120s
```

Expected: "deployment \"grafana\" successfully rolled out"

---

### Task 12: Verify Grafana Dashboards

**Files:**
- Verify: Grafana UI dashboards rendering data

- [ ] **Step 1: Get Grafana URL**

```bash
kubectl get svc -n monitoring | grep grafana
```

Expected: Service with external IP or LoadBalancer

(If using port-forward instead):
```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

- [ ] **Step 2: Open Grafana in browser**

Navigate to: `http://localhost:3000` (or external IP)

Expected: Grafana login page

- [ ] **Step 3: Login to Grafana**

Default credentials: admin / admin (or your configured credentials)

Expected: Grafana home page

- [ ] **Step 4: Navigate to Dashboards**

Click: Dashboards → Browse

Expected: List of dashboards

- [ ] **Step 5: Verify LLM Cost & Usage dashboard exists**

Search for: "LLM Cost"

Expected: Dashboard named "AI SRE Observability - LLM Cost & Usage"

- [ ] **Step 6: Open LLM Cost & Usage dashboard**

Click on the dashboard

Expected: Dashboard loads with panels

- [ ] **Step 7: Verify panels show data**

Check these panels:
- Total LLM Cost (should show non-zero value)
- Cost by Provider (should show "openai")
- Cost by Model (should show "gpt-4o")
- Token Usage (should show line chart with data)
- LLM Request Rate (should show requests over time)

Expected: All panels display data (not "No data")

- [ ] **Step 8: Filter by service**

Select service variable: `ai-market-studio`

Expected: Panels update to show only ai-market-studio data

- [ ] **Step 9: Verify Service Overview dashboard**

Navigate to: Dashboards → Browse → "AI SRE Observability - Service Overview"

Expected: Dashboard loads with service health, request rate, latency panels

- [ ] **Step 10: Verify Request Tracing dashboard**

Navigate to: Dashboards → Browse → "AI SRE Observability - Request Tracing"

Expected: Dashboard loads with trace search, latency heatmap, slowest requests

---

### Task 13: Configure Prometheus Scraping (if not already configured)

**Files:**
- Modify: Prometheus ConfigMap (if needed)

- [ ] **Step 1: Check if Prometheus is scraping observability service**

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
```

Navigate to: `http://localhost:9090/targets`

Expected: Target named "ai-sre-observability" with state "UP"

- [ ] **Step 2: If target is missing, add scrape config**

Edit Prometheus ConfigMap:

```bash
kubectl edit configmap prometheus-config -n monitoring
```

Add this scrape config:

```yaml
scrape_configs:
  - job_name: 'ai-sre-observability'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - default
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: ai-sre-observability
        action: keep
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
    scrape_interval: 15s
    scrape_timeout: 10s
```

- [ ] **Step 3: Reload Prometheus config**

```bash
kubectl rollout restart deployment/prometheus -n monitoring
```

Expected: "deployment.apps/prometheus restarted"

- [ ] **Step 4: Verify target appears**

Navigate to: `http://localhost:9090/targets`

Expected: "ai-sre-observability" target with state "UP"

- [ ] **Step 5: Query metrics in Prometheus**

Navigate to: `http://localhost:9090/graph`

Query: `llm_requests_total{service="ai-market-studio"}`

Expected: Time series data with values

---

### Task 14: Final Verification and Documentation

**Files:**
- Create: `ai-market-studio/docs/observability-integration.md` (optional)

- [ ] **Step 1: Run end-to-end test**

```bash
# Make 10 queries to generate metrics
for i in {1..10}; do
  curl -X POST http://35.224.3.54/api/chat \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"What is EUR/USD?\", \"history\": []}" \
    -s > /dev/null
  echo "Query $i completed"
  sleep 3
done
```

Expected: "Query 1 completed" ... "Query 10 completed"

- [ ] **Step 2: Wait for metrics to propagate (30 seconds)**

```bash
sleep 30
```

- [ ] **Step 3: Verify metrics in Grafana**

Open Grafana → LLM Cost & Usage dashboard

Expected:
- Total LLM Cost shows accumulated cost
- Request count >= 10
- Token usage chart shows activity
- All panels have data

- [ ] **Step 4: Check for errors in logs**

```bash
kubectl logs -l app=ai-market-studio -c ai-market-studio --tail=100 | grep -i error
```

Expected: No SDK-related errors (observability errors should be warnings, not errors)

- [ ] **Step 5: Check observability service logs**

```bash
kubectl logs -l app=ai-sre-observability --tail=100
```

Expected: "POST /ingest" requests with 200 status codes

- [ ] **Step 6: Verify performance impact**

Check ai-market-studio response times before and after integration.

Expected: <10ms increase in latency (SDK overhead)

- [ ] **Step 7: Document integration**

Create summary document (optional):

```markdown
# AI Market Studio Observability Integration

**Deployed:** 2026-04-23
**Status:** ✅ Active

## Services
- Observability Service: http://ai-sre-observability.default.svc.cluster.local:8080
- Grafana Dashboards: [LLM Cost & Usage, Service Overview, Request Tracing]

## Metrics Tracked
- LLM requests per query
- Token usage (prompt + completion)
- Cost per query (USD)
- Request duration
- Error rates

## Dashboards
- LLM Cost & Usage: Real-time cost tracking by model
- Service Overview: Service health and performance
- Request Tracing: Trace ID correlation and debugging

## Rollback
If issues occur:
1. Remove OBSERVABILITY_URL from deployment
2. Rollback: `kubectl rollout undo deployment/ai-market-studio`
```

- [ ] **Step 8: Commit all changes**

```bash
cd c:/SourceCode/ai-market-studio
git add backend/main.py backend/agent/agent.py backend/requirements.txt k8s/deployment.yaml
git commit -m "feat: integrate AI SRE observability for LLM cost tracking

- Add observability SDK initialization in main.py
- Wrap agent loop with LLM call tracking
- Add OBSERVABILITY_URL to deployment
- Track token usage and costs per user query

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

Expected: Commit created with changes

---

## Success Criteria Verification

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

---

## Rollback Procedure (if needed)

### If Integration Causes Issues

- [ ] **Step 1: Remove OBSERVABILITY_URL from deployment**

```bash
cd c:/SourceCode/ai-market-studio
# Edit k8s/deployment.yaml and remove the env section with OBSERVABILITY_URL
kubectl apply -f k8s/deployment.yaml
kubectl rollout restart deployment/ai-market-studio
```

- [ ] **Step 2: Or rollback to previous deployment**

```bash
kubectl rollout undo deployment/ai-market-studio
kubectl rollout status deployment/ai-market-studio
```

- [ ] **Step 3: Verify rollback**

```bash
kubectl logs -l app=ai-market-studio -c ai-market-studio --tail=20
```

Expected: No observability initialization messages

---

## Plan Complete

**Total Tasks:** 14
**Estimated Time:** 6-9 hours (1-2 days)

**Phase 1 (Tasks 1-3):** Deploy observability service - 2-3 hours
**Phase 2 (Tasks 4-10):** Integrate SDK - 3-4 hours
**Phase 3 (Tasks 11-14):** Setup dashboards and verify - 1-2 hours

**Next Steps:**
1. Execute tasks in order
2. Verify each task before proceeding
3. Commit changes after each major milestone
4. Monitor for 24 hours post-deployment

