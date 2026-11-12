@echo off
chcp 65001 >nul
setlocal
rem Установка Battlefield в папку, где лежит этот файл.
rem Нужно один раз. Потом игра запускается и обновляется через play.bat.
rem Файл копирует себя во временную папку и работает оттуда — так git может спокойно
rem перезаписать setup.bat в папке игры.
if /i "%~1"=="--from-temp" goto main
copy /y "%~f0" "%TEMP%\battlefield_setup.bat" >nul
call "%TEMP%\battlefield_setup.bat" --from-temp "%~dp0"
exit /b

:main
cd /d "%~2"
title Установка Battlefield
echo === Установка Battlefield в %CD% ===
echo.
if not exist logs mkdir logs

rem --- 1. Git ---
where git >nul 2>&1
if not errorlevel 1 goto have_git
if not exist "%ProgramFiles%\Git\cmd\git.exe" goto install_git
set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
goto have_git

:install_git
echo Git не найден — ставлю его через winget (разреши установку, если Windows спросит)...
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
where git >nul 2>&1
if errorlevel 1 goto nogit

:have_git
echo [1/4] Git есть.

rem --- 2. Файлы игры с GitHub ---
if exist ".git" goto update_repo
echo [2/4] Скачиваю игру с GitHub...
git init -q -b main
git remote add origin https://github.com/Yotonick/battlefield.git
git fetch origin main
if errorlevel 1 goto nofetch
git checkout -q -f -B main origin/main
if errorlevel 1 goto nofetch
goto have_repo

:update_repo
echo [2/4] Игра уже скачана — обновляю...
git pull --ff-only origin main > logs\update_log.txt 2>&1
if errorlevel 1 call tools\win\force_update.bat

:have_repo
call tools\win\config.bat
if exist models if not exist models\.gdignore type nul > models\.gdignore
if not exist logs\.gdignore type nul > logs\.gdignore

rem --- 3. Godot ---
echo [3/4] Godot %GODOT_VER%...
call tools\win\install_godot.bat
if errorlevel 1 goto fail

rem --- 4. Импорт ресурсов + ярлык ---
echo [4/4] Готовлю ресурсы...
call tools\win\import.bat
if errorlevel 1 goto fail
set "BF_DIR=%CD%\"
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\Battlefield.lnk'); $s.TargetPath=$env:BF_DIR+'play.bat'; $s.WorkingDirectory=$env:BF_DIR; $s.IconLocation=$env:BF_DIR+$env:GODOT_EXE; $s.Save()" >nul 2>&1

echo.
echo Готово! Игра запускается через play.bat (или ярлык Battlefield на рабочем столе).
echo play.bat сам скачивает обновления при каждом запуске.
echo.
choice /c YN /m "Запустить игру сейчас"
if errorlevel 2 goto :eof
call play.bat
goto :eof

:nogit
echo ОШИБКА: не получилось поставить Git. Поставь вручную: https://git-scm.com/download/win
echo и запусти setup.bat ещё раз.
pause
goto :eof

:nofetch
echo ОШИБКА: не удалось скачать игру с GitHub. Проверь интернет и запусти setup.bat ещё раз.
pause
goto :eof

:fail
pause
