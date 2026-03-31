@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  KEEP WINDOW OPEN: re-launch inside a persistent cmd session
::  so the window never closes automatically on error.
:: ============================================================
if "%~1"=="--child" goto :main
cmd /k ""%~f0" --child"
exit

:main
cd /d "%~dp0"
title Study Assistant -- Dependency Installer

:: Log file for this run (always written, survives window close)
set LOGFILE=%~dp0install.log
echo. > "%LOGFILE%"
call :log INFO "Log file: %LOGFILE%"

call :print_header

:: ============================================================
::  1. Python check
:: ============================================================
call :log INFO "Checking Python..."
python --version >nul 2>&1
if %errorlevel% neq 0 (
    call :log ERROR "Python not found in PATH."
    echo.
    echo   Install Python 3.10+ from https://www.python.org/downloads/
    echo   IMPORTANT: tick  [v] Add Python to PATH  during install.
    goto :fail
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do (
    set PY_VER=%%v
    echo   %%v >> "%LOGFILE%"
)
call :log OK "%PY_VER% detected."

:: ============================================================
::  2. Create / reuse virtual environment
:: ============================================================
if exist ".venv\Scripts\python.exe" (
    call :log OK "Virtual environment (.venv) already exists."
) else (
    call :log INFO "Creating virtual environment (.venv) ..."
    python -m venv .venv >> "%LOGFILE%" 2>&1
    if !errorlevel! neq 0 (
        call :log ERROR "Failed to create venv. See %LOGFILE%"
        goto :fail
    )
    call :log OK "Virtual environment created."
)

:: ============================================================
::  3. Activate
:: ============================================================
call :log INFO "Activating virtual environment..."
call ".venv\Scripts\activate.bat"
if %errorlevel% neq 0 (
    call :log ERROR "Could not activate .venv."
    goto :fail
)
call :log OK "Virtual environment active."

:: ============================================================
::  4. Upgrade pip  (silent — almost never fails)
:: ============================================================
call :log INFO "Upgrading pip..."
python -m pip install --upgrade pip --quiet >> "%LOGFILE%" 2>&1
call :log OK "pip upgraded."

:: ============================================================
::  5. PyTorch — CPU wheel first (saves ~1.5 GB)
:: ============================================================
call :log INFO "Installing PyTorch CPU wheel..."
echo   (downloading ~200 MB — please wait)
pip install "torch>=2.1.0" --index-url https://download.pytorch.org/whl/cpu --prefer-binary >> "%LOGFILE%" 2>&1
if %errorlevel% neq 0 (
    call :log WARN "CPU wheel failed. Falling back to default PyPI torch..."
    pip install "torch>=2.1.0" --prefer-binary >> "%LOGFILE%" 2>&1
    if !errorlevel! neq 0 (
        call :log ERROR "PyTorch install failed. See %LOGFILE%"
        goto :fail
    )
)
call :log OK "PyTorch installed."

:: ============================================================
::  6. Main dependencies
::     --prefer-binary  — never compile C++ from source
::     No --quiet       — errors are visible AND logged
:: ============================================================
call :log INFO "Installing dependencies from requirements.txt ..."
echo   (first run may take 5-15 minutes)
echo.

:: Redirect pip output to a temp file, then print it so the user sees it.
:: This lets us grep the output afterward without running pip twice.
set PIP_TMP=%TEMP%\sa_pip_install.log
pip install -r requirements.txt --prefer-binary > "%PIP_TMP%" 2>&1
set PIP_EXIT=!errorlevel!

:: Show what pip printed
type "%PIP_TMP%"
:: Append to persistent log
type "%PIP_TMP%" >> "%LOGFILE%"

echo.
if !PIP_EXIT! neq 0 (
    call :log WARN "pip exited with code !PIP_EXIT!. Diagnosing..."
    echo.

    :: ---- Detect C++ build-tools error ----
    findstr /i "Microsoft Visual C++" "%PIP_TMP%" >nul 2>&1
    if !errorlevel! == 0 (
        call :log ERROR "A package requires C++ compilation — no pre-built wheel available."
        echo.
        echo  --------------------------------------------------------
        echo   FIX: Install Microsoft C++ Build Tools (free, ~6 GB)
        echo.
        echo   1. Go to:
        echo      https://visualstudio.microsoft.com/visual-cpp-build-tools/
        echo   2. Download and run the installer
        echo   3. Select  "Desktop development with C++"
        echo   4. Click Install  (takes ~10 min, needs reboot)
        echo   5. Re-run this installer
        echo  --------------------------------------------------------
        del "%PIP_TMP%" >nul 2>&1
        goto :fail
    )

    :: ---- Detect version-conflict error ----
    findstr /i "ResolutionImpossible\|conflict\|incompatible" "%PIP_TMP%" >nul 2>&1
    if !errorlevel! == 0 (
        call :log ERROR "pip could not resolve package versions."
        echo.
        echo   Try deleting .venv and running this installer again:
        echo     rmdir /s /q .venv
        del "%PIP_TMP%" >nul 2>&1
        goto :fail
    )

    :: ---- Generic failure ----
    call :log ERROR "Installation failed. Full log: %LOGFILE%"
    echo   Scroll up — the first red 'error:' line shows the cause.
    del "%PIP_TMP%" >nul 2>&1
    goto :fail
)

del "%PIP_TMP%" >nul 2>&1
call :log OK "All packages installed."

:: ============================================================
::  7. Verify imports
:: ============================================================
call :log INFO "Verifying imports..."
python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers" >> "%LOGFILE%" 2>&1
if %errorlevel% neq 0 (
    call :log WARN "Import check failed. Details:"
    python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers"
    echo.
    echo   ^ Fix any missing package shown above, then re-run this script.
) else (
    call :log OK "All imports verified."
)

:: ============================================================
::  8. Ollama check
:: ============================================================
echo.
call :log INFO "Checking Ollama..."
where ollama >nul 2>&1
if %errorlevel% neq 0 (
    call :log WARN "Ollama not found in PATH."
    echo.
    echo   Install: https://ollama.com/download
    echo   Then:    ollama pull llama3.1:8b
) else (
    call :log OK "Ollama found."
    powershell -NoProfile -Command ^
        "try{$r=Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 3 -EA Stop;if($r.models.name -like '*llama3.1*'){exit 0}else{exit 2}}catch{exit 1}" >nul 2>&1
    if !errorlevel! == 0 (
        call :log OK "Model llama3.1:8b already pulled."
    ) else if !errorlevel! == 2 (
        call :log WARN "Model not pulled yet. Run:  ollama pull llama3.1:8b"
    ) else (
        call :log INFO "Ollama not running — model check skipped."
        echo         After starting Ollama run:  ollama pull llama3.1:8b
    )
)

:: ============================================================
::  Done
:: ============================================================
echo.
echo  ==========================================================
echo   SUCCESS!  All dependencies installed.
echo   Next: double-click  start-project.bat  to launch the app.
echo  ==========================================================
echo.
pause
exit /b 0

:fail
echo.
echo  ==========================================================
echo   FAILED.  Full install log saved to:
echo   %LOGFILE%
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
echo.
goto :eof

:log
set "_lvl=%~1"
set "_msg=%~2"
echo [%_lvl%] %_msg% >> "%LOGFILE%"
if /i "%_lvl%"=="OK"    powershell -NoProfile -Command "Write-Host '  [ OK    ] ' -NoNewline -ForegroundColor Green;  Write-Host '%_msg%'"
if /i "%_lvl%"=="INFO"  powershell -NoProfile -Command "Write-Host '  [ INFO  ] ' -NoNewline -ForegroundColor Cyan;   Write-Host '%_msg%'"
if /i "%_lvl%"=="WARN"  powershell -NoProfile -Command "Write-Host '  [ WARN  ] ' -NoNewline -ForegroundColor Yellow; Write-Host '%_msg%'"
if /i "%_lvl%"=="ERROR" powershell -NoProfile -Command "Write-Host '  [ ERROR ] ' -NoNewline -ForegroundColor Red;    Write-Host '%_msg%'"
goto :eof
