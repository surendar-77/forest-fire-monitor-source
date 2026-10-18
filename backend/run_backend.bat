@echo off
rem Runs the Forest Fire backend service on Windows, restarting it if it exits.
rem Point GOOGLE_APPLICATION_CREDENTIALS at the service-account key (keep the
rem key OUTSIDE this repository), either here or before calling this script.

if not defined GOOGLE_APPLICATION_CREDENTIALS set GOOGLE_APPLICATION_CREDENTIALS=C:\secure\forest-fire-service-account.json
if not defined POLL_SECONDS set POLL_SECONDS=60
set PYTHONUNBUFFERED=1

cd /d "%~dp0"
if not exist .venv (
  python -m venv .venv
  .venv\Scripts\pip install -r requirements.txt
)

:loop
.venv\Scripts\python -m forest_fire_backend.service
echo Service stopped (exit code %errorlevel%). Restarting in 30 seconds...
timeout /t 30 /nobreak >nul
goto loop
