@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  start "Body Tone Fitness" cmd /k "py -m http.server 5500"
) else (
  where python >nul 2>nul
  if %errorlevel%==0 (
    start "Body Tone Fitness" cmd /k "python -m http.server 5500"
  ) else (
    echo Python is not installed.
    echo Use VS Code Live Server instead.
    pause
    exit /b 1
  )
)
timeout /t 2 >nul
start "" "http://127.0.0.1:5500/index.html"
