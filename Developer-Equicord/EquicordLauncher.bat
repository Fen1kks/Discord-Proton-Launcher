@echo off
setlocal
title Equicord Launcher ^& VPN Sync
color 0B

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0EquicordLauncher.ps1" %*
set "LAUNCHER_EXIT=%ERRORLEVEL%"

if not "%LAUNCHER_EXIT%"=="0" (
    echo.
    echo [HATA] Launcher tamamlanamadi. Ayrintilar yukarida ve logs klasorunde.
    pause
)

exit /b %LAUNCHER_EXIT%
