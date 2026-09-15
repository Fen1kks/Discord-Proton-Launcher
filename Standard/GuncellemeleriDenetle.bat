@echo off
setlocal
chcp 65001 >nul
title Güncellemeleri Denetle
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LauncherBootstrap.ps1" -UpdateOnly
set "UPDATE_EXIT=%ERRORLEVEL%"
if not "%UPDATE_EXIT%"=="0" echo [HATA] Güncelleme tamamlanamadı. Mevcut sürüm korunuyor.
echo.
pause
exit /b %UPDATE_EXIT%
