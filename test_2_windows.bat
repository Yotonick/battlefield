@echo off
chcp 65001 >nul
setlocal
rem Проверка сети на одном ПК: два окна игры — хост (Синие) и гость (Красные).
rem Обновление не делает — сначала хотя бы раз запусти play.bat.
cd /d "%~dp0"
if not exist logs mkdir logs
call tools\win\run.bat --host --name=Host --team=1
timeout /t 3 /nobreak >nul
call tools\win\run.bat --join=127.0.0.1 --name=Guest --team=2
