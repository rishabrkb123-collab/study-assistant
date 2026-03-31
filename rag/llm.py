"""
Ollama LLM wrapper — streaming chat + code-generation helper.
"""
from __future__ import annotations

from typing import Generator, List, Optional

import ollama

MODEL = "llama3.1:8b"

SYSTEM_PROMPT = """\
You are an expert study tutor helping a student understand their course material.
You have access to relevant excerpts from their notes and textbooks (provided below).

━━━ HOW TO RESPOND ━━━

▸ NUMERICAL / CALCULATION PROBLEMS
  1. List all given values with units
  2. State the governing formula / law
  3. Substitute values and compute each step (show arithmetic)
  4. State the final answer with correct units
  5. Sanity-check: does the magnitude make sense?

▸ DERIVATIONS
  1. State starting equation or first principles
  2. Show every algebraic/calculus step
  3. Briefly explain *why* each transformation is valid
  4. Highlight the final result

▸ CONCEPTUAL QUESTIONS
  1. Intuitive analogy or real-world example first
  2. Formal definition with **key terms** in bold
  3. Common misconceptions (if any)

▸ GENERAL
  • Use LaTeX-style math where readable (e.g. E = mc^2, integral sign ∫, √)
  • Structure long answers with ## headers and numbered/bulleted lists
  • If the provided context answers the question, use it as your primary source
  • If context is insufficient, say so explicitly before drawing on general knowledge
  • End EVERY response with a "**Sources:**" section listing which document(s) you drew from

━━━━━━━━━━━━━━━━━━━━━━
"""


def check_ollama() -> tuple[bool, str]:
    """Return (is_running, error_message)."""
    try:
        ollama.list()
        return True, ""
    except Exception as exc:
        return False, str(exc)


def model_available(model: str = MODEL) -> bool:
    try:
        info = ollama.list()
        names = [m["name"] for m in info.get("models", [])]
        return any(model.split(":")[0] in n for n in names)
    except Exception:
        return False


def _build_user_message(
    query: str,
    context_chunks: List[dict],
    code_result: Optional[str] = None,
) -> str:
    parts: list[str] = []

    if context_chunks:
        parts.append("## Relevant Study Material\n")
        for i, chunk in enumerate(context_chunks, 1):
            rel = chunk.get("relevance", 0)
            src = chunk.get("source", "unknown")
            parts.append(
                f"### Excerpt {i} — *{src}* (relevance: {rel:.0%})\n"
                f"{chunk['text']}\n"
            )

    if code_result:
        parts.append(
            f"## Python Computation Result\n```\n{code_result}\n```\n"
        )

    parts.append(f"## Question\n{query}")
    return "\n".join(parts)


def stream_response(
    query: str,
    context_chunks: List[dict],
    code_result: Optional[str] = None,
) -> Generator[str, None, None]:
    """Yield response tokens one by one from Ollama."""
    user_msg = _build_user_message(query, context_chunks, code_result)

    stream = ollama.chat(
        model=MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_msg},
        ],
        stream=True,
    )
    for chunk in stream:
        content = chunk.get("message", {}).get("content", "")
        if content:
            yield content


def generate_solver_code(query: str, context: str) -> str:
    """
    Ask the LLM to produce executable Python that solves a numerical problem.
    Returns the raw LLM text (caller extracts code block).
    """
    prompt = (
        "You are a scientific Python programmer.\n"
        "Write ONLY a self-contained Python script that solves the problem below.\n"
        "• Import math / numpy as needed\n"
        "• Use clear variable names with comments\n"
        "• print() every intermediate result AND the final answer with units\n"
        "• Output ONLY a fenced ```python … ``` block — no prose.\n\n"
        f"Context from study notes:\n{context}\n\n"
        f"Problem: {query}"
    )
    resp = ollama.chat(
        model=MODEL,
        messages=[{"role": "user", "content": prompt}],
        stream=False,
    )
    return resp["message"]["content"]
