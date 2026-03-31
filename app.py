"""
Study Assistant — Streamlit UI
RAG-powered tutor backed by Ollama + ChromaDB + sentence-transformers.
"""
from __future__ import annotations

import os
import tempfile
import time
from pathlib import Path
from typing import Optional

import streamlit as st

# ── Page config (must be first Streamlit call) ────────────────────────────────
st.set_page_config(
    page_title="Study Assistant",
    page_icon="📚",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Local imports ─────────────────────────────────────────────────────────────
from rag.ingestor import (
    ingest_document,
    list_ingested_documents,
    get_total_chunks,
    delete_document,
)
from rag.retriever import retrieve
from rag.llm import (
    MODEL,
    check_ollama,
    model_available,
    stream_response,
    generate_solver_code,
)
from rag.tools import is_numerical, extract_code, execute_code

# ── Custom CSS ────────────────────────────────────────────────────────────────
st.markdown(
    """
<style>
/* Chat bubbles */
.user-bubble {
    background: #2D2B55;
    border-left: 3px solid #7C3AED;
    padding: 12px 16px;
    border-radius: 8px;
    margin: 8px 0;
}
.assistant-bubble {
    background: #1A1A2E;
    border-left: 3px solid #06B6D4;
    padding: 12px 16px;
    border-radius: 8px;
    margin: 8px 0;
}
/* Source chip */
.source-chip {
    display: inline-block;
    background: #312E81;
    color: #C4B5FD;
    font-size: 0.72rem;
    padding: 2px 10px;
    border-radius: 20px;
    margin: 3px 3px 3px 0;
}
/* Code block for executed code */
.exec-box {
    background: #0F172A;
    border: 1px solid #334155;
    border-radius: 6px;
    padding: 10px 14px;
    font-size: 0.82rem;
    font-family: monospace;
}
/* Relevance bar */
.rel-bar-wrap { background:#1E293B; border-radius:4px; height:6px; width:100%; }
.rel-bar-fill { background:#7C3AED; border-radius:4px; height:6px; }
/* Sidebar doc badge */
.doc-badge {
    background: #1E293B;
    border: 1px solid #334155;
    padding: 6px 10px;
    border-radius: 6px;
    font-size: 0.80rem;
    margin: 4px 0;
    display: flex;
    justify-content: space-between;
    align-items: center;
}
</style>
""",
    unsafe_allow_html=True,
)

# ── Session state ─────────────────────────────────────────────────────────────
if "messages" not in st.session_state:
    st.session_state.messages = []  # [{role, content, sources, code, code_out}]
if "ingested_docs" not in st.session_state:
    st.session_state.ingested_docs = list_ingested_documents()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _refresh_docs() -> None:
    st.session_state.ingested_docs = list_ingested_documents()


def _relevance_bar(score: float) -> str:
    pct = int(score * 100)
    return (
        f'<div class="rel-bar-wrap">'
        f'<div class="rel-bar-fill" style="width:{pct}%"></div>'
        f"</div>"
    )


def _render_sources(sources: list[dict]) -> None:
    if not sources:
        return
    st.markdown("**Sources used:**")
    for s in sources:
        chip = f'<span class="source-chip">📄 {s["source"]} · chunk {s["chunk_index"]}</span>'
        st.markdown(chip, unsafe_allow_html=True)
        st.markdown(
            _relevance_bar(s["relevance"]) +
            f"<small style='color:#64748B'> relevance {s['relevance']:.0%}</small>",
            unsafe_allow_html=True,
        )
        with st.expander(f"View excerpt — {s['source']}", expanded=False):
            st.caption(s["text"])


def _render_code_block(code: str, output: str, success: bool) -> None:
    icon = "✅" if success else "❌"
    with st.expander(f"{icon} Python solver — click to expand", expanded=not success):
        st.code(code, language="python")
        if output:
            st.markdown("**Output:**")
            st.code(output, language="text")


# ── Sidebar ───────────────────────────────────────────────────────────────────

with st.sidebar:
    st.markdown("## 📚 Study Assistant")
    st.caption("RAG · Ollama · ChromaDB · Sentence-Transformers")
    st.divider()

    # ── Ollama status ─────────────────────────────────────────────────────────
    ollama_ok, ollama_err = check_ollama()
    if ollama_ok:
        model_ok = model_available(MODEL)
        if model_ok:
            st.success(f"Ollama ✓  |  `{MODEL}` loaded")
        else:
            st.warning(
                f"Ollama running but **{MODEL}** not found.\n\n"
                f"Run: `ollama pull {MODEL}`"
            )
    else:
        st.error(
            "**Ollama not reachable.**\n\n"
            "Make sure Ollama is running: `ollama serve`\n\n"
            f"_Details: {ollama_err}_"
        )

    st.divider()

    # ── Document upload ───────────────────────────────────────────────────────
    st.markdown("### Upload Documents")
    uploaded = st.file_uploader(
        "PDF, TXT, or MD files",
        type=["pdf", "txt", "md"],
        accept_multiple_files=True,
        label_visibility="collapsed",
    )

    if uploaded:
        for uf in uploaded:
            suffix = Path(uf.name).suffix
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
                tmp.write(uf.read())
                tmp_path = tmp.name
            try:
                with st.spinner(f"Ingesting **{uf.name}** …"):
                    n_chunks = ingest_document(tmp_path, uf.name)
                st.success(f"✓ {uf.name} → {n_chunks} chunks")
                _refresh_docs()
            except Exception as exc:
                st.error(f"Failed to ingest {uf.name}: {exc}")
            finally:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass

    st.divider()

    # ── Ingested documents list ───────────────────────────────────────────────
    st.markdown("### Ingested Documents")
    total_chunks = get_total_chunks()
    docs = st.session_state.ingested_docs

    if not docs:
        st.caption("No documents yet. Upload files above.")
    else:
        st.caption(f"{len(docs)} document(s) · {total_chunks} total chunks")
        for doc in docs:
            col_name, col_del = st.columns([4, 1])
            col_name.markdown(
                f'<div class="doc-badge">📄 {doc}</div>', unsafe_allow_html=True
            )
            if col_del.button("🗑", key=f"del_{doc}", help=f"Remove {doc}"):
                removed = delete_document(doc)
                st.success(f"Removed {doc} ({removed} chunks)")
                _refresh_docs()
                st.rerun()

    st.divider()

    # ── Settings ──────────────────────────────────────────────────────────────
    st.markdown("### Settings")
    top_k = st.slider("Chunks to retrieve (top-k)", 1, 10, 5)
    use_code_tool = st.toggle("Enable Python solver for numericals", value=True)

    st.divider()
    if st.button("🗑 Clear chat history"):
        st.session_state.messages = []
        st.rerun()

# ── Main chat area ────────────────────────────────────────────────────────────

st.markdown("## 🎓 Study Assistant Chat")
st.caption(
    "Ask conceptual questions, request step-by-step derivations, or pose numerical problems."
)

# Render existing conversation
for msg in st.session_state.messages:
    role = msg["role"]
    with st.chat_message(role):
        st.markdown(msg["content"])
        if role == "assistant":
            if msg.get("code") and msg.get("code_out") is not None:
                _render_code_block(
                    msg["code"], msg["code_out"], msg.get("code_success", False)
                )
            if msg.get("sources"):
                _render_sources(msg["sources"])

# ── Input ─────────────────────────────────────────────────────────────────────
query = st.chat_input("Ask anything from your notes…")

if query:
    # -- Guard: Ollama must be up -----------------------------------------------
    if not ollama_ok:
        st.error("Ollama is not running. Start it with `ollama serve` and refresh.")
        st.stop()

    # -- Show user message -------------------------------------------------------
    st.session_state.messages.append({"role": "user", "content": query})
    with st.chat_message("user"):
        st.markdown(query)

    # -- Retrieve ----------------------------------------------------------------
    with st.spinner("Searching your notes…"):
        chunks = retrieve(query, top_k=top_k)

    if not chunks:
        no_doc_warning = (
            "_No documents ingested yet. Upload study material in the sidebar, "
            "then I'll answer from your notes. Answering from general knowledge for now._\n\n"
        )
    else:
        no_doc_warning = ""

    # -- Optional: numerical code solver ----------------------------------------
    code_used: Optional[str] = None
    code_output: Optional[str] = None
    code_success = False

    if use_code_tool and is_numerical(query):
        context_text = "\n\n".join(c["text"] for c in chunks[:3]) if chunks else ""
        with st.spinner("Writing Python solver…"):
            raw_llm = generate_solver_code(query, context_text)
        code_used = extract_code(raw_llm)
        if code_used:
            with st.spinner("Executing Python code…"):
                code_output, code_success = execute_code(code_used)
        else:
            code_used = None  # extraction failed; skip

    # -- Stream LLM response ----------------------------------------------------
    with st.chat_message("assistant"):
        response_placeholder = st.empty()
        full_response = no_doc_warning
        response_placeholder.markdown(full_response + "▌")

        try:
            for token in stream_response(
                query=query,
                context_chunks=chunks,
                code_result=code_output,
            ):
                full_response += token
                response_placeholder.markdown(full_response + "▌")
        except Exception as exc:
            full_response += f"\n\n⚠️ LLM error: {exc}"

        response_placeholder.markdown(full_response)

        # Show code block (if used)
        if code_used:
            _render_code_block(code_used, code_output or "", code_success)

        # Show sources
        if chunks:
            _render_sources(chunks)

    # -- Persist to session state -----------------------------------------------
    st.session_state.messages.append(
        {
            "role": "assistant",
            "content": full_response,
            "sources": chunks,
            "code": code_used,
            "code_out": code_output,
            "code_success": code_success,
        }
    )
