@echo off
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
 echo Install Python 3.10 or newer from python.org, then run this file again.
 pause
 exit /b 1
)
echo Keep this window open while MT5 is running.
echo Source status: http://127.0.0.1:8765/events
py -3 service.py --db "%LOCALAPPDATA%\sniper-news.sqlite3" --port 8765
pause
