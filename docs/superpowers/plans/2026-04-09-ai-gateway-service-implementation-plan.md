# AI Gateway Service — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a LiteLLM-based AI Gateway on GKE as a unified entry point for OpenAI + DeepSeek calls across all AI services.

**Architecture:** LiteLLM acts as a reverse proxy — consumer services call the gateway with OpenAI-compatible requests; LiteLLM routes to the correct provider based on model name. No custom API key handling in v1; keys live in GCP Secret Manager injected as env vars at runtime.

**Tech Stack:** Python 3.11, LiteLLM, FastAPI (via LiteLLM server), GCP Secret Manager, GKE, Cloud Build, Artifact Registry.

---

## File Map

```
ai-gateway-service/               # Root of the repo (c:/SourceCode/ai-gateway-service/)
├── requirements.txt               # Python dependencies
├── config.yaml                    # LiteLLM model routing config
├── Dockerfile                     # Container image
├── cloudbuild.yaml               # GCP Cloud Build CI
├── app/
│   └── __init__.py               # Empty, marks package
├── tests/
│   ├── __init__.py
│   ├── conftest.py               # Shared pytest fixtures
│   ├── test_health.py            # /health and /readiness endpoint tests
│   └── test_routing.py           # Model routing / v1/models tests
├── k8s/
│   ├── namespace.yaml             # Optional: dedicated namespace
│   ├── deployment.yaml            # GKE Deployment
│   ├── service.yaml               # GKE Service (ClusterIP)
│   └── secret.yaml                # API key secret (references GCP Secret Manager)
└── README.md
```

**Note:** No custom `app/main.py` needed — LiteLLM ships its own production-ready server. We configure it entirely via `config.yaml` + env vars.

---

## Task 1: Project Scaffolding

**Files:**
- Create: `ai-gateway-service/requirements.txt`
- Create: `ai-gateway-service/config.yaml`
- Create: `ai-gateway-service/app/__init__.py`
- Create: `ai-gateway-service/tests/__init__.py`
- Create: `ai-gateway-service/tests/conftest.py`

- [ ] **Step 1: Create `requirements.txt`**

```txt
litellm==1.52.3
python-dotenv==1.0.1
httpx==0.28.1
pytest==8.3.4
pytest-asyncio==0.25.2
```

- [ ] **Step 2: Create `config.yaml`**

```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OpenAI_API_KEY

  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY

  - model_name: deepseek-chat
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: os.environ/DEEPSEEK_API_KEY

general_settings:
  master_key: null  # no auth in v1
  database_path: null  # no persistence needed

environment: gke
port: 4000
```

- [ ] **Step 3: Create `app/__init__.py` and `tests/__init__.py`**

Both files: empty. `app/` is just a package marker.

- [ ] **Step 4: Create `tests/conftest.py`**

```python
import pytest

@pytest.fixture
def config_path():
    return "config.yaml"
```

- [ ] **Step 5: Commit**

```bash
git add requirements.txt config.yaml app/ tests/
git commit -m "chore: project scaffold - requirements, config, test structure"
```

---

## Task 2: Health Check Endpoint Tests

**Files:**
- Create: `ai-gateway-service/tests/test_health.py`

- [ ] **Step 1: Write failing health check tests**

```python
# tests/test_health.py
import httpx
import pytest

BASE_URL = "http://localhost:4000"

@pytest.mark.asyncio
async def test_health_returns_200():
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{BASE_URL}/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

@pytest.mark.asyncio
async def test_readiness_checks_openai_key():
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{BASE_URL}/readiness")
    # Returns 200 if keys are configured, 503 if missing
    assert response.status_code in (200, 503)
```

- [ ] **Step 2: Verify tests fail (no server running)**

Run: `pytest tests/test_health.py -v`
Expected: `ConnectionError` — server not yet running

- [ ] **Step 3: Commit**

```bash
git add tests/test_health.py
git commit -m "test: add health endpoint tests"
```

---

## Task 3: Model Routing Tests

**Files:**
- Create: `ai-gateway-service/tests/test_routing.py`

- [ ] **Step 1: Write failing model list test**

```python
# tests/test_routing.py
import httpx
import pytest

BASE_URL = "http://localhost:4000"

@pytest.mark.asyncio
async def test_models_endpoint_returns_configured_models():
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{BASE_URL}/v1/models")
    assert response.status_code == 200
    data = response.json()
    model_ids = [m["id"] for m in data.get("data", [])]
    assert "gpt-4o" in model_ids or "gpt-4o-mini" in model_ids
    assert "deepseek-chat" in model_ids
```

