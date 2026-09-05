@echo off
setlocal
title Roblox VPN Sync
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0vpn_sync.ps1" -RobloxOnly %*
set "SYNC_EXIT=%ERRORLEVEL%"
if not "%SYNC_EXIT%"=="0" (
    echo [HATA] Roblox VPN yolu guncellenemedi.
    pause
)
exit /b %SYNC_EXIT%
