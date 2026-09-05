[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$DiscordExePath,
    [switch]$RobloxOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-LatestDiscordExecutable {
    $discordDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Discord'
    $candidates = foreach ($directory in Get-ChildItem -LiteralPath $discordDirectory -Directory -Filter 'app-*' -ErrorAction SilentlyContinue) {
        $exePath = Join-Path $directory.FullName 'Discord.exe'
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
            continue
        }

        $parsedVersion = New-Object System.Version(0, 0)
        $null = [System.Version]::TryParse($directory.Name.Substring(4), [ref]$parsedVersion)
        [pscustomobject]@{ Path = $exePath; Version = $parsedVersion; LastWriteTime = $directory.LastWriteTimeUtc }
    }

    $latest = $candidates | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true } | Select-Object -First 1
    if (-not $latest) {
        throw 'Guncel Discord.exe bulunamadi.'
    }
    return $latest.Path
}

function Get-LatestRobloxExecutable {
    param([string]$VersionsDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Roblox\Versions'))

    if (-not (Test-Path -LiteralPath $VersionsDirectory -PathType Container)) { return $null }
    $candidates = foreach ($directory in Get-ChildItem -LiteralPath $VersionsDirectory -Directory -Filter 'version-*') {
        $exePath = Join-Path $directory.FullName 'RobloxPlayerBeta.exe'
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $exePath
        $info = $file.VersionInfo
        # Folder names are hashes, not sortable versions. Use the executable's numeric version.
        $version = New-Object System.Version($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart, $info.FilePrivatePart)
        [pscustomobject]@{ Path = $exePath; Version = $version; LastWriteTime = $directory.LastWriteTimeUtc }
    }
    $latest = $candidates | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true } | Select-Object -First 1
    if ($latest) { return $latest.Path }
    return $null
}

function Get-ProtonSettingsFile {
    $storageDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Proton\Proton VPN\Storage'
    if (-not (Test-Path -LiteralPath $storageDirectory -PathType Container)) {
        throw "Proton VPN ayar klasoru bulunamadi: $storageDirectory"
    }

    $settingsFile = Get-ChildItem -LiteralPath $storageDirectory -File -Filter 'UserSettings*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $settingsFile) {
        throw "Proton VPN UserSettings JSON dosyasi bulunamadi: $storageDirectory"
    }
    return $settingsFile
}

function Read-ProtonSettings {
    param([Parameter(Mandatory = $true)]$SettingsFile)

    $root = Get-Content -LiteralPath $SettingsFile.FullName -Raw | ConvertFrom-Json
    $property = $root.PSObject.Properties['SplitTunnelingInverseAppsList']
    if ($null -eq $property) {
        throw 'SplitTunnelingInverseAppsList alani Proton ayarlarinda bulunamadi.'
    }

    if ($null -eq $property.Value -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        $apps = @()
    }
    elseif ($property.Value -is [string]) {
        $parsedApps = $property.Value | ConvertFrom-Json
        $apps = @($parsedApps | ForEach-Object { $_ })
    }
    else {
        $apps = @($property.Value | ForEach-Object { $_ })
    }

    return [pscustomobject]@{ Root = $root; Apps = $apps }
}

function Assert-InverseSplitTunnelingMode {
    param([Parameter(Mandatory = $true)]$RootObject)

    $enabledProperty = $RootObject.PSObject.Properties['IsSplitTunnelingEnabled']
    if ($null -ne $enabledProperty -and [string]$enabledProperty.Value -ine 'true') {
        throw 'Proton VPN Split Tunneling etkin degil. Proton ayarlarindan etkinlestirin.'
    }

    $modeProperty = $RootObject.PSObject.Properties['SplitTunnelingMode']
    if ($null -ne $modeProperty -and [string]$modeProperty.Value -ine 'Inverse') {
        throw 'Proton VPN Split Tunneling modu "Yalnizca eklenen uygulamalar VPN uzerinden" olmali.'
    }
}

function Set-AppEntry {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Apps,
        [Parameter(Mandatory = $true)][string]$ExePath
    )

    $matches = @($Apps | Where-Object {
        $_.PSObject.Properties['AppFilePath'] -and
        [System.IO.Path]::GetFileName([string]$_.AppFilePath) -ieq [System.IO.Path]::GetFileName($ExePath)
    })

    $changed = $false
    Write-Verbose ("Eslesen uygulama kaydi sayisi: {0}" -f $matches.Count)
    if ($matches.Count -eq 0) {
        $Apps += [pscustomobject]@{
            AppFilePath = $ExePath
            AlternateAppFilePaths = @()
            IsActive = $true
        }
        $changed = $true
    }
    else {
        foreach ($entry in $matches) {
            Write-Verbose ("Kayit karsilastirmasi: '{0}' -> '{1}', IsActive={2}" -f $entry.AppFilePath, $ExePath, $entry.IsActive)
            if (-not [string]::Equals([string]$entry.AppFilePath, $ExePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $entry.AppFilePath = $ExePath
                $changed = $true
            }
            if ($entry.PSObject.Properties['IsActive'] -and -not [bool]$entry.IsActive) {
                $entry.IsActive = $true
                $changed = $true
            }
        }
    }

    return [pscustomobject]@{ Apps = @($Apps); Changed = $changed }
}

function Set-TargetEntries {
    param([AllowEmptyCollection()][object[]]$Apps, [string[]]$Paths)
    $changed = $false
    foreach ($path in $Paths) {
        $result = Set-AppEntry -Apps $Apps -ExePath $path
        $Apps = $result.Apps
        $changed = $changed -or $result.Changed
    }
    return [pscustomobject]@{ Apps = @($Apps); Changed = $changed }
}

