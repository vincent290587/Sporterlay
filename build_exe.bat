@echo off
rem Build dist\Sporterlay.exe (single file). Run on Windows.
cd /d "%~dp0"
if not exist .venv py -3 -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt pyinstaller || exit /b 1
.venv\Scripts\pyinstaller --noconfirm --onefile --windowed --name Sporterlay ^
  --collect-all libusb_package --collect-submodules openant --collect-submodules usb --collect-all bleak --collect-submodules winrt ^
  --add-data "workouts;workouts" launcher.py
echo.
echo Built dist\Sporterlay.exe
