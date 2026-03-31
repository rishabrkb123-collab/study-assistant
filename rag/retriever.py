"""
ChromaDB retrieval: given a query, return the top-k most relevant chunks.
"""
from __future__ import annotations

from typing import List

from .ingestor import get_chroma_client, get_collection, get_embed_model


def retrieve(query: str, top_k: int = 5) -> List[dict]:
    """
    Retrieve the top-k chunks most relevant to *query*.

    Each result dict has:
        text          – chunk text
        source        – source document name
        chunk_index   – position within source
        distance      – cosine distance (lower = more similar)
        relevance     – 1 - distance, clamped to [0, 1]
    """
    client = get_chroma_client()
    collection = get_collection(client)

    total = collection.count()
    if total == 0:
        return []

    model = get_embed_model()
    q_emb = model.encode([query]).tolist()

    n = min(top_k, total)
    results = collection.query(
        query_embeddings=q_emb,
        n_results=n,
        include=["documents", "metadatas", "distances"],
    )

    chunks: list[dict] = []
    for i in range(len(results["documents"][0])):
        dist = results["distances"][0][i]
        chunks.append(
            {
                "text": results["documents"][0][i],
                "source": results["metadatas"][0][i]["source"],
                "chunk_index": results["metadatas"][0][i]["chunk_index"],
                "distance": dist,
                "relevance": round(max(0.0, 1.0 - dist), 4),
            }
        )

    # Sort by relevance descending (highest relevance first)
    chunks.sort(key=lambda c: c["relevance"], reverse=True)
    return chunks
