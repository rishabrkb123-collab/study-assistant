@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Study Assistant -- Dependency Installer

:: ================================================================
::  ANSI colour codes  (set up once; no PowerShell spawn per line)
::  Works on Windows 10 / 11.  Falls back to plain text silently.
:: ================================================================
for /f "delims=" %%e in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%e"
set "GREEN=!ESC![92m" & set "CYAN=!ESC![96m" & set "YELLOW=!ESC![93m"
set "RED=!ESC![91m"   & set "BOLD=!ESC![1m"  & set "R=!ESC![0m"

:: ================================================================
::  Log file (written even if window closes)
:: ================================================================
set "LOGFILE=%~dp0install.log"
echo Install started: %DATE% %TIME% > "%LOGFILE%"

:: ================================================================
::  Header
:: ================================================================
cls
echo.
echo %BOLD%  ===========================================================%R%
echo %BOLD%         STUDY ASSISTANT -- Dependency Installer%R%
echo %BOLD%  ===========================================================%R%
echo.

:: ================================================================
::  1.  Python
:: ================================================================
call :info "Checking Python..."
python --version >nul 2>&1
if !errorlevel! neq 0 (
    call :error "Python not found in PATH."
    echo.
    echo   Install Python 3.10+ from: https://www.python.org/downloads/
    echo   IMPORTANT -- tick  [v] Add Python to PATH  during install.
    goto :fail
)
:: Use tokens=2 to grab only "3.x.y" — avoids capturing a trailing ^M
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set "PY_NUM=%%v"
call :ok "Python !PY_NUM! detected."

:: ================================================================
::  2.  Virtual environment
:: ================================================================
if exist ".venv\Scripts\python.exe" (
    call :ok "Virtual environment (.venv) already exists."
) else (
    call :info "Creating virtual environment (.venv)..."
    python -m venv .venv >> "%LOGFILE%" 2>&1
    if !errorlevel! neq 0 (
        call :error "Could not create .venv -- see install.log"
        goto :fail
    )
    call :ok "Virtual environment created."
)

:: ================================================================
::  3.  Activate
:: ================================================================
call :info "Activating virtual environment..."
call ".venv\Scripts\activate.bat"
if !errorlevel! neq 0 (
    call :error "Could not activate .venv."
    goto :fail
)
call :ok "Virtual environment activated."

:: ================================================================
::  4.  Upgrade pip
:: ================================================================
call :info "Upgrading pip..."
python -m pip install --upgrade pip --quiet >> "%LOGFILE%" 2>&1
call :ok "pip up to date."

:: ================================================================
::  5.  PyTorch CPU  (install before requirements.txt so
::      sentence-transformers does not pull the large CUDA wheel)
:: ================================================================
call :info "Installing PyTorch (CPU build -- ~200 MB vs ~2 GB CUDA)..."
pip install "torch>=2.1.0" --index-url https://download.pytorch.org/whl/cpu --prefer-binary --quiet >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 (
    call :warn "CPU wheel unavailable -- falling back to default PyPI torch..."
    pip install "torch>=2.1.0" --prefer-binary --quiet >> "%LOGFILE%" 2>&1
    if !errorlevel! neq 0 (
        call :error "PyTorch install failed -- see install.log"
        goto :fail
    )
)
call :ok "PyTorch installed."

:: ================================================================
::  6.  Main dependencies
::      Output goes to temp log AND the screen simultaneously
::      via a two-pass: run→log, then type the log.
:: ================================================================
call :info "Installing dependencies from requirements.txt..."
echo   (first run: 5-15 min depending on internet speed)
echo.

set "PIP_LOG=%TEMP%\sa_pip_%RANDOM%.log"
pip install -r requirements.txt --prefer-binary > "!PIP_LOG!" 2>&1
set "PIP_RC=!errorlevel!"

:: Print pip's full output so the user can see it
type "!PIP_LOG!"
type "!PIP_LOG!" >> "%LOGFILE%"
echo.

