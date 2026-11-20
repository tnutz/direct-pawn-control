@echo off
rem The test bench: runs test jobs in Dragon's Dogma 2 with nobody at the PC, restarts the game after a crash.
rem Leave this window open. Ctrl+C stops it. Jobs: the game's reframework\data\bench\jobs folder.
rem (The capture desk has the same bench in its "Test bench" panel; use one or the other.)
cd /d "%~dp0"
where python >nul 2>nul || (echo python was not found on the PATH. & pause & exit /b 1)
python tools\bench.py %*
if errorlevel 1 pause