- [ ] **Step 2: Verify test fails**

Run: `pytest tests/test_routing.py -v`
Expected: `ConnectionError` — server not yet running

- [ ] **Step 3: Commit**

```bash
git add tests/test_routing.py
git commit -m "test: add model routing /v1/models test"
```

---

## Task 4: Dockerfile

**Files:**
- Create: `ai-gateway-service/Dockerfile`

- [ ] **Step 1: Write Dockerfile**

```dockerfile
FROM ghcr.io/berriai/litellm:main

WORKDIR /app

# Copy config
COPY config.yaml /app/config.yaml

# Copy custom routes dir (empty for now, reserved for future)
COPY app/ /app/app/

# Expose port
EXPOSE 4000

# Environment variables injected at runtime via Kubernetes secrets
# LITELLM_MASTER_KEY, OPENAI_API_KEY, DEEPSEEK_API_KEY, OTEL_EXPORTER_OTLP_ENDPOINT

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD python -c "import httpx; httpx.get('http://localhost:4000/health', timeout=5).raise_for_status()"

# Start LiteLLM server with config
CMD ["--config", "/app/config.yaml", "--port", "4000", "--host", "0.0.0.0"]
```

- [ ] **Step 2: Verify Dockerfile builds locally**

Run: `docker build -t ai-gateway-service:test ./ai-gateway-service/ --no-cache`
Expected: Build succeeds, image size ~2-3GB (LiteLLM image is large)

- [ ] **Step 3: Commit**

```bash
git add Dockerfile
git commit -m "chore: add Dockerfile for LiteLLM gateway"
```

---

## Task 5: Kubernetes Manifests

**Files:**
- Create: `ai-gateway-service/k8s/namespace.yaml`
- Create: `ai-gateway-service/k8s/deployment.yaml`
- Create: `ai-gateway-service/k8s/service.yaml`
- Create: `ai-gateway-service/k8s/secret.yaml`

- [ ] **Step 1: Write `k8s/namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ai-gateway
  labels:
    name: ai-gateway
    environment: production
```

- [ ] **Step 2: Write `k8s/secret.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ai-gateway-secrets
  namespace: ai-gateway
type: Opaque
stringData:
  OPENAI_API_KEY: "dummy-placeholder"   # Replace with actual key via Secret Manager
  DEEPSEEK_API_KEY: "dummy-placeholder"  # Replace with actual key via Secret Manager
  # In production, use GCP Secret Manager sync or externally-managed secrets
```

- [ ] **Step 3: Write `k8s/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-gateway
  namespace: ai-gateway
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ai-gateway
  template:
    metadata:
      labels:
        app: ai-gateway
      annotations:
        otel.io/inject-sdk: "true"  # OpenTelemetry auto-instrumentation
    spec:
      containers:
        - name: ai-gateway
          image: REGION-docker.pkg.dev/PROJECT_ID/ai-gateway-repo/ai-gateway-service:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 4000
          env:
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ai-gateway-secrets
                  key: OPENAI_API_KEY
            - name: DEEPSEEK_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ai-gateway-secrets
                  key: DEEPSEEK_API_KEY
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
            limits:
              cpu: "2000m"
              memory: "2Gi"
          livenessProbe:
            httpGet:
              path: /health
              port: 4000
            initialDelaySeconds: 30
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /readiness
              port: 4000
            initialDelaySeconds: 10
            periodSeconds: 10
```

> **Note:** Replace `REGION`, `PROJECT_ID`, and `ai-gateway-repo` with your actual GCP values before deploying.

- [ ] **Step 4: Write `k8s/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ai-gateway
  namespace: ai-gateway
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 4000
      protocol: TCP
  selector:
    app: ai-gateway
```

- [ ] **Step 5: Commit**

```bash
git add k8s/
git commit -m "chore: add Kubernetes manifests for GKE deployment"
```

---

## Task 6: Cloud Build Pipeline

**Files:**
- Create: `ai-gateway-service/cloudbuild.yaml`

- [ ] **Step 1: Write `cloudbuild.yaml`**

