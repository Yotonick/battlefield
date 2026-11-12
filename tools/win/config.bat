@echo off
rem Общие настройки для всех .bat. Меняется только здесь.
rem Версия Godot: при смене все установки сами скачают новую при следующем запуске play.bat.
set "GODOT_VER=4.7.1-stable"
set "GODOT_EXE=.engine\Godot_v%GODOT_VER%_win64.exe"
set "GODOT_CON=.engine\Godot_v%GODOT_VER%_win64_console.exe"
set "REPO_URL=https://github.com/Yotonick/battlefield.git"
