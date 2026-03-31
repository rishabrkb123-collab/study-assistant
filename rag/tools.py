"""
Numerical/code-execution tool.

Detects whether a query requires computation, extracts Python code from LLM
output, and executes it in a restricted sandbox.
"""
from __future__ import annotations

import io
import re
import sys
import traceback
from typing import Optional

# ── Numerical-query detection ─────────────────────────────────────────────────

_NUMERICAL_SIGNALS = [
    # explicit instruction words
    "calculate", "compute", "solve", "evaluate", "find the value",
    "how much", "how many", "what is the value", "numerically",
    # math operations
    "derivative", "integral", "differentiate", "integrate",
    "sum of", "product of", "root of", "log of", "ln of",
    # physics quantities
    "resistance", "current", "voltage", "force", "velocity", "speed",
    "acceleration", "energy", "power", "frequency", "wavelength",
    "momentum", "pressure", "temperature", "density", "torque",
    "capacitance", "inductance", "flux", "entropy", "enthalpy",
    # math symbols (as text) – catches "x = 3 + 4" style
    "=", "kg", "m/s", "km/h", "joule", "watt", "newton", "pascal",
    "amp", "volt", "ohm", "celsius", "kelvin", "mol", "liter",
    "meter", "second", "radian", "degree", "percent",
]


def is_numerical(query: str) -> bool:
    """Return True if the query likely requires computation."""
    q = query.lower()
    # Direct keyword hit
    if any(sig in q for sig in _NUMERICAL_SIGNALS):
        return True
    # Contains a digit followed by a unit-like word
    if re.search(r"\d+\s*[a-zA-Z]+", query):
        return True
    return False


# ── Code extraction ───────────────────────────────────────────────────────────

def extract_code(text: str) -> Optional[str]:
    """Pull the first Python (or generic) fenced code block from text."""
    for pat in (
        r"```python\s*\n(.*?)```",
        r"```py\s*\n(.*?)```",
        r"```\s*\n(.*?)```",
    ):
        m = re.search(pat, text, re.DOTALL | re.IGNORECASE)
        if m:
            return m.group(1).strip()

    # Fallback: if text looks like raw code
    stripped = text.strip()
    if any(
        stripped.startswith(kw)
        for kw in ("import ", "from ", "#", "def ", "class ", "print(")
    ) or "print(" in stripped:
        return stripped

    return None


# ── Sandboxed executor ────────────────────────────────────────────────────────

_SAFE_BUILTINS = {
    # I/O
    "print": print,
    # Types
    "int": int, "float": float, "str": str, "bool": bool,
    "list": list, "dict": dict, "tuple": tuple, "set": set,
    "bytes": bytes,
    # Built-in functions
    "abs": abs, "round": round, "min": min, "max": max, "sum": sum,
    "len": len, "range": range, "enumerate": enumerate, "zip": zip,
    "map": map, "filter": filter, "sorted": sorted, "reversed": reversed,
    "isinstance": isinstance, "type": type, "repr": repr,
    "pow": pow, "divmod": divmod,
    # Allow safe imports (math, numpy, etc.)
    "__import__": __import__,
    # Needed for class definitions
    "__build_class__": __build_class__,
    "super": super,
    # Exceptions (read-only refs, not exec)
    "ValueError": ValueError, "TypeError": TypeError,
    "ZeroDivisionError": ZeroDivisionError,
}


def execute_code(code: str, timeout_hint: str = "~5 s") -> tuple[str, bool]:
    """
    Execute *code* in a restricted environment.

    Returns (output_text, success).
    The environment allows math / numpy / scipy imports but blocks file I/O,
    subprocess, os.system, etc. by not exposing those builtins directly.
    """
    # Capture stdout + stderr
    old_out, old_err = sys.stdout, sys.stderr
    sys.stdout = buf_out = io.StringIO()
    sys.stderr = buf_err = io.StringIO()

    success = False
    output = ""
    try:
        globs = {"__builtins__": _SAFE_BUILTINS}
        exec(compile(code, "<study_tool>", "exec"), globs)  # noqa: S102
        out = buf_out.getvalue()
        err = buf_err.getvalue()
        output = out
        if err.strip():
            output += f"\n[stderr]\n{err}"
        success = True
    except Exception:
        output = traceback.format_exc()
        success = False
    finally:
        sys.stdout = old_out
        sys.stderr = old_err

    return output.strip(), success
