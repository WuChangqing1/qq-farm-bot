@echo off
cd /d "%~dp0"
node daily-report.js
if errorlevel 1 (
  echo.
  echo Report generation failed.
  pause
  exit /b 1
)
start "" explorer "core\data\daily"
timeout /t 6 >nul
