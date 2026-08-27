[CmdletBinding()]
param(
    [switch]$CheckOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$vpnScriptPath = Join-Path $scriptRoot 'vpn_sync.ps1'
$logDirectory = Join-Path $scriptRoot 'logs'
$mutex = $null
$mutexAcquired = $false
$transcriptStarted = $false
$discordManaged = $false
$exitCode = 0

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Limit-LauncherLogs {
    param(
        [int]$Maximum = 5,
        [int]$ReservedSlots = 0
    )

    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        return
    }

    $keepExisting = [Math]::Max(0, $Maximum - $ReservedSlots)
    $oldLogs = @(Get-ChildItem -LiteralPath $logDirectory -File -Filter 'launcher-*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -Skip $keepExisting)

    foreach ($oldLog in $oldLogs) {
        try {
            Remove-Item -LiteralPath $oldLog.FullName -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Eski log silinemedi: $($oldLog.FullName)"
        }
    }
}

function Stop-Discord {
    $processes = @(Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host 'Discord kapatiliyor...'
    foreach ($process in $processes) {
        try { $null = $process.CloseMainWindow() } catch { }
    }

    try { $processes | Wait-Process -Timeout 5 -ErrorAction Stop } catch { }

    $remaining = @(Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}

function Get-LatestDiscordApp {
    $discordDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Discord'
    if (-not (Test-Path -LiteralPath $discordDirectory -PathType Container)) {
        throw "Discord klasoru bulunamadi: $discordDirectory"
    }

    $candidates = foreach ($directory in Get-ChildItem -LiteralPath $discordDirectory -Directory -Filter 'app-*' -ErrorAction SilentlyContinue) {
        $discordExe = Join-Path $directory.FullName 'Discord.exe'
        if (-not (Test-Path -LiteralPath $discordExe -PathType Leaf)) {
            continue
        }

        $version = New-Object System.Version(0, 0)
        if (-not [System.Version]::TryParse($directory.Name.Substring(4), [ref]$version)) {
            $version = New-Object System.Version(0, 0)
        }

        [pscustomobject]@{
            Directory = $directory.FullName
            DiscordExe = $discordExe
            Version = $version
            LastWriteTime = $directory.LastWriteTimeUtc
        }
    }

    $latest = $candidates | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true } | Select-Object -First 1
    if (-not $latest) {
        throw 'Calisabilir bir Discord app-* klasoru bulunamadi.'
    }
    return $latest
}

function Invoke-VpnSync {
    param(
        [Parameter(Mandatory = $true)][string]$DiscordExePath,
        [switch]$WhatIfMode
    )

    if (-not (Test-Path -LiteralPath $vpnScriptPath -PathType Leaf)) {
        throw "vpn_sync.ps1 bulunamadi: $vpnScriptPath"
    }

    if ($WhatIfMode) {
        & $vpnScriptPath -DiscordExePath $DiscordExePath -WhatIf
    }
    else {
        & $vpnScriptPath -DiscordExePath $DiscordExePath
    }
}

function Start-DiscordThroughUpdater {
    $updateExe = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Discord\Update.exe'
    if (-not (Test-Path -LiteralPath $updateExe -PathType Leaf)) {
        throw "Discord Update.exe bulunamadi: $updateExe"
    }
    Start-Process -FilePath $updateExe -ArgumentList @('--processStart', 'Discord.exe') -WindowStyle Hidden
}

function Wait-ForDiscordExecutable {
    param([int]$TimeoutSeconds = 60)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        foreach ($process in @(Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)) {
            try {
                if ($process.Path -and (Test-Path -LiteralPath $process.Path -PathType Leaf)) {
                    return $process.Path
                }
            }
            catch { }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Discord $TimeoutSeconds saniye icinde baslamadi."
}

try {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    Limit-LauncherLogs -Maximum 5 -ReservedSlots 1
    $logPath = Join-Path $logDirectory ("launcher-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
    try {
        Start-Transcript -Path $logPath | Out-Null
        $transcriptStarted = $true
    }
    catch {
        Write-Warning "Log baslatilamadi: $($_.Exception.Message)"
    }

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\DiscordVpnSyncLauncher', [ref]$createdNew)
    if (-not $createdNew) {
        try { $mutexAcquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mutexAcquired = $true }
        if (-not $mutexAcquired) {
            throw 'Discord VPN Launcher zaten calisiyor.'
        }
    }
    else {
        $mutexAcquired = $true
    }

    Write-Step 'Ortam kontrol ediliyor'
    $initialDiscord = Get-LatestDiscordApp
    Write-Host "Discord: $($initialDiscord.Version) - $($initialDiscord.DiscordExe)"

    if ($CheckOnly) {
        Invoke-VpnSync -DiscordExePath $initialDiscord.DiscordExe -WhatIfMode
        Write-Host 'Kontrol tamamlandi; Discord, Proton ve ayarlar degistirilmedi.' -ForegroundColor Green
        return
    }

    Write-Step 'Discord kapatiliyor'
    Stop-Discord
    $discordManaged = $true

    Write-Step 'Proton VPN split tunneling esleniyor'
    Invoke-VpnSync -DiscordExePath $initialDiscord.DiscordExe

    Write-Step 'Discord updater uzerinden baslatiliyor'
    Start-DiscordThroughUpdater
    $actualDiscordExe = Wait-ForDiscordExecutable

    if (-not [string]::Equals($actualDiscordExe, $initialDiscord.DiscordExe, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host 'Updater yeni bir Discord surumu baslatti; VPN rotasi yeni yola tasiniyor...' -ForegroundColor Yellow
        Stop-Discord
        Invoke-VpnSync -DiscordExePath $actualDiscordExe
        Start-Process -FilePath $actualDiscordExe -WorkingDirectory (Split-Path -Parent $actualDiscordExe)
        $verifiedExe = Wait-ForDiscordExecutable -TimeoutSeconds 30
        if (-not [string]::Equals($verifiedExe, $actualDiscordExe, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Discord beklenmeyen bir yoldan basladi: $verifiedExe"
        }
    }

    Write-Host "`n[TAMAM] Discord ve Proton VPN rotasi hazir." -ForegroundColor Green
}
catch {
    $exitCode = 1
    if ($discordManaged) {
        Stop-Discord
    }
    Write-Host "`n[KRITIK HATA] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Discord dogrulanmamis bir VPN rotasiyla acik birakilmadi.' -ForegroundColor Yellow
}
finally {
    if ($mutexAcquired -and $null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $mutex) {
        $mutex.Dispose()
    }
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
    Limit-LauncherLogs -Maximum 5
}

exit $exitCode
