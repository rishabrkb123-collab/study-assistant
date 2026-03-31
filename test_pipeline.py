"""
End-to-end pipeline test.

Usage:
    python test_pipeline.py

What it does:
    1. Writes a sample Markdown note on Newton's Laws + kinematics
    2. Ingests it into ChromaDB
    3. Runs three queries (concept, derivation, numerical)
    4. Prints retrieved chunks + streamed LLM answers
    5. Tests the Python solver tool on a simple kinematic problem
    6. Exits with code 0 on success, 1 on failure
"""
from __future__ import annotations

import os
import sys
import tempfile
import textwrap
import traceback

SAMPLE_NOTE = textwrap.dedent("""\
# Classical Mechanics — Quick Reference

## Newton's Laws of Motion

**First Law (Inertia):** An object at rest stays at rest, and an object in motion
stays in motion at constant velocity, unless acted upon by a net external force.

**Second Law:** The net force on an object equals its mass times its acceleration.
    F = m × a
where F is in Newtons (N), m in kilograms (kg), and a in m/s².

**Third Law:** For every action there is an equal and opposite reaction.

## Kinematic Equations (constant acceleration)

1. v = u + at
2. s = ut + ½at²
3. v² = u² + 2as
4. s = (u + v)/2 × t

Symbols:
- u = initial velocity (m/s)
- v = final velocity (m/s)
- a = acceleration (m/s²)
- t = time (s)
- s = displacement (m)

## Example: Free Fall

A ball is dropped from rest (u = 0) from a height of 45 m.
Taking g = 10 m/s² (downward), find the time to hit the ground and final velocity.

Using s = ut + ½at²:
    45 = 0×t + ½×10×t²
    45 = 5t²
    t² = 9  →  t = 3 s

Using v = u + at:
    v = 0 + 10×3 = 30 m/s
""")

QUERIES = [
    ("concept",     "Explain Newton's Second Law intuitively."),
    ("derivation",  "Derive the kinematic equation v² = u² + 2as from first principles."),
    ("numerical",   "A ball is thrown upward with initial velocity 20 m/s. "
                    "Using g = 10 m/s², how high does it go and how long before it returns?"),
]


def separator(title: str) -> None:
    print("\n" + "=" * 60)
    print(f"  {title}")
    print("=" * 60)