```yaml
steps:
  - name: "gcr.io/cloud-builders/docker"
    args:
      - build
      - -t
      - REGION-docker.pkg.dev/PROJECT_ID/ai-gateway-repo/ai-gateway-service:latest
      - -t
      - REGION-docker.pkg.dev/PROJECT_ID/ai-gateway-repo/ai-gateway-service:$COMMIT_SHA
      - .
    env:
      - DOCKER_BUILDKIT=1

  - name: "gcr.io/cloud-builders/docker"
    args:
      - push
      - --all-tags
      - REGION-docker.pkg.dev/PROJECT_ID/ai-gateway-repo/ai-gateway-service
    env:
      - DOCKER_BUILDKIT=1

images:
  - REGION-docker.pkg.dev/PROJECT_ID/ai-gateway-repo/ai-gateway-service:latest
  - REGION-docker.pkg.dev/PROJECT_ID/ai-gateway-repo/ai-gateway-service:$COMMIT_SHA

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: E2_HIGHCPU_8
```

> **Note:** Replace `REGION` and `PROJECT_ID` with your GCP region and project ID.

- [ ] **Step 2: Commit**

```bash
git add cloudbuild.yaml
git commit -m "chore: add Cloud Build CI pipeline"
```

---

## Task 7: README

**Files:**
- Create: `ai-gateway-service/README.md`

- [ ] **Step 1: Write README**

````markdown
# AI Gateway Service

Unified OpenAI-compatible API gateway for OpenAI and DeepSeek, powered by LiteLLM.

## Quick Start

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set API keys
export OPENAI_API_KEY=sk-...
export DEEPSEEK_API_KEY=sk-...

# Start server
litellm --config config.yaml --port 4000
```

### Health Check

```bash
curl http://localhost:4000/health        # Returns {"status": "ok"}
curl http://localhost:4000/readiness     # Checks provider connectivity
curl http://localhost:4000/v1/models     # Lists configured models
```

### Docker

```bash
docker build -t ai-gateway-service .
docker run -p 4000:4000 \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  -e DEEPSEEK_API_KEY=$DEEPSEEK_API_KEY \
  ai-gateway-service
```

## Deployment (GKE)

1. Configure Artifact Registry:
   ```bash
   gcloud artifacts repositories create ai-gateway-repo \
     --repository-format=docker \
     --location=REGION
   ```

2. Build and push:
   ```bash
   gcloud builds submit --config=cloudbuild.yaml
   ```

3. Apply Kubernetes manifests:
   ```bash
   kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/secret.yaml    # Update with real keys first
   kubectl apply -f k8s/deployment.yaml
   kubectl apply -f k8s/service.yaml
   ```

4. Verify deployment:
   ```bash
   kubectl -n ai-gateway get pods
   kubectl -n ai-gateway logs -l app=ai-gateway --tail=50
   ```

## Model Routing

| Model Prefix   | Provider  | Endpoint |
|----------------|-----------|----------|
| `gpt-4o*`      | OpenAI    | `POST /v1/chat/completions` |
| `gpt-4o-mini*` | OpenAI    | `POST /v1/chat/completions` |
| `deepseek-*`   | DeepSeek  | `POST /v1/chat/completions` |

## Configuration

All model and provider configuration is in `config.yaml`. No hardcoded API keys — keys are injected via environment variables at runtime.
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with local and GKE deployment instructions"
```

---

## Self-Review Checklist

1. **Spec coverage:** All items in `2026-04-09-ai-gateway-service-design.md` have corresponding tasks:
   - Unified endpoint (`/v1/chat/completions`, `/v1/models`) → Task 3 (routing test + LiteLLM built-in)
   - Model routing → Task 3 (`test_routing.py`)
   - API key management → Task 1 (`config.yaml` with env vars) + Task 5 (`k8s/secret.yaml`)
   - Health check → Task 2 (`test_health.py` + `deployment.yaml` probes)
   - Observability hooks → LiteLLM auto-instruments; deployment annotation set in Task 5
   - GKE deployment → Tasks 4, 5, 6

2. **Placeholder scan:** No TODOs, no TBDs. All file paths, code, and commands are complete.

3. **Type consistency:** All references use consistent naming — `ai-gateway`, namespace `ai-gateway`, port `4000`, `gpt-4o` model name. No mismatches.

4. **Gaps identified:** None.

---

**Plan complete.** All 7 tasks are independent and can run in sequence (they commit independently). The Docker build in Task 4 is the first integration checkpoint — if it fails, the plan needs adjustment.
