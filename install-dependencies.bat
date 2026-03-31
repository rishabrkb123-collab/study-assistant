@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Study Assistant -- Dependency Installer

:: ============================================================
::  Colours via PowerShell helper (works on all modern Windows)
:: ============================================================
call :print_header
echo.

:: ============================================================
::  1. Verify Python
:: ============================================================
call :log INFO "Checking Python installation..."
python --version >nul 2>&1
if %errorlevel% neq 0 (
    call :log ERROR "Python not found in PATH."
    echo.
    echo   Please install Python 3.10 or newer from:
    echo   https://www.python.org/downloads/
    echo   IMPORTANT: Check "Add Python to PATH" during installation.
    echo.
    goto :fail
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do set PY_VER=%%v
call :log OK "Found %PY_VER%"

:: ============================================================
::  2. Create virtual environment
:: ============================================================
if exist ".venv\Scripts\python.exe" (
    call :log OK "Virtual environment already exists (.venv)"
) else (
    call :log INFO "Creating virtual environment (.venv)..."
    python -m venv .venv
    if !errorlevel! neq 0 (
        call :log ERROR "Failed to create virtual environment."
        goto :fail
    )
    call :log OK "Virtual environment created."
)

:: ============================================================
::  3. Activate virtual environment
:: ============================================================
call :log INFO "Activating virtual environment..."
call .venv\Scripts\activate.bat
if %errorlevel% neq 0 (
    call :log ERROR "Could not activate virtual environment."
    goto :fail
)
call :log OK "Virtual environment activated."

:: ============================================================
::  4. Upgrade pip
:: ============================================================
call :log INFO "Upgrading pip..."
python -m pip install --upgrade pip --quiet
call :log OK "pip is up to date."

:: ============================================================
::  5. Install PyTorch (CPU-only to save ~1.5 GB)
:: ============================================================
call :log INFO "Installing PyTorch (CPU build -- saves ~1.5 GB vs CUDA)..."
pip install torch --index-url https://download.pytorch.org/whl/cpu --quiet
if %errorlevel% neq 0 (
    call :log WARN "CPU wheel failed. Falling back to default PyTorch from PyPI..."
    pip install torch --quiet
    if !errorlevel! neq 0 (
        call :log ERROR "PyTorch installation failed."
        goto :fail
    )
)
call :log OK "PyTorch installed."

:: ============================================================
::  6. Install all remaining dependencies
:: ============================================================
call :log INFO "Installing remaining dependencies from requirements.txt..."
echo       (this may take several minutes on first run)
echo.
pip install -r requirements.txt --quiet
if %errorlevel% neq 0 (
    call :log ERROR "Dependency installation failed."
    echo.
    echo   Try running manually for details:
    echo   pip install -r requirements.txt
    echo.
    goto :fail
)
call :log OK "All dependencies installed."

:: ============================================================
::  7. Verify key imports
:: ============================================================
call :log INFO "Verifying key packages..."
python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers, langchain" >nul 2>&1
if %errorlevel% neq 0 (
    call :log WARN "Some packages may not have installed correctly."
    echo   Run: python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers"
    echo   to see which package is missing.
) else (
    call :log OK "All key packages verified."
)

:: ============================================================
::  8. Check Ollama
:: ============================================================
echo.
call :log INFO "Checking Ollama..."
where ollama >nul 2>&1
if %errorlevel% neq 0 (
    call :log WARN "Ollama is not installed or not in PATH."
    echo.
    echo   Install Ollama from: https://ollama.com/download
    echo   Then run:  ollama pull llama3.1:8b
    echo.
) else (
    call :log OK "Ollama found in PATH."
    call :log INFO "Checking for model llama3.1:8b..."
    powershell -NoProfile -Command "try { $r = Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 3 -EA Stop; if ($r.models.name -like '*llama3.1*') { exit 0 } else { exit 2 } } catch { exit 1 }" >nul 2>&1
    if !errorlevel! == 0 (
        call :log OK "Model llama3.1:8b is already pulled."
    ) else if !errorlevel! == 2 (
        call :log WARN "Model llama3.1:8b not found. Pull it with:"
        echo         ollama pull llama3.1:8b
    ) else (
        call :log INFO "Ollama is not running yet -- model check skipped."
        echo         Start Ollama and run:  ollama pull llama3.1:8b
    )
)

:: ============================================================
::  Done
:: ============================================================
echo.
echo  ==========================================================
echo   Installation complete!
echo   Double-click start-project.bat to launch the assistant.
echo  ==========================================================
echo.
pause
exit /b 0

:fail
echo.
echo  ==========================================================
echo   Installation FAILED. See errors above.
echo  ==========================================================
echo.
pause
exit /b 1

:: ============================================================
::  Helpers
:: ============================================================
:print_header
cls
echo  ==========================================================
echo.
echo        STUDY ASSISTANT -- Dependency Installer
echo.
echo  ==========================================================
goto :eof

:log
:: Usage: call :log LEVEL "message"
set "_lvl=%~1"
set "_msg=%~2"
if /i "%_lvl%"=="OK"    powershell -NoProfile -Command "Write-Host '  [ OK    ] ' -NoNewline -ForegroundColor Green;  Write-Host '%_msg%'"
if /i "%_lvl%"=="INFO"  powershell -NoProfile -Command "Write-Host '  [ INFO  ] ' -NoNewline -ForegroundColor Cyan;   Write-Host '%_msg%'"
if /i "%_lvl%"=="WARN"  powershell -NoProfile -Command "Write-Host '  [ WARN  ] ' -NoNewline -ForegroundColor Yellow; Write-Host '%_msg%'"
if /i "%_lvl%"=="ERROR" powershell -NoProfile -Command "Write-Host '  [ ERROR ] ' -NoNewline -ForegroundColor Red;    Write-Host '%_msg%'"
goto :eof
