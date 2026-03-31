"""
Document ingestion pipeline: load → chunk → embed → store in ChromaDB.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
from typing import List

import fitz  # PyMuPDF
import chromadb
from sentence_transformers import SentenceTransformer

try:
    from langchain_text_splitters import RecursiveCharacterTextSplitter
except ImportError:
    from langchain.text_splitter import RecursiveCharacterTextSplitter  # type: ignore

# ── Constants ────────────────────────────────────────────────────────────────
_ROOT = Path(__file__).resolve().parent.parent
CHROMA_PATH = str(_ROOT / "data" / "chroma_db")
COLLECTION_NAME = "study_docs"
EMBED_MODEL = "all-MiniLM-L6-v2"
CHUNK_SIZE = 800
CHUNK_OVERLAP = 100

# ── Singleton embedding model (loaded once per process) ──────────────────────
_embed_model: SentenceTransformer | None = None


def get_embed_model() -> SentenceTransformer:
    global _embed_model
    if _embed_model is None:
        _embed_model = SentenceTransformer(EMBED_MODEL)
    return _embed_model


# ── ChromaDB helpers ─────────────────────────────────────────────────────────

def get_chroma_client() -> chromadb.PersistentClient:
    os.makedirs(CHROMA_PATH, exist_ok=True)
    return chromadb.PersistentClient(path=CHROMA_PATH)


def get_collection(client: chromadb.PersistentClient):
    return client.get_or_create_collection(
        name=COLLECTION_NAME,
        metadata={"hnsw:space": "cosine"},
    )


# ── Document loaders ─────────────────────────────────────────────────────────

def _load_pdf(path: str) -> str:
    doc = fitz.open(path)
    pages: list[str] = []
    for i, page in enumerate(doc):
        text = page.get_text()
        if text.strip():
            pages.append(f"[Page {i + 1}]\n{text.strip()}")
    doc.close()
    return "\n\n".join(pages)


def _load_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def load_document(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix == ".pdf":
        return _load_pdf(path)
    elif suffix in (".txt", ".md"):
        return _load_text(path)
    else:
        raise ValueError(f"Unsupported file type '{suffix}'. Use .pdf, .txt, or .md")


# ── Chunking ──────────────────────────────────────────────────────────────────

def chunk_text(text: str, source_name: str) -> list[dict]:
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        separators=["\n\n", "\n", ". ", "! ", "? ", " ", ""],
        length_function=len,
    )
    raw = splitter.split_text(text)
    chunks = []
    for i, chunk in enumerate(raw):
        if not chunk.strip():
            continue
        uid = hashlib.md5(f"{source_name}::{i}::{chunk[:60]}".encode()).hexdigest()
        chunks.append(
            {
                "id": uid,
                "text": chunk,
                "source": source_name,
                "chunk_index": i,
            }
        )
    return chunks


# ── Main ingestion entry point ────────────────────────────────────────────────

def ingest_document(file_path: str, display_name: str) -> int:
    """
    Load, chunk, embed, and upsert a document into ChromaDB.
    Returns the number of chunks stored.
    """
    text = load_document(file_path)
    chunks = chunk_text(text, display_name)
    if not chunks:
        return 0

    model = get_embed_model()
    texts = [c["text"] for c in chunks]
    embeddings = model.encode(texts, batch_size=32, show_progress_bar=False).tolist()

    client = get_chroma_client()
    collection = get_collection(client)

    batch_size = 100
    for start in range(0, len(chunks), batch_size):
        batch = chunks[start : start + batch_size]
        collection.upsert(
            ids=[c["id"] for c in batch],
            embeddings=embeddings[start : start + batch_size],
            documents=[c["text"] for c in batch],
            metadatas=[
                {"source": c["source"], "chunk_index": c["chunk_index"]}
                for c in batch
            ],
        )

    return len(chunks)


# ── Metadata helpers ──────────────────────────────────────────────────────────

def list_ingested_documents() -> List[str]:
    """Return sorted list of unique source document names."""
    try:
        client = get_chroma_client()
        col = get_collection(client)
        result = col.get(include=["metadatas"])
        return sorted({m["source"] for m in result["metadatas"]})
    except Exception:
        return []


def get_total_chunks() -> int:
    try:
        client = get_chroma_client()
        col = get_collection(client)
        return col.count()
    except Exception:
        return 0


def delete_document(source_name: str) -> int:
    """Delete all chunks for a document. Returns how many were removed."""
    client = get_chroma_client()
    col = get_collection(client)
    result = col.get(where={"source": source_name})
    ids = result["ids"]
    if ids:
        col.delete(ids=ids)
    return len(ids)
