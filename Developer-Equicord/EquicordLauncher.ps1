[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ForceBuild,
    [string]$RepositoryPath,
    [string]$UpstreamRemote,
    [string]$UpstreamBranch
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoPath = $null
$upstreamRemoteName = $null
$upstreamBranchName = $null
$vpnScriptPath = Join-Path $scriptRoot 'vpn_sync.ps1'
$statePath = Join-Path $scriptRoot 'launcher-state.json'
$configPath = Join-Path $scriptRoot 'launcher-config.json'
$logDirectory = Join-Path $scriptRoot 'logs'
$transcriptStarted = $false
$mutex = $null
$mutexAcquired = $false
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

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $null
    )

    $display = @($Command) + $Arguments
    Write-Host ("> " + ($display -join ' ')) -ForegroundColor DarkGray

    if ($WorkingDirectory) {
        Push-Location -LiteralPath $WorkingDirectory
    }

    try {
        & $Command @Arguments
        $nativeExitCode = $LASTEXITCODE
        if ($nativeExitCode -ne 0) {
            throw "Komut basarisiz oldu (cikis kodu $nativeExitCode): $Command"
        }
    }
    finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Get-ExternalOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $null
    )

    if ($WorkingDirectory) {
        Push-Location -LiteralPath $WorkingDirectory
    }

    try {
        $output = & $Command @Arguments 2>&1
        $nativeExitCode = $LASTEXITCODE
        if ($nativeExitCode -ne 0) {
            throw "Komut basarisiz oldu (cikis kodu $nativeExitCode): $Command $($Arguments -join ' ')"
        }
        return (($output | Out-String).Trim())
    }
    finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Save-LauncherConfig {
    param([Parameter(Mandatory = $true)]$Config)

    $temporaryPath = "$configPath.tmp.$([guid]::NewGuid().ToString('N'))"
    $json = $Config | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8NoBom)
        $null = Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json
        Move-Item -LiteralPath $temporaryPath -Destination $configPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-LauncherConfig {
    if (-not [string]::IsNullOrWhiteSpace($RepositoryPath)) {
        return [pscustomobject]@{
            RepositoryPath = $RepositoryPath
            UpstreamRemote = $(if ([string]::IsNullOrWhiteSpace($UpstreamRemote)) { 'upstream' } else { $UpstreamRemote })
            UpstreamBranch = $(if ([string]::IsNullOrWhiteSpace($UpstreamBranch)) { 'main' } else { $UpstreamBranch })
        }
    }

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $savedPath = if ($saved.PSObject.Properties['RepositoryPath']) { [string]$saved.RepositoryPath } else { '' }
            $savedRemote = if ($saved.PSObject.Properties['UpstreamRemote']) { [string]$saved.UpstreamRemote } else { 'upstream' }
            $savedBranch = if ($saved.PSObject.Properties['UpstreamBranch']) { [string]$saved.UpstreamBranch } else { 'main' }
            if ([string]::IsNullOrWhiteSpace($savedPath)) {
                throw 'RepositoryPath bos.'
            }
            return [pscustomobject]@{
                RepositoryPath = $savedPath
                UpstreamRemote = $savedRemote
                UpstreamBranch = $savedBranch
            }
        }
        catch {
            throw "launcher-config.json okunamadi. Dosyayi silip tekrar deneyin: $($_.Exception.Message)"
        }
    }

    Write-Host ''
    Write-Host 'Ilk kurulum: Equicord kaynak kodu ayarlari' -ForegroundColor Yellow
    Write-Host 'Bu bilgiler launcher-config.json dosyasina kaydedilecek.'
    $enteredPath = (Read-Host 'Equicord Git deposunun tam yolu').Trim().Trim('"')
    $enteredRemote = (Read-Host 'Upstream remote adi [upstream]').Trim()
    $enteredBranch = (Read-Host 'Upstream branch adi [main]').Trim()
    if ([string]::IsNullOrWhiteSpace($enteredRemote)) { $enteredRemote = 'upstream' }
    if ([string]::IsNullOrWhiteSpace($enteredBranch)) { $enteredBranch = 'main' }
    if ([string]::IsNullOrWhiteSpace($enteredPath)) {
        throw 'Equicord repo yolu bos birakilamaz.'
    }
    $enteredPath = [System.IO.Path]::GetFullPath($enteredPath)
    if (-not (Test-Path -LiteralPath (Join-Path $enteredPath '.git') -PathType Container) -or
        -not (Test-Path -LiteralPath (Join-Path $enteredPath 'package.json') -PathType Leaf)) {
        throw "Gecerli bir Equicord Git deposu bulunamadi: $enteredPath"
    }

    $newConfig = [pscustomobject]@{
        RepositoryPath = $enteredPath
        UpstreamRemote = $enteredRemote
        UpstreamBranch = $enteredBranch
    }
    Save-LauncherConfig -Config $newConfig
    return $newConfig
}

