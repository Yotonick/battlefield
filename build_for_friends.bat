@echo off
chcp 65001 >nul
setlocal
rem Собирает игру в один Battlefield.exe и пакует в build\Battlefield-Windows.zip — этот zip можно кидать друзьям.
rem Обычно это не нужно: GitHub собирает такой же zip сам после каждого обновления
rem (страница Releases репозитория). Этот файл — запасной вариант, если нужна сборка прямо сейчас.
rem Первый раз скачивает шаблоны экспорта Godot (~1.3 ГБ, оставляет из них ~110 МБ).
cd /d "%~dp0"
if not exist logs mkdir logs
call tools\win\config.bat
call tools\win\install_godot.bat
if errorlevel 1 goto fail

set "TPL_VER=%GODOT_VER:-=.%"
set "TPL_DIR=%APPDATA%\Godot\export_templates\%TPL_VER%"
if exist "%TPL_DIR%\windows_release_x86_64.exe" goto have_tpl
echo Скачиваю шаблоны экспорта Godot %GODOT_VER% (~1.3 ГБ, один раз)...
if not exist "%TPL_DIR%" mkdir "%TPL_DIR%"
curl.exe -L --fail --progress-bar -o "%TEMP%\godot_templates.tpz" "https://github.com/godotengine/godot/releases/download/%GODOT_VER%/Godot_v%GODOT_VER%_export_templates.tpz"
if errorlevel 1 goto fail
tar -xf "%TEMP%\godot_templates.tpz" -C "%TEMP%" templates/windows_release_x86_64.exe templates/version.txt
if errorlevel 1 goto fail
move /y "%TEMP%\templates\windows_release_x86_64.exe" "%TPL_DIR%\" >nul
move /y "%TEMP%\templates\version.txt" "%TPL_DIR%\" >nul
del /q "%TEMP%\godot_templates.tpz"
rd /s /q "%TEMP%\templates" 2>nul

:have_tpl
call tools\win\import.bat
if errorlevel 1 goto fail
echo Собираю Battlefield.exe...
if exist build\Battlefield rd /s /q build\Battlefield
mkdir build\Battlefield
"%GODOT_CON%" --headless --export-release "Windows" build\Battlefield\Battlefield.exe > logs\build_log.txt 2>&1
if not exist build\Battlefield\Battlefield.exe goto buildfail
copy /y tools\win\friends_readme.txt build\Battlefield\README.txt >nul
del /q build\Battlefield-Windows.zip 2>nul
tar -a -c -f build\Battlefield-Windows.zip -C build Battlefield
echo.
echo Готово: build\Battlefield-Windows.zip — кидай друзьям.
explorer build
pause
goto :eof

:buildfail
echo ОШИБКА сборки. Подробности: logs\build_log.txt
:fail
pause
