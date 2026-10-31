@echo off
rem Run Sporterlay from source on Windows (needs Python 3.10+ from python.org).
cd /d "%~dp0"
if not exist .venv (
    py -3 -m venv .venv || goto :err
    .venv\Scripts\python -m pip install --upgrade pip
    .venv\Scripts\python -m pip install -r requirements.txt || goto :err
)
start "" .venv\Scripts\pythonw -m sporterlay %*
exit /b 0
:err
echo Setup failed. Is Python installed? https://www.python.org/downloads/
pause
