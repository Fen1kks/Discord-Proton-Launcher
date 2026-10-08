@echo off
setlocal
title Discord VPN Sync
color 0B

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0LauncherBootstrap.ps1" -Target DiscordLauncher.ps1 %*
set "LAUNCHER_EXIT=%ERRORLEVEL%"

if not "%LAUNCHER_EXIT%"=="0" (
    echo.
    echo [HATA] Discord baslatilamadi. Ayrintilar yukarida ve logs klasorunde.
    if not "%DISCORD_LAUNCHER_SILENT%"=="1" pause
)

exit /b %LAUNCHER_EXIT%
