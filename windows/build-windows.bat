@echo off
rem Builds CyberNeonPlayer.exe and, if Inno Setup is installed, the installer CyberNeonPlayer-Setup.exe
rem Needs: Python 3.10-3.13 (python.org, tick "Add python.exe to PATH"). Run by double-click.
setlocal
cd /d "%~dp0.."

where python >nul 2>&1
if errorlevel 1 (
  echo Python was not found. Install it from https://www.python.org/downloads/ and tick "Add python.exe to PATH".
  pause & exit /b 1
)

python -m venv build\venv || goto :fail
call build\venv\Scripts\activate.bat
python -m pip install --upgrade pip || goto :fail
pip install -r windows\requirements.txt || goto :fail

pyinstaller --noconfirm --clean --windowed --name CyberNeonPlayer ^
  --icon windows\cyberneon-player.ico ^
  --add-data "Main.qml;." --add-data "NeonButton.qml;." --add-data "NeonSlider.qml;." ^
  --add-data "NeonField.qml;." --add-data "NeonBars.qml;." --add-data "Blob.qml;." ^
  --add-data "cyberneon-player.svg;." ^
  --collect-data PySide6 --collect-submodules PySide6.QtQuick --collect-submodules PySide6.QtMultimedia ^
  main.py || goto :fail

echo.
echo Built: dist\CyberNeonPlayer\CyberNeonPlayer.exe

set ISCC=
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe
if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" set ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe
if "%ISCC%"=="" (
  echo.
  echo Inno Setup not found, so no installer yet. Install it ^(free^): winget install JRSoftware.InnoSetup
  echo then run this file again. The program itself already works: dist\CyberNeonPlayer\CyberNeonPlayer.exe
  pause & exit /b 0
)
"%ISCC%" windows\installer.iss || goto :fail
echo.
echo Installer: windows\Output\CyberNeonPlayer-Setup.exe
pause & exit /b 0

:fail
echo.
echo Build failed, see the messages above.
pause & exit /b 1