if !PIP_RC! neq 0 (
    call :warn "pip finished with errors (code !PIP_RC!). Diagnosing..."
    echo.

    findstr /i "Microsoft Visual C++" "!PIP_LOG!" >nul 2>&1
    if !errorlevel! == 0 (
        call :error "A package needs to be compiled from C++ source."
        echo.
        echo  !BOLD!  FIX -- install Microsoft C++ Build Tools (free, ~6 GB):!R!
        echo.
        echo    1.  https://visualstudio.microsoft.com/visual-cpp-build-tools/
        echo    2.  Run the installer
        echo    3.  Select  "Desktop development with C++"
        echo    4.  Click Install  (10-15 min)
        echo    5.  Reboot, then run this installer again
        echo.
        del "!PIP_LOG!" >nul 2>&1
        goto :fail
    )

    findstr /i "ResolutionImpossible\|Cannot install\|conflict\|incompatible" "!PIP_LOG!" >nul 2>&1
    if !errorlevel! == 0 (
        call :error "Package version conflict detected."
        echo.
        echo   Fix: delete .venv and re-run this script:
        echo     rmdir /s /q .venv
        echo     install-dependencies.bat
        del "!PIP_LOG!" >nul 2>&1
        goto :fail
    )

    call :error "Installation failed -- check install.log for details."
    echo   Scroll up to find the first  'ERROR' / 'error:'  line.
    del "!PIP_LOG!" >nul 2>&1
    goto :fail
)

del "!PIP_LOG!" >nul 2>&1
call :ok "All packages installed."

:: ================================================================
::  7.  Verify imports
:: ================================================================
call :info "Verifying key imports..."
python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers" >> "%LOGFILE%" 2>&1
if !errorlevel! neq 0 (
    call :warn "One or more packages failed to import. Running diagnostic..."
    echo.
    for %%p in (streamlit chromadb ollama fitz sentence_transformers) do (
        python -c "import %%p" >nul 2>&1
        if !errorlevel! neq 0 (
            call :error "  MISSING: %%p"
        ) else (
            call :ok   "  OK:      %%p"
        )
    )
    echo.
    echo   Re-run this installer after fixing the missing package(s).
    goto :fail
)
call :ok "All imports verified."

:: ================================================================
::  8.  Ollama check
:: ================================================================
echo.
call :info "Checking Ollama..."
where ollama >nul 2>&1
if !errorlevel! neq 0 (
    call :warn "Ollama not found in PATH."
    echo.
    echo   Install: https://ollama.com/download
    echo   Then:    ollama pull llama3.1:8b
) else (
    call :ok "Ollama is installed."
    powershell -NoProfile -Command ^
      "try{$r=Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 3 -EA Stop;if($r.models.name -like '*llama3.1*'){exit 0}else{exit 2}}catch{exit 1}" >nul 2>&1
    if !errorlevel! == 0 (
        call :ok "Model llama3.1:8b is available."
    ) else if !errorlevel! == 2 (
        call :warn "Model not pulled yet.  Run:  ollama pull llama3.1:8b"
    ) else (
        call :info "Ollama not running (model check skipped)."
        echo         After starting Ollama run:  ollama pull llama3.1:8b
    )
)

:: ================================================================
::  Done
:: ================================================================
echo.
echo %BOLD%  ===========================================================%R%
echo %GREEN%%BOLD%   SUCCESS!  All dependencies installed.%R%
echo    Next: double-click  start-project.bat  to launch the app.
echo %BOLD%  ===========================================================%R%
echo.
goto :end

:fail
echo.
echo %BOLD%  ===========================================================%R%
echo %RED%%BOLD%   INSTALLATION FAILED.%R%
echo    Full log: %LOGFILE%
echo %BOLD%  ===========================================================%R%
echo.

:end
echo Press any key to close this window...
pause >nul
exit /b

:: ================================================================
::  Subroutines  (all must end with goto :eof)
:: ================================================================

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

:error
echo %RED%  [ ERROR ]%R% %~1
echo [ERROR] %~1 >> "%LOGFILE%"
goto :eof
