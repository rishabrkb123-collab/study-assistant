@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Study Assistant -- Starting Up

:: ── ANSI colours (one PowerShell call; never spawned per log line) ───────────
for /f "delims=" %%e in ('powershell -NoProfile -Command "[char]27"') do set "ESC=%%e"
set "GREEN=%ESC%[92m"
set "CYAN=%ESC%[96m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "BOLD=%ESC%[1m"
set "R=%ESC%[0m"

cls
echo.
echo %BOLD%  ============================================================%R%
echo %BOLD%        STUDY ASSISTANT  --  Startup Launcher%R%
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
    echo   Install Python 3.10+: https://www.python.org/downloads/
    echo   Tick [v] Add Python to PATH during setup.
    goto :fail
)
:: tokens=2 grabs only "3.x.y" -- avoids trailing ^M carriage-return
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set "PY_NUM=%%v"
call :ok "Python %PY_NUM% detected."

:: ════════════════════════════════════════════════════════════════════════════
::  2.  Activate virtual environment
:: ════════════════════════════════════════════════════════════════════════════
if exist ".venv\Scripts\activate.bat" (
    call ".venv\Scripts\activate.bat"
    call :ok "Virtual environment activated."
) else (
    call :warn "No .venv found -- using system Python."
    echo         Run install-dependencies.bat first.
)

:: ════════════════════════════════════════════════════════════════════════════
::  3.  Check / install dependencies
:: ════════════════════════════════════════════════════════════════════════════
call :info "Verifying dependencies..."
python -c "import streamlit" >nul 2>&1
if !errorlevel! neq 0 (
    call :warn "Streamlit not found -- launching installer..."
    echo.
    call "%~dp0install-dependencies.bat"
    if !errorlevel! neq 0 (
        call :err "Installer failed. Run install-dependencies.bat manually."
        goto :fail
    )
    if exist ".venv\Scripts\activate.bat" call ".venv\Scripts\activate.bat"
)

python -c "import streamlit, chromadb, ollama, fitz, sentence_transformers" >nul 2>&1
if !errorlevel! neq 0 (
    call :err "Required packages missing even after install."
    echo   Run install-dependencies.bat manually to see what failed.
    goto :fail
)
call :ok "All dependencies verified."

:: ════════════════════════════════════════════════════════════════════════════
::  4.  Ollama
:: ════════════════════════════════════════════════════════════════════════════
call :info "Checking Ollama..."
powershell -NoProfile -Command ^
  "try{Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 3 -EA Stop|Out-Null;exit 0}catch{exit 1}" >nul 2>&1
if !errorlevel! == 0 (
    call :ok "Ollama is running."
    goto :check_model
)

:: Not running -- locate and start it
call :info "Ollama not running. Attempting to start..."
set "OLLAMA_EXE="
where ollama >nul 2>&1
if !errorlevel! == 0 set "OLLAMA_EXE=ollama"
if not defined OLLAMA_EXE (
    if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" (
        set "OLLAMA_EXE=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"
    )
)
if not defined OLLAMA_EXE (
    if exist "%ProgramFiles%\Ollama\ollama.exe" (
        set "OLLAMA_EXE=%ProgramFiles%\Ollama\ollama.exe"
    )
)

if not defined OLLAMA_EXE (
    call :warn "Ollama not found. Install: https://ollama.com/download"
    echo         The app will start but LLM features need Ollama running.
    goto :find_port
)

start "" /b "!OLLAMA_EXE!" serve >nul 2>&1
call :info "Waiting for Ollama to start (up to 15s)..."

set "_w=0"
:wait_ollama
timeout /t 2 /nobreak >nul
set /a "_w+=2"
powershell -NoProfile -Command ^
  "try{Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 2 -EA Stop|Out-Null;exit 0}catch{exit 1}" >nul 2>&1
if !errorlevel! == 0 (
    call :ok "Ollama started."
    goto :check_model
)
if !_w! lss 15 goto :wait_ollama
call :warn "Ollama did not respond within 15s. Continuing anyway..."
goto :find_port

:: ════════════════════════════════════════════════════════════════════════════
::  5.  Model check
:: ════════════════════════════════════════════════════════════════════════════
:check_model
powershell -NoProfile -Command ^
  "try{$r=Invoke-RestMethod http://localhost:11434/api/tags -TimeoutSec 5 -EA Stop;if($r.models|Where-Object{$_.name -like '*llama3.1*'}){exit 0}else{exit 1}}catch{exit 2}" >nul 2>&1
if !errorlevel! == 0 (
    call :ok "Model llama3.1:8b is available."
) else if !errorlevel! == 1 (
    call :warn "Model llama3.1:8b is NOT pulled yet."
    echo.
    echo   Run in a separate terminal:  ollama pull llama3.1:8b
    echo   (~4.7 GB download -- app will work once the pull finishes)
    echo.
    timeout /t 3 /nobreak >nul
) else (
    call :warn "Could not verify model -- continuing anyway."
)

:: ════════════════════════════════════════════════════════════════════════════
::  6.  Find free port  (8501 -> 8600)
:: ════════════════════════════════════════════════════════════════════════════
:find_port
call :info "Finding available port..."
set "PORT=8501"

:port_loop
powershell -NoProfile -Command ^
  "try{$l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,!PORT!);$l.Start();$l.Stop();exit 0}catch{exit 1}" >nul 2>&1
if !errorlevel! == 0 (
    call :ok "Port !PORT! is free."
    goto :launch
)
call :info "Port !PORT! is busy -- trying next..."
set /a "PORT+=1"
if !PORT! gtr 8600 (
    call :err "No free port found in range 8501-8600."
    goto :fail
)
goto :port_loop

:: ════════════════════════════════════════════════════════════════════════════
::  7.  Launch
:: ════════════════════════════════════════════════════════════════════════════
:launch
echo.
echo %BOLD%  ============================================================%R%
echo %GREEN%%BOLD%   Launching Study Assistant%R%
echo   URL: http://localhost:!PORT!
echo %BOLD%  ============================================================%R%
echo.

:: Open browser in BACKGROUND after 3s so Streamlit starts first.
:: "start /b" detaches the process -- no blocking, no sequential &-trick.
start /b "" powershell -NoProfile -WindowStyle Hidden ^
  -Command "Start-Sleep 3; Start-Process 'http://localhost:!PORT!'"

streamlit run app.py ^
    --server.port !PORT! ^
    --server.headless true ^
    --browser.gatherUsageStats false

echo.
call :info "Streamlit exited."
goto :end

:: ════════════════════════════════════════════════════════════════════════════
::  Exit paths
:: ════════════════════════════════════════════════════════════════════════════
:fail
echo.
echo %BOLD%  ============================================================%R%
echo %RED%%BOLD%   STARTUP FAILED. See messages above.%R%
echo %BOLD%  ============================================================%R%
echo.

:end
echo Press any key to close this window...
pause >nul
exit /b

:: ════════════════════════════════════════════════════════════════════════════
::  Subroutines
:: ════════════════════════════════════════════════════════════════════════════
:ok
echo %GREEN%  [ OK    ]%R% %~1
goto :eof

:info
echo %CYAN%  [ INFO  ]%R% %~1
goto :eof

:warn
echo %YELLOW%  [ WARN  ]%R% %~1
goto :eof

:err
echo %RED%  [ ERROR ]%R% %~1
goto :eof
