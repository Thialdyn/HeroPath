@echo off
cd /d "%~dp0"
start "" http://127.0.0.1:8080/
where py >nul 2>nul && (py -m http.server 8080 --bind 127.0.0.1) || (python -m http.server 8080 --bind 127.0.0.1)
