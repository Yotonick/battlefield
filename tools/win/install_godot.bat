@echo off
rem Ставит или обновляет Godot в папку .engine (версия — в config.bat).
rem Если нужная версия уже стоит — ничего не делает.
call tools\win\config.bat
if exist "%GODOT_EXE%" if exist "%GODOT_CON%" exit /b 0

echo Скачиваю Godot %GODOT_VER% (около 85 МБ, один раз)...
if not exist .engine mkdir .engine
if not exist ".engine\.gdignore" type nul > ".engine\.gdignore"
curl.exe -L --fail --progress-bar -o ".engine\godot.zip" "https://github.com/godotengine/godot/releases/download/%GODOT_VER%/Godot_v%GODOT_VER%_win64.exe.zip"
if errorlevel 1 goto fail
tar -xf ".engine\godot.zip" -C ".engine"
if errorlevel 1 goto fail
del /q ".engine\godot.zip"
if not exist "%GODOT_EXE%" goto fail
echo Godot %GODOT_VER% установлен.
exit /b 0

:fail
echo ОШИБКА: не удалось скачать или распаковать Godot. Проверь интернет и запусти ещё раз.
del /q ".engine\godot.zip" 2>nul
exit /b 1
