# Study Assistant — Local RAG Tutor

A fully offline, free AI study assistant that answers conceptual questions,
solves numericals step-by-step, and does derivations — all grounded in your
own notes and PDFs.

| Layer | Technology |
|---|---|
| LLM | Ollama · `llama3.1:8b` |
| Embeddings | `sentence-transformers` · `all-MiniLM-L6-v2` |
| Vector DB | ChromaDB (persistent, local) |
| RAG pipeline | LangChain text splitters |
| Math solver | Python `exec()` sandbox |
| Document loaders | PyMuPDF (PDF) · built-in (TXT, MD) |
| UI | Streamlit |

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Python | ≥ 3.10 | 3.11 recommended |
| Ollama | latest | [ollama.com/download](https://ollama.com/download) |
| Git | any | optional |

---

## Setup (from scratch)

### 1 — Install Ollama

**macOS / Linux**
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

**Windows**
Download and run the installer from https://ollama.com/download

### 2 — Pull the model

```bash
ollama pull llama3.1:8b
```

> This downloads ~4.7 GB. Run once; Ollama caches it locally.

### 3 — Clone / unzip the project

```bash
# If you have git:
git clone <repo-url> study-assistant
cd study-assistant

# Otherwise just unzip and cd into the folder.
```

### 4 — Create a virtual environment

```bash
python -m venv .venv

# macOS / Linux
source .venv/bin/activate

# Windows (PowerShell)
.venv\Scripts\Activate.ps1

# Windows (CMD)
.venv\Scripts\activate.bat
```

### 5 — Install Python dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

> **GPU users:** for faster embeddings replace the `torch` line in
> `requirements.txt` with the CUDA wheel for your platform (see
> https://pytorch.org/get-started/locally/).
>
> **CPU-only install** (saves ~1 GB):
> ```bash
> pip install torch --index-url https://download.pytorch.org/whl/cpu
> pip install -r requirements.txt
> ```

### 6 — Run the app

```bash
# Start Ollama in background (if not already running)
ollama serve &        # macOS/Linux
# On Windows: Ollama runs as a system service after install

# Launch the UI
streamlit run app.py
```

Open http://localhost:8501 in your browser.

---

## Running the end-to-end test

Make sure Ollama is running and the model is pulled, then:

```bash
python test_pipeline.py
```

The test will:
1. Create a sample Mechanics markdown note
2. Ingest it into ChromaDB
3. Run retrieval queries
4. Stream LLM answers for conceptual, derivation, and numerical queries
5. Execute a Python solver and verify output
6. Print `All tests PASSED ✓` and exit `0` on success

---

## Project structure

```
study-assistant/
├── app.py                   # Streamlit UI (entry point)
├── requirements.txt
├── test_pipeline.py         # End-to-end test
├── README.md
├── .streamlit/
│   └── config.toml          # Dark theme settings
├── rag/
│   ├── __init__.py
│   ├── ingestor.py          # Load → chunk → embed → store
│   ├── retriever.py         # Query ChromaDB for top-k chunks
│   ├── llm.py               # Ollama wrapper (streaming + code-gen)
│   └── tools.py             # Numerical detector + Python executor
└── data/
    └── chroma_db/           # Persistent vector store (auto-created)
```

---

## How it works

```
User query
    │
    ▼
[retriever.py] Query ChromaDB with sentence-transformer embedding
    │  top-5 relevant chunks
    ▼
[tools.py] If numerical: ask LLM to write Python → exec() → capture result
    │
    ▼
[llm.py] Build prompt: system prompt + chunks + code result + question
    │
    ▼
Ollama (llama3.1:8b) streams tokens → Streamlit renders in real time
    │
    ▼
[app.py] Display response + source chips + relevance bars + code block
```

---

## Supported file types

| Extension | Loader |
|---|---|
| `.pdf` | PyMuPDF — page-aware extraction |
| `.txt` | UTF-8 plain text |
| `.md` | Markdown (treated as plain text) |

---

## Chunking parameters

| Parameter | Value |
|---|---|
| `chunk_size` | 800 characters |
| `chunk_overlap` | 100 characters |
| `separators` | `\n\n`, `\n`, `. `, ` `, `` |

Change these in `rag/ingestor.py` if you need finer or coarser chunks.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Ollama not reachable" | Run `ollama serve` |
| "Model not found" | Run `ollama pull llama3.1:8b` |
| Slow first query | Embedding model downloads ~90 MB on first run |
| Out-of-memory | Use CPU torch; reduce `top_k` slider |
| ChromaDB error on restart | Delete `data/chroma_db/` and re-ingest |
| PDF text is garbled | Ensure the PDF has selectable text (not scanned image) |

---

## Changing the LLM

Edit `rag/llm.py` line:
```python
MODEL = "llama3.1:8b"
```

Any model available in Ollama works — e.g. `mistral`, `phi3`, `gemma2`.
Pull it first: `ollama pull <model-name>`.

---

## Privacy

Everything runs 100 % locally. No data leaves your machine.
