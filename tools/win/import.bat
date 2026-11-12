@echo off
rem Импорт ресурсов (модели, текстуры, звуки) — нужен Godot перед запуском игры из исходников.
rem Делается только если версия игры сменилась после прошлого импорта.
call tools\win\config.bat
set "HEAD="
for /f %%h in ('git rev-parse HEAD 2^>nul') do set "HEAD=%%h"
set "LAST="
if exist ".godot\last_import.txt" set /p LAST=<".godot\last_import.txt"
if not exist ".godot\imported" goto do_import
if "%LAST%"=="%HEAD%" exit /b 0

:do_import
echo Готовлю ресурсы игры (первый раз — до пары минут)...
"%GODOT_CON%" --headless --import --path . > logs\import_log.txt 2>&1
if not exist ".godot\imported" goto fail
>".godot\last_import.txt" echo %HEAD%
exit /b 0

:fail
echo ОШИБКА импорта ресурсов. Подробности: logs\import_log.txt
exit /b 1
