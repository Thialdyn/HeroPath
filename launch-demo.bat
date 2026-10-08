@echo off
cd /d "%~dp0"
where py >nul 2>nul && (py -3 launch-demo.py & goto :eof)
python launch-demo.py
