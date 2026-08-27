@echo off
setlocal
title Discord VPN Sync
color 0B

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0DiscordLauncher.ps1" %*
set "LAUNCHER_EXIT=%ERRORLEVEL%"

if not "%LAUNCHER_EXIT%"=="0" (
    echo.
    echo [HATA] Discord baslatilamadi. Ayrintilar yukarida ve logs klasorunde.
    pause
)

exit /b %LAUNCHER_EXIT%
