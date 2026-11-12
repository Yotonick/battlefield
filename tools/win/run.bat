@echo off
rem Запуск игры. Вызывается из play.bat после обновления; этот файл можно менять как угодно.
rem Аргументы play.bat передаются в игру: play.bat --host --name=Хост --team=1
call tools\win\config.bat
if not exist logs\.gdignore type nul > logs\.gdignore
rem Сырые ассеты в models\ Godot не трогает (там архивы, разбираем их по одному в assets\)
if exist models if not exist models\.gdignore type nul > models\.gdignore

call tools\win\install_godot.bat
if errorlevel 1 goto fail
call tools\win\import.bat
if errorlevel 1 goto fail

for /f "tokens=2 delims==" %%v in ('findstr /b "config/version=" project.godot') do set "GAME_VER=%%~v"
echo Запускаю Battlefield %GAME_VER%...
start "" "%GODOT_EXE%" --path . %*
exit /b 0

:fail
pause
exit /b 1
