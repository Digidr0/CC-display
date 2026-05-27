@echo off
chcp 65001 >nul
title CC:Tweaked Dev Server — base-gui

echo ========================================
echo  CC:Tweaked Dev Server — base-gui
echo ========================================
echo.
echo  Запуск HTTP-сервера на порту 8000...
echo  В игре используй: wget http://localhost:8000/startup.lua startup.lua
echo.
echo  Нажми Ctrl+C для остановки.
echo ========================================
echo.

node "%~dp0dev-server.js"
pause