function Get-LauncherState {
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [pscustomobject]@{
            Version = 1
            LastSuccessfulBuildHead = $null
            LastSuccessfulBuildUtc = $null
            LastDiscordExePath = $null
        }
    }

    try {
        return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
    }
    catch {
        Write-Warning "Durum dosyasi okunamadi; yeni durum olusturulacak: $($_.Exception.Message)"
        return [pscustomobject]@{
            Version = 1
            LastSuccessfulBuildHead = $null
            LastSuccessfulBuildUtc = $null
            LastDiscordExePath = $null
        }
    }
}

function Save-LauncherState {
    param([Parameter(Mandatory = $true)]$State)

    $temporaryPath = "$statePath.tmp.$([guid]::NewGuid().ToString('N'))"
    $json = $State | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8NoBom)
        $null = Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json
        Move-Item -LiteralPath $temporaryPath -Destination $statePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Stop-Discord {
    $processes = @(Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host "Discord kapatiliyor..."
    foreach ($process in $processes) {
        try { $null = $process.CloseMainWindow() } catch { }
    }

    try {
        $processes | Wait-Process -Timeout 5 -ErrorAction Stop
    }
    catch { }

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

        $versionText = $directory.Name.Substring(4)
        $parsedVersion = New-Object System.Version(0, 0)
        if (-not [System.Version]::TryParse($versionText, [ref]$parsedVersion)) {
            $parsedVersion = New-Object System.Version(0, 0)
        }

        [pscustomobject]@{
            Directory = $directory.FullName
            DiscordExe = $discordExe
            Version = $parsedVersion
            LastWriteTime = $directory.LastWriteTimeUtc
        }
    }

    $latest = $candidates | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true } | Select-Object -First 1
    if (-not $latest) {
        throw "Calisabilir bir Discord app-* klasoru bulunamadi."
    }

    return $latest
}

