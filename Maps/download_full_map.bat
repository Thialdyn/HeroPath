@echo off
cd /d "%~dp0"
where py >nul 2>nul && (py download_full_map.py) || (python download_full_map.py)
