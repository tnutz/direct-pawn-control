@echo off
rem No page: fetch the new footage (take log, marks, browser copies) and render out\final.mp4 with the current edit.
rem The same two steps as "Get new footage" and "Render video" in capture_desk.bat.
cd /d "%~dp0"
where python >nul 2>nul || (echo python was not found on the PATH. & pause & exit /b 1)
where ffmpeg >nul 2>nul || (echo ffmpeg was not found. Install it with:  winget install Gyan.FFmpeg   then open a new window and run this again. & pause & exit /b 1)
python tools\desk.py --once
pause