function Stop-ProtonClient {
    $processes = @(Get-Process -Name @('ProtonVPN.Client', 'ProtonVPN') -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return $false
    }

    foreach ($process in $processes) {
        try { $null = $process.CloseMainWindow() } catch { }
    }
    try { $processes | Wait-Process -Timeout 8 -ErrorAction Stop } catch { }

    $remaining = @(Get-Process -Name @('ProtonVPN.Client', 'ProtonVPN') -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 750
    }
    return $true
}

function Start-ProtonClient {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Proton\VPN\ProtonVPN.Launcher.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Proton\VPN\ProtonVPN.Launcher.exe'),
        (Join-Path $env:ProgramFiles 'Proton\Proton VPN\ProtonVPN.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Proton\Proton VPN\ProtonVPN.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

    $launcher = $candidates | Select-Object -First 1
    if (-not $launcher) {
        throw 'Proton VPN yeniden baslaticisi bulunamadi.'
    }
    Start-Process -FilePath $launcher -WindowStyle Hidden

    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Get-Process -Name 'ProtonVPN.Client' -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 1
            return
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'Proton VPN istemcisi yeniden baslatilamadi.'
}

function Write-SettingsAtomically {
    param(
        [Parameter(Mandatory = $true)]$SettingsFile,
        [Parameter(Mandatory = $true)]$RootObject,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Apps
    )

    $backupDirectory = Join-Path $SettingsFile.DirectoryName 'DiscordVpnSyncBackups'
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $backupPath = Join-Path $backupDirectory ("{0}.{1}.bak" -f $SettingsFile.Name, $timestamp)

    $RootObject.SplitTunnelingInverseAppsList = ConvertTo-Json -InputObject ([object[]]$Apps) -Compress -Depth 20
    $finalJson = $RootObject | ConvertTo-Json -Depth 50
    $temporaryPath = "$($SettingsFile.FullName).equicord.$([guid]::NewGuid().ToString('N')).tmp"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        [System.IO.File]::WriteAllText($temporaryPath, $finalJson, $utf8NoBom)
        $validationRoot = Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json
        $null = $validationRoot.SplitTunnelingInverseAppsList | ConvertFrom-Json
        # Windows PowerShell 5.1/.NET Framework rejects a null backup path here.
        # Let File.Replace create the timestamped backup as part of the same
        # atomic operation so the original remains intact if replacement fails.
        [System.IO.File]::Replace($temporaryPath, $SettingsFile.FullName, $backupPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $backupPath
}

$targetPaths = @()
if (-not $RobloxOnly) {
    if ([string]::IsNullOrWhiteSpace($DiscordExePath)) {
        $DiscordExePath = Get-LatestDiscordExecutable
    }
    $DiscordExePath = [System.IO.Path]::GetFullPath($DiscordExePath)
    if (-not (Test-Path -LiteralPath $DiscordExePath -PathType Leaf) -or [System.IO.Path]::GetFileName($DiscordExePath) -ine 'Discord.exe') {
        throw "Gecersiz Discord.exe yolu: $DiscordExePath"
    }
    $targetPaths += $DiscordExePath
}
$robloxExePath = Get-LatestRobloxExecutable
if ($RobloxOnly -and -not $robloxExePath) {
    throw 'Roblox Versions klasorunde RobloxPlayerBeta.exe bulunamadi.'
}

$settingsFile = Get-ProtonSettingsFile
$settings = Read-ProtonSettings -SettingsFile $settingsFile
Assert-InverseSplitTunnelingMode -RootObject $settings.Root
# Normal Discord launches maintain Roblox only when the user already added it to Proton.
$hasRobloxEntry = @($settings.Apps | Where-Object {
    $_.PSObject.Properties['AppFilePath'] -and
    [System.IO.Path]::GetFileName([string]$_.AppFilePath) -ieq 'RobloxPlayerBeta.exe'
}).Count -gt 0
if ($robloxExePath -and ($RobloxOnly -or $hasRobloxEntry)) {
    $targetPaths += $robloxExePath
    Write-Host "Roblox: $robloxExePath"
}
$update = Set-TargetEntries -Apps $settings.Apps -Paths $targetPaths

if (-not $update.Changed) {
    Write-Host "[STABIL] Proton VPN uygulama rotalari zaten guncel." -ForegroundColor Green
    return
}

if (-not $PSCmdlet.ShouldProcess($settingsFile.FullName, "Split tunneling yollarini guncelle: $($targetPaths -join '; ')")) {
    return
}

Write-Host '[VPN] Uygulama yolu degisti; Proton ayari guvenli bicimde guncelleniyor...' -ForegroundColor Yellow
$protonWasRunning = $false
try {
    $protonWasRunning = Stop-ProtonClient

    # Proton kapanirken son ayarlarini yazmis olabilir; dosyayi yeniden okuyup degisikligi tekrar uygula.
    $settingsFile = Get-ProtonSettingsFile
    $settings = Read-ProtonSettings -SettingsFile $settingsFile
    Assert-InverseSplitTunnelingMode -RootObject $settings.Root
    $update = Set-TargetEntries -Apps $settings.Apps -Paths $targetPaths
    if ($update.Changed) {
        $backupPath = Write-SettingsAtomically -SettingsFile $settingsFile -RootObject $settings.Root -Apps $update.Apps
        Write-Host "[VPN] Ayar guncellendi. Yedek: $backupPath" -ForegroundColor Green
    }
    else {
        Write-Host '[STABIL] Proton kapanirken ayari zaten guncellemis.' -ForegroundColor Green
    }
}
finally {
    if ($protonWasRunning) {
        Start-ProtonClient
    }
}
