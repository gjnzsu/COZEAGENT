# Design: F4 Research RAG Integration (Sidecar Architecture)

## Overview
Integrate the `ai-rag-service` (Provider) into `ai-market-studio` (Consumer) to enable natural-language queries over internal research documents (PDF, Jira, Confluence).

## Architecture
- **ai-rag-service** (Running on port 8000): Specialized service for document ingestion, indexing, and retrieval using ChromaDB. In GKE, exposed via internal ClusterIP service.
- **ai-market-studio** (Running on port 8000): Conversational UI/UX for FX data. Communicates with RAG service via K8s internal DNS (e.g., `http://ai-rag-service:8000`).

## Implementation Plan

### 1. `ai-market-studio` Configuration
- Add `RAG_SERVICE_URL` (default: `http://localhost:8000`) to `.env`.
- Update `backend/config.py` to expose this URL to the application.
- Update `k8s/configmap.yaml` with the production service URL.

### 2. RAG Connector in Studio
- Create `backend/connectors/rag_connector.py` to handle the REST client logic for the RAG service.
- Implement a `query_research(question: str) -> dict` method that calls the `/query` endpoint of the RAG service.

### 3. LLM Tooling & Function Calling
- Add a new tool to the Studio LLM registry: `get_internal_research`.
- Description: "Search internal research documents (PDFs, Jira issues, Confluence pages) for market insights, trader analysis, or project updates."
- Update the main chat logic in `backend/api/chat.py` to handle tool calls to the RAG service.

### 4. UI/UX Enhancements
- Update the frontend chat bubble to handle research-specific responses.
- Display source citations (e.g., "Source: Q1-Report.pdf") provided by the RAG service.
- Add an example chip: "What do the internal reports say about EUR/USD?"

## Security & Reliability
- **Error Handling**: If the RAG service is unreachable, return a graceful "Research search is currently unavailable" message.
- **Authentication**: (Future) Secure the communication between Studio and the RAG service via internal API keys.

## Success Criteria
- User can ask "What is the outlook for JPY according to internal reports?" and receive a RAG-backed answer.
- Answers include document/item sources for transparency.
- RAG queries complete in under 3 seconds.

## Future Considerations
- Support for real-time trader commentary ingestion (F6).
- OCR-based ingestion for scanned market reports (F11).