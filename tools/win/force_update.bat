@echo off
rem Вызывается, если обычное обновление (git pull) не прошло: нет сети или файлы игры правились руками.
rem Ручные правки не теряются — сохраняются в git stash (вернуть: git stash pop).
echo Обычное обновление не прошло, пробую ещё раз начисто (лог: logs\update_log.txt)...
git fetch origin main >> logs\update_log.txt 2>&1
if errorlevel 1 goto offline
git -c user.name=battlefield -c user.email=battlefield@local stash push -m "auto-backup before force update" >> logs\update_log.txt 2>&1
git reset --hard origin/main >> logs\update_log.txt 2>&1
if errorlevel 1 goto offline
echo Игра обновлена. Если ты что-то менял в файлах игры — копия лежит в git stash.
exit /b 0

:offline
echo Нет связи с GitHub — запускаю ту версию, что уже скачана.
echo Если друзья на новой версии, хост тебя не пустит: обнови, когда появится интернет.
exit /b 0
