@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Study Assistant -- Dependency Installer

:: ── ANSI colours (one PowerShell call at startup; never again) ───────────────
for /f "delims=" %%e in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%e"
set "GREEN=%ESC%[92m"
set "CYAN=%ESC%[96m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "BOLD=%ESC%[1m"
set "R=%ESC%[0m"

:: ── Persistent log ────────────────────────────────────────────────────────────
set "LOGFILE=%~dp0install.log"
echo Install started: %DATE% %TIME% > "%LOGFILE%"

cls
echo.
echo %BOLD%  ============================================================%R%
echo %BOLD%        STUDY ASSISTANT  --  Dependency Installer%R%
echo %BOLD%  ============================================================%R%
echo.

:: ════════════════════════════════════════════════════════════════════════════
::  1.  Python
:: ════════════════════════════════════════════════════════════════════════════
call :info "Checking Python..."
python --version >nul 2>&1
if !errorlevel! neq 0 (
    call :err "Python not found in PATH."
    echo.
    echo   Install Python 3.10+:  https://www.python.org/downloads/
    echo   IMPORTANT: tick  [v] Add Python to PATH  during setup.
    goto :fail
)
:: tokens=2  grabs only "3.x.y" — avoids trailing ^M from Windows line endings
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set "PY_NUM=%%v"
call :ok "Python %PY_NUM% detected."

:: ════════════════════════════════════════════════════════════════════════════
::  2.  Virtual environment
:: ════════════════════════════════════════════════════════════════════════════
if exist ".venv\Scripts\python.exe" (
    call :ok "Virtual environment (.venv) already exists."
) else (
    call :info "Creating virtual environment (.venv)..."
    python -m venv .venv >> "%LOGFILE%" 2>&1
    if !errorlevel! neq 0 (
        call :err "Failed to create .venv -- see install.log"
        goto :fail
    )
    call :ok "Virtual environment created."
)

:: ════════════════════════════════════════════════════════════════════════════
::  3.  Activate
:: ════════════════════════════════════════════════════════════════════════════
call :info "Activating virtual environment..."
call ".venv\Scripts\activate.bat"
if !errorlevel! neq 0 (
    call :err "Could not activate .venv."
    goto :fail
)
call :ok "Virtual environment activated."

:: ════════════════════════════════════════════════════════════════════════════
::  4.  Pip upgrade
:: ════════════════════════════════════════════════════════════════════════════
call :info "Upgrading pip..."
python -m pip install --upgrade pip --quiet >> "%LOGFILE%" 2>&1
call :ok "pip up to date."

:: ════════════════════════════════════════════════════════════════════════════
::  5.  PyTorch CPU wheel
::      Must run BEFORE requirements.txt so that sentence-transformers finds
::      torch already satisfied and pip does not backtrack to a CUDA wheel.
:: ════════════════════════════════════════════════════════════════════════════
call :info "Installing PyTorch CPU build (~200 MB)..."
echo   Please wait...
pip install "torch>=2.1.0" --index-url https://download.pytorch.org/whl/cpu ^
    --prefer-binary --quiet >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 (
    call :warn "CPU wheel failed -- trying default PyPI torch..."
    pip install "torch>=2.1.0" --prefer-binary --quiet >> "%LOGFILE%" 2>&1
    if !errorlevel! neq 0 (
        call :err "PyTorch install failed -- see install.log"
        goto :fail
    )
)
call :ok "PyTorch installed."

:: ════════════════════════════════════════════════════════════════════════════
::  6.  All remaining dependencies
::      --quiet           no line-by-line flood
::      --prefer-binary   never compile C++ from source
::      --extra-index-url PyTorch CPU index so torch sub-deps don't backtrack
::
::      IMPORTANT: all labels in this section are at the TOP LEVEL (not inside
::      any if-block).  Labels inside (...) blocks terminate the block early
::      and cause unconditional execution -- that was the previous "always
::      fails" bug.
:: ════════════════════════════════════════════════════════════════════════════
call :info "Installing remaining packages (first run: 5-15 min)..."
echo   Please wait -- silence is normal...
echo.

set "PIP_LOG=%TEMP%\sa_pip_%RANDOM%.log"

pip install -r requirements.txt ^
    --prefer-binary ^
    --extra-index-url https://download.pytorch.org/whl/cpu ^
    --quiet > "%PIP_LOG%" 2>&1

set "PIP_RC=!errorlevel!"

:: Route: success vs failure  (no labels inside any if-block)
if !PIP_RC! neq 0 goto :pip_failed

:: ── pip succeeded ─────────────────────────────────────────────────────────
del "%PIP_LOG%" >nul 2>&1
call :ok "All packages installed."
goto :step7

:: ── pip failed: show output then diagnose ─────────────────────────────────
:pip_failed
call :warn "pip exited with errors (code %PIP_RC%) -- diagnosing..."
echo.
type "%PIP_LOG%"
type "%PIP_LOG%" >> "%LOGFILE%"
echo.

findstr /i "Microsoft Visual C++" "%PIP_LOG%" >nul 2>&1
if !errorlevel! == 0 goto :err_cpp

findstr /i "ResolutionImpossible" "%PIP_LOG%" >nul 2>&1
if !errorlevel! == 0 goto :err_conflict

findstr /i "Cannot install" "%PIP_LOG%" >nul 2>&1
if !errorlevel! == 0 goto :err_conflict

findstr /i "incompatible" "%PIP_LOG%" >nul 2>&1
if !errorlevel! == 0 goto :err_conflict

goto :err_generic

:err_cpp
call :err "A package needs C++ compilation -- no pre-built wheel available."
echo.
echo   %BOLD%FIX: Install Microsoft C++ Build Tools (free, ~6 GB)%R%
echo.
echo     1.  https://visualstudio.microsoft.com/visual-cpp-build-tools/
echo     2.  Run the installer
echo     3.  Select  "Desktop development with C++"
echo     4.  Click Install  (10-15 min, then reboot)
echo     5.  Re-run this installer
del "%PIP_LOG%" >nul 2>&1
goto :fail

:err_conflict
call :err "Package version conflict detected."
echo.
echo   Fix: delete .venv and re-run this script:
echo     rmdir /s /q .venv
echo     install-dependencies.bat
del "%PIP_LOG%" >nul 2>&1
goto :fail

:err_generic
call :err "Installation failed -- see install.log for the full error."
echo   Scroll up to find the first red error line above.
del "%PIP_LOG%" >nul 2>&1
goto :fail

:: ════════════════════════════════════════════════════════════════════════════
::  7.  Verify imports
:: ════════════════════════════════════════════════════════════════════════════
:step7
call :info "Verifying key imports..."
python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers" >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 (
    call :warn "Import check failed -- running per-package diagnostic..."
    echo.
    for %%p in (streamlit chromadb ollama fitz sentence_transformers) do (
        python -c "import %%p" >nul 2>&1
        if !errorlevel! neq 0 (
            call :err "MISSING: %%p"
        ) else (
            call :ok  "OK:      %%p"
        )
    )
    echo.
    echo   Re-run this installer after fixing the missing package(s) above.
    goto :fail
)
call :ok "All imports verified."