function Test-EquicordInjection {
    param([Parameter(Mandatory = $true)][string]$DiscordAppDirectory)

    $indexPath = Join-Path $DiscordAppDirectory 'resources\app.asar\index.js'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        return $false
    }

    $patcherPath = (Join-Path $repoPath 'dist\desktop\patcher.js').Replace('\', '\\')
    $content = Get-Content -LiteralPath $indexPath -Raw -ErrorAction SilentlyContinue
    return ($null -ne $content -and $content.IndexOf($patcherPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Repair-EquicordInjection {
    param([Parameter(Mandatory = $true)][string]$DiscordAppDirectory)

    if (Test-EquicordInjection -DiscordAppDirectory $DiscordAppDirectory) {
        Write-Host "Equicord enjeksiyonu guncel." -ForegroundColor Green
        return
    }

    Write-Host "Equicord enjeksiyonu eksik veya eski; onariliyor..." -ForegroundColor Yellow
    Invoke-External -Command 'pnpm.cmd' -Arguments @('inject') -WorkingDirectory $repoPath

    if (-not (Test-EquicordInjection -DiscordAppDirectory $DiscordAppDirectory)) {
        throw "Equicord enjeksiyonu dogrulanamadi: $DiscordAppDirectory"
    }
}

function Invoke-VpnSync {
    param([Parameter(Mandatory = $true)][string]$DiscordExePath)

    if (-not (Test-Path -LiteralPath $vpnScriptPath -PathType Leaf)) {
        throw "VPN betigi bulunamadi: $vpnScriptPath"
    }

    & $vpnScriptPath -DiscordExePath $DiscordExePath
}

function Wait-ForDiscordExecutable {
    param([int]$TimeoutSeconds = 60)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $processes = @(Get-Process -Name 'Discord' -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
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

function Start-DiscordThroughUpdater {
    $updateExe = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Discord\Update.exe'
    if (-not (Test-Path -LiteralPath $updateExe -PathType Leaf)) {
        throw "Discord Update.exe bulunamadi: $updateExe"
    }

    Start-Process -FilePath $updateExe -ArgumentList @('--processStart', 'Discord.exe') -WindowStyle Hidden
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
    $mutex = New-Object System.Threading.Mutex($true, 'Local\DiscordProtonLauncher-DeveloperEquicord', [ref]$createdNew)
    if (-not $createdNew) {
        try { $mutexAcquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mutexAcquired = $true }
        if (-not $mutexAcquired) {
            throw "Equicord Launcher zaten calisiyor."
        }
    }
    else {
        $mutexAcquired = $true
    }

    Write-Step "Ortam kontrol ediliyor"
    foreach ($commandName in @('git.exe', 'pnpm.cmd')) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            throw "Gerekli komut bulunamadi: $commandName"
        }
    }

    $launcherConfig = Get-LauncherConfig
    $repoPath = [System.IO.Path]::GetFullPath([string]$launcherConfig.RepositoryPath)
    $upstreamRemoteName = [string]$launcherConfig.UpstreamRemote
    $upstreamBranchName = [string]$launcherConfig.UpstreamBranch
    if (-not (Test-Path -LiteralPath (Join-Path $repoPath '.git') -PathType Container)) {
        throw "Equicord Git deposu bulunamadi: $repoPath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $repoPath 'package.json') -PathType Leaf)) {
        throw "Equicord package.json bulunamadi: $repoPath"
    }
    $upstreamUrl = Get-ExternalOutput -Command 'git.exe' -Arguments @('remote', 'get-url', $upstreamRemoteName) -WorkingDirectory $repoPath
    Write-Host "Equicord repo: $repoPath"
    Write-Host "Upstream: $upstreamRemoteName/$upstreamBranchName ($upstreamUrl)"

    $initialDiscord = Get-LatestDiscordApp
    Write-Host "Discord: $($initialDiscord.Version) - $($initialDiscord.DiscordExe)"

    if ($CheckOnly) {
        Write-Host "Git, pnpm, Discord ve betik yollari gecerli." -ForegroundColor Green
        Write-Host ("Equicord enjeksiyonu: " + $(if (Test-EquicordInjection $initialDiscord.Directory) { 'gecerli' } else { 'onarim gerekli' }))
        & $vpnScriptPath -DiscordExePath $initialDiscord.DiscordExe -WhatIf
        Write-Host "Kontrol tamamlandi; hicbir uygulama veya ayar degistirilmedi." -ForegroundColor Green
        return
    }

    Write-Step "Discord kapatiliyor"
    Stop-Discord
    $discordManaged = $true

    Write-Step "Equicord upstream ile esleniyor"
    Invoke-External -Command 'git.exe' -Arguments @('fetch', '--tags', '--prune', $upstreamRemoteName, $upstreamBranchName) -WorkingDirectory $repoPath
    $upstreamRef = "$upstreamRemoteName/$upstreamBranchName"
    Invoke-External -Command 'git.exe' -Arguments @('rebase', '--rebase-merges', '--autostash', $upstreamRef) -WorkingDirectory $repoPath

    $head = Get-ExternalOutput -Command 'git.exe' -Arguments @('rev-parse', 'HEAD') -WorkingDirectory $repoPath
    $workingTreeStatus = Get-ExternalOutput -Command 'git.exe' -Arguments @('status', '--porcelain=v1', '--untracked-files=all') -WorkingDirectory $repoPath
    $state = Get-LauncherState
    $patcherArtifact = Join-Path $repoPath 'dist\desktop\patcher.js'
    $needsBuild = $ForceBuild -or
        ($state.LastSuccessfulBuildHead -ne $head) -or
        (-not [string]::IsNullOrWhiteSpace($workingTreeStatus)) -or
        (-not (Test-Path -LiteralPath $patcherArtifact -PathType Leaf))

    Write-Step "Derleme kontrol ediliyor"
    if ($needsBuild) {
        if (-not [string]::IsNullOrWhiteSpace($workingTreeStatus)) {
            Write-Warning "Calisma agaci temiz degil; yerel degisikliklerin derlemeye alinacak."
        }
        Invoke-External -Command 'pnpm.cmd' -Arguments @('install', '--frozen-lockfile') -WorkingDirectory $repoPath
        Invoke-External -Command 'pnpm.cmd' -Arguments @('build') -WorkingDirectory $repoPath
        if (-not (Test-Path -LiteralPath $patcherArtifact -PathType Leaf)) {
            throw "Build tamamlandi ancak patcher.js bulunamadi."
        }
        $state.LastSuccessfulBuildHead = $head
        $state.LastSuccessfulBuildUtc = [DateTime]::UtcNow.ToString('o')
        Save-LauncherState -State $state
        Write-Host "Build basarili." -ForegroundColor Green
    }
    else {
        Write-Host "Kaynak kod degismedi; onceki basarili build kullaniliyor." -ForegroundColor Green
    }

    $initialDiscord = Get-LatestDiscordApp
    Write-Step "Equicord enjeksiyonu kontrol ediliyor"
    Repair-EquicordInjection -DiscordAppDirectory $initialDiscord.Directory

    Write-Step "Proton VPN split tunneling esleniyor"
    Invoke-VpnSync -DiscordExePath $initialDiscord.DiscordExe

    Write-Step "Discord updater uzerinden baslatiliyor"
    Start-DiscordThroughUpdater
    $actualDiscordExe = Wait-ForDiscordExecutable
    $actualDiscordDirectory = Split-Path -Parent $actualDiscordExe
    $pathChanged = -not [string]::Equals($actualDiscordExe, $initialDiscord.DiscordExe, [System.StringComparison]::OrdinalIgnoreCase)
    $injectionChanged = -not (Test-EquicordInjection -DiscordAppDirectory $actualDiscordDirectory)

    if ($pathChanged -or $injectionChanged) {
        Write-Host "Updater yeni veya enjeksiyonsuz bir Discord surumu baslatti; onarim yapiliyor..." -ForegroundColor Yellow
        Stop-Discord
        Repair-EquicordInjection -DiscordAppDirectory $actualDiscordDirectory
        Invoke-VpnSync -DiscordExePath $actualDiscordExe
        Start-Process -FilePath $actualDiscordExe -WorkingDirectory $actualDiscordDirectory
        $null = Wait-ForDiscordExecutable -TimeoutSeconds 30
    }

    $state = Get-LauncherState
    $state.LastDiscordExePath = $actualDiscordExe
    Save-LauncherState -State $state

    Write-Host "`n[TAMAM] Equicord ve VPN rotasi hazir." -ForegroundColor Green
}
catch {
    $exitCode = 1
    if ($discordManaged) {
        Stop-Discord
    }
    Write-Host "`n[KRITIK HATA] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Discord guvenli olmayan veya eksik bir durumla otomatik baslatilmadi." -ForegroundColor Yellow
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
