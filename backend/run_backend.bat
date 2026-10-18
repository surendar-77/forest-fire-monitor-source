@echo off
rem Runs the Forest Fire backend service on Windows, restarting it if it exits.
rem Set the key path below (keep the key OUTSIDE this repository), then
rem double-click, or add to Task Scheduler "At startup" to run unattended.

set GOOGLE_APPLICATION_CREDENTIALS=C:\secure\forest-fire-service-account.json
set POLL_SECONDS=60

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
