@echo off
rem The capture desk: review takes frame by frame, edit the shot list, fetch new footage, render.
rem Needs Python 3 and ffmpeg on the PATH ("winget install Gyan.FFmpeg", then a new window).
cd /d "%~dp0"
where python >nul 2>nul || (echo python was not found on the PATH. & pause & exit /b 1)
where ffmpeg >nul 2>nul || (echo ffmpeg was not found. Install it with:  winget install Gyan.FFmpeg   then open a new window and run this again. & pause & exit /b 1)
python tools\desk.py %*
if errorlevel 1 pause