:: ════════════════════════════════════════════════════════════════════════════
::  8.  Ollama
:: ════════════════════════════════════════════════════════════════════════════
echo.
call :info "Checking Ollama..."
where ollama >nul 2>&1
if !errorlevel! neq 0 (
    call :warn "Ollama not found in PATH."
    echo.
    echo   Install : https://ollama.com/download
    echo   Then    : ollama pull llama3.1:8b
    goto :done
)
call :ok "Ollama is installed."

powershell -NoProfile -Command ^
  "try{$r=Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 3 -EA Stop; if($r.models.name -like '*llama3.1*'){exit 0}else{exit 2}}catch{exit 1}" >nul 2>&1
set "ORC=!errorlevel!"
if %ORC% == 0 (
    call :ok "Model llama3.1:8b is available."
) else if %ORC% == 2 (
    call :warn "Model not pulled yet.  Run:  ollama pull llama3.1:8b"
) else (
    call :info "Ollama not running -- model check skipped."
    echo         After starting Ollama run:  ollama pull llama3.1:8b
)

:: ════════════════════════════════════════════════════════════════════════════
::  Done
:: ════════════════════════════════════════════════════════════════════════════
:done
echo.
echo %BOLD%  ============================================================%R%
echo %GREEN%%BOLD%   SUCCESS! All dependencies installed.%R%
echo    Next: double-click start-project.bat to launch the app.
echo %BOLD%  ============================================================%R%
echo.
goto :end

:fail
echo.
echo %BOLD%  ============================================================%R%
echo %RED%%BOLD%   INSTALLATION FAILED.%R%
echo    Full log: %LOGFILE%
echo %BOLD%  ============================================================%R%
echo.

:end
echo Press any key to close this window...
pause >nul
exit /b

:: ════════════════════════════════════════════════════════════════════════════
::  Subroutines  (goto :eof returns to caller)
:: ════════════════════════════════════════════════════════════════════════════
:ok
echo %GREEN%  [ OK    ]%R% %~1
echo [OK] %~1 >> "%LOGFILE%"
goto :eof

:info
echo %CYAN%  [ INFO  ]%R% %~1
echo [INFO] %~1 >> "%LOGFILE%"
goto :eof

:warn
echo %YELLOW%  [ WARN  ]%R% %~1
echo [WARN] %~1 >> "%LOGFILE%"
goto :eof

:err
echo %RED%  [ ERROR ]%R% %~1
echo [ERROR] %~1 >> "%LOGFILE%"
goto :eof
