@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
if not exist logs mkdir logs
if not exist "tools\win\run.bat" goto nosetup
if not exist ".git" goto nosetup

echo Обновляю игру...
git pull --ff-only origin main > logs\update_log.txt 2>&1
rem --- ВАЖНО: всё, что выше этой строки, менять нельзя (файл обновляет сам себя на ходу) ---
if errorlevel 1 call tools\win\force_update.bat
call tools\win\run.bat %*
goto :eof

:nosetup
echo Сначала запусти setup.bat
pause