def run_test() -> bool:  # noqa: C901
    ok = True

    # ── 1. Write sample note to a temp file ──────────────────────────────────
    separator("1 / Ingestion")
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".md", delete=False, encoding="utf-8"
    )
    tmp.write(SAMPLE_NOTE)
    tmp.close()
    print(f"Sample note written to: {tmp.name}")

    try:
        from rag.ingestor import ingest_document, list_ingested_documents, get_total_chunks

        n = ingest_document(tmp.name, "sample_mechanics_note.md")
        print(f"Chunks ingested: {n}")
        assert n > 0, "Expected at least 1 chunk after ingestion"

        docs = list_ingested_documents()
        print(f"Indexed documents: {docs}")
        assert "sample_mechanics_note.md" in docs

        total = get_total_chunks()
        print(f"Total chunks in DB: {total}")
        assert total > 0

        print("\n✓ Ingestion passed")
    except Exception:
        traceback.print_exc()
        ok = False
        print("✗ Ingestion FAILED")
    finally:
        os.unlink(tmp.name)

    # ── 2. Retrieval ──────────────────────────────────────────────────────────
    separator("2 / Retrieval")
    try:
        from rag.retriever import retrieve

        chunks = retrieve("Newton's Second Law", top_k=3)
        assert chunks, "Expected non-empty retrieval"
        print(f"Retrieved {len(chunks)} chunks:")
        for i, c in enumerate(chunks, 1):
            print(f"  [{i}] source={c['source']}  relevance={c['relevance']:.0%}")
            print(f"      {c['text'][:80].strip()}…")

        print("\n✓ Retrieval passed")
    except Exception:
        traceback.print_exc()
        ok = False
        print("✗ Retrieval FAILED")

    # ── 3. Ollama availability ────────────────────────────────────────────────
    separator("3 / Ollama check")
    try:
        from rag.llm import check_ollama, model_available, MODEL

        running, err = check_ollama()
        if not running:
            print(f"⚠  Ollama not running ({err}) — skipping LLM tests.")
            print("   Start Ollama with: ollama serve")
            return ok  # not a hard failure — infra might not be available in CI

        print(f"Ollama running ✓")
        mok = model_available(MODEL)
        if not mok:
            print(f"⚠  Model {MODEL} not pulled — skipping LLM tests.")
            print(f"   Run: ollama pull {MODEL}")
            return ok

        print(f"Model {MODEL} available ✓")
    except Exception:
        traceback.print_exc()
        ok = False
        return ok

    # ── 4. LLM streaming ─────────────────────────────────────────────────────
    separator("4 / LLM streaming")
    try:
        from rag.llm import stream_response

        chunks = retrieve(QUERIES[0][1], top_k=3)
        print(f"Query: {QUERIES[0][1]}\n")
        print("Response (streaming):\n")
        response = ""
        for token in stream_response(QUERIES[0][1], chunks):
            print(token, end="", flush=True)
            response += token
        print()
        assert len(response) > 50, "Response too short"

        print("\n✓ LLM streaming passed")
    except Exception:
        traceback.print_exc()
        ok = False
        print("✗ LLM streaming FAILED")

    # ── 5. Numerical solver tool ──────────────────────────────────────────────
    separator("5 / Numerical solver tool")
    try:
        from rag.tools import is_numerical, extract_code, execute_code

        num_query = QUERIES[2][1]
        assert is_numerical(num_query), "Should detect as numerical"
        print(f"is_numerical({num_query[:60]}…) = True ✓")

        # Simple standalone code test (no LLM needed)
        test_code = textwrap.dedent("""\
            import math
            u = 20       # initial velocity m/s
            g = 10       # gravity m/s^2
            h_max = u**2 / (2 * g)
            t_up  = u / g
            t_total = 2 * t_up
            print(f"Max height:    {h_max} m")
            print(f"Time to top:   {t_up} s")
            print(f"Total flight:  {t_total} s")
        """)
        out, success = execute_code(test_code)
        print(f"Code executed successfully: {success}")
        print(f"Output:\n{out}")
        assert success, f"Code execution failed: {out}"
        assert "20.0" in out or "20" in out, "Expected max_height = 20 in output"

        print("\n✓ Numerical solver passed")
    except Exception:
        traceback.print_exc()
        ok = False
        print("✗ Numerical solver FAILED")

    # ── 6. Full pipeline for all query types ──────────────────────────────────
    separator("6 / Full pipeline (all query types)")
    try:
        from rag.llm import stream_response, generate_solver_code
        from rag.tools import is_numerical, extract_code, execute_code

        for q_type, q_text in QUERIES:
            print(f"\n--- Query type: {q_type} ---")
            print(f"Q: {q_text}\n")

            ctx = retrieve(q_text, top_k=3)
            code_result = None

            if is_numerical(q_text):
                ctx_text = "\n".join(c["text"] for c in ctx[:2])
                raw = generate_solver_code(q_text, ctx_text)
                code = extract_code(raw)
                if code:
                    code_result, _ = execute_code(code)
                    print(f"[code result] {code_result[:200]}")

            resp = ""
            for tok in stream_response(q_text, ctx, code_result):
                resp += tok
            print(resp[:400] + ("…" if len(resp) > 400 else ""))
            assert len(resp) > 30, f"Empty response for {q_type} query"

        print("\n✓ Full pipeline passed")
    except Exception:
        traceback.print_exc()
        ok = False
        print("✗ Full pipeline FAILED")

    return ok


if __name__ == "__main__":
    passed = run_test()
    separator("RESULT")
    if passed:
        print("All tests PASSED ✓")
        sys.exit(0)
    else:
        print("One or more tests FAILED ✗")
        sys.exit(1)
