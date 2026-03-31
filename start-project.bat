@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Study Assistant -- Starting Up

call :print_header

:: ============================================================
::  1. Verify Python
:: ============================================================
call :log INFO "Checking Python..."
python --version >nul 2>&1
if %errorlevel% neq 0 (
    call :log ERROR "Python not found in PATH."
    echo.
    echo   Install Python 3.10+ from https://www.python.org/downloads/
    echo   Make sure to tick "Add Python to PATH".
    goto :fail
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do set PY_VER=%%v
call :log OK "Found %PY_VER%"

:: ============================================================
::  2. Activate virtual environment (if present)
:: ============================================================
if exist ".venv\Scripts\activate.bat" (
    call .venv\Scripts\activate.bat
    call :log OK "Virtual environment (.venv) activated."
) else (
    call :log WARN "No .venv found -- using system Python."
    echo         Run install-dependencies.bat to set up a proper environment.
)

:: ============================================================
::  3. Check core dependencies
:: ============================================================
call :log INFO "Verifying dependencies..."
python -c "import streamlit" >nul 2>&1
if %errorlevel% neq 0 (
    call :log WARN "Dependencies not installed. Launching installer now..."
    echo.
    call install-dependencies.bat
    if !errorlevel! neq 0 (
        call :log ERROR "Installer failed. Cannot start."
        goto :fail
    )
    :: Re-activate venv after install
    if exist ".venv\Scripts\activate.bat" call .venv\Scripts\activate.bat
)

python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers" >nul 2>&1
if %errorlevel% neq 0 (
    call :log ERROR "One or more required packages are missing even after install."
    echo   Run install-dependencies.bat manually for details.
    goto :fail
)
call :log OK "All dependencies OK."

:: ============================================================
::  4. Ensure Ollama is running
:: ============================================================
call :log INFO "Checking Ollama service..."

powershell -NoProfile -Command "try { Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 3 -EA Stop | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if %errorlevel% == 0 (
    call :log OK "Ollama is already running."
    goto :check_model
)

:: Not running -- try to start it
call :log INFO "Ollama not running. Attempting to start..."

:: Try common install paths on Windows
set OLLAMA_EXE=
where ollama >nul 2>&1 && set OLLAMA_EXE=ollama
if "!OLLAMA_EXE!"=="" (
    if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" (
        set OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe
    )
)
if "!OLLAMA_EXE!"=="" (
    if exist "%ProgramFiles%\Ollama\ollama.exe" (
        set OLLAMA_EXE=%ProgramFiles%\Ollama\ollama.exe
    )
)

if "!OLLAMA_EXE!"=="" (
    call :log WARN "Ollama executable not found."
    echo         Install from https://ollama.com/download
    echo         The app will start but LLM features will not work.
    goto :find_port
)

start "" /B "!OLLAMA_EXE!" serve >nul 2>&1
call :log INFO "Waiting for Ollama to initialise..."

:: Poll up to 15 s
set /a _wait=0
:wait_ollama
timeout /t 2 /nobreak >nul
set /a _wait+=2
powershell -NoProfile -Command "try { Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 2 -EA Stop | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if %errorlevel% == 0 (
    call :log OK "Ollama started successfully."
    goto :check_model
)
if !_wait! lss 15 goto :wait_ollama

call :log WARN "Ollama did not respond within 15 s. Continuing anyway..."
goto :find_port

:check_model
:: ============================================================
::  5. Verify llama3.1:8b is pulled
:: ============================================================
call :log INFO "Checking for model llama3.1:8b..."
powershell -NoProfile -Command "try { $r = Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 5 -EA Stop; if (($r.models | Where-Object { $_.name -like '*llama3.1*' }) ) { exit 0 } else { exit 1 } } catch { exit 2 }" >nul 2>&1
if %errorlevel% == 0 (
    call :log OK "Model llama3.1:8b is available."
) else if %errorlevel% == 1 (
    call :log WARN "Model llama3.1:8b is NOT pulled."
    echo.
    echo   The app will launch but LLM answers will fail until you run:
    echo       ollama pull llama3.1:8b
    echo   (downloads ~4.7 GB -- run in a separate terminal)
    echo.
    timeout /t 4 /nobreak >nul
) else (
    call :log WARN "Could not verify model list. Continuing..."
)

:: ============================================================
::  6. Find an available port (start at 8501, scan to 8600)
:: ============================================================
:find_port
call :log INFO "Finding available port..."
set PORT=8501

:port_loop
powershell -NoProfile -Command ^
  "try { $l=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,%PORT%); $l.Start(); $l.Stop(); exit 0 } catch { exit 1 }" >nul 2>&1
if %errorlevel% == 0 (
    call :log OK "Port !PORT! is free."
    goto :launch
)
call :log INFO "Port !PORT! is busy -- trying next..."
set /a PORT+=1
if !PORT! gtr 8600 (
    call :log ERROR "No free port found in range 8501-8600."
    goto :fail
)
goto :port_loop

:: ============================================================
::  7. Launch Streamlit
:: ============================================================
:launch
echo.
echo  ==========================================================
echo   Launching Study Assistant
echo   URL : http://localhost:!PORT!
echo  ==========================================================
echo.

:: Open browser after a short delay (Streamlit needs a moment)
powershell -NoProfile -Command "Start-Sleep 3; Start-Process 'http://localhost:!PORT!'" >nul 2>&1 &

streamlit run app.py ^
    --server.port !PORT! ^
    --server.headless true ^
    --browser.gatherUsageStats false

:: If Streamlit exits (user closed it), pause so window stays open
echo.
call :log INFO "Streamlit has exited."
pause
exit /b 0

:: ============================================================
::  Failure handler
:: ============================================================
:fail
echo.
echo  ==========================================================
echo   Startup FAILED. See messages above.
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
echo           STUDY ASSISTANT -- Startup Launcher
echo.
echo  ==========================================================
echo.
goto :eof

:log
set "_lvl=%~1"
set "_msg=%~2"
if /i "%_lvl%"=="OK"    powershell -NoProfile -Command "Write-Host '  [ OK    ] ' -NoNewline -ForegroundColor Green;  Write-Host '%_msg%'"
if /i "%_lvl%"=="INFO"  powershell -NoProfile -Command "Write-Host '  [ INFO  ] ' -NoNewline -ForegroundColor Cyan;   Write-Host '%_msg%'"
if /i "%_lvl%"=="WARN"  powershell -NoProfile -Command "Write-Host '  [ WARN  ] ' -NoNewline -ForegroundColor Yellow; Write-Host '%_msg%'"
if /i "%_lvl%"=="ERROR" powershell -NoProfile -Command "Write-Host '  [ ERROR ] ' -NoNewline -ForegroundColor Red;    Write-Host '%_msg%'"
goto :eof
