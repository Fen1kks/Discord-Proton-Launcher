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

        $hasAsar = (Test-Path -LiteralPath (Join-Path $directory.FullName 'resources\app.asar')) -or
            (Test-Path -LiteralPath (Join-Path $directory.FullName 'resources\_app.asar'))
        if (-not $hasAsar) {
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

function Get-ProtonClientLogFiles {
    $logDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Proton\Proton VPN\Logs'
    return @(Get-ChildItem -LiteralPath $logDirectory -File -Filter 'client-logs*.txt' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}

function Read-SharedTextFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Proton keeps its log open for writing; a plain read would be refused.
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    $reader = New-Object System.IO.StreamReader($stream)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
}

function Get-ProtonConnectionEvents {
    param([AllowEmptyCollection()][string[]]$LogPaths)

    $pattern = '(?m)^(?<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z) \|.*\[CONNECTION_PROCESS\] Status updated to (?<status>[A-Za-z]+)'
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    $events = foreach ($path in @($LogPaths)) {
        try { $text = Read-SharedTextFile -Path $path }
        catch {
            Write-Verbose "Proton logu okunamadi: $path"
            continue
        }
        foreach ($match in [regex]::Matches($text, $pattern)) {
            [pscustomobject]@{
                TimeUtc = [DateTime]::Parse($match.Groups['time'].Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles)
                Status = $match.Groups['status'].Value
            }
        }
    }
    return @($events | Sort-Object -Property TimeUtc)
}

function Get-ProtonReconnectState {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Events,
        [Parameter(Mandatory = $true)][DateTime]$SinceUtc
    )

    # The service receives the split tunneling list only while connecting, so a
    # client restart that re-attaches to the running tunnel keeps the old list.
    if ($Events.Count -eq 0) { return 'Unknown' }
    if (@($Events | Where-Object { $_.Status -eq 'Connecting' -and $_.TimeUtc -gt $SinceUtc }).Count -gt 0) { return 'Applied' }
    if ($Events[-1].Status -ne 'Connected') { return 'Disconnected' }
    return 'Pending'
}

function Get-ReconnectMarkerPath {
    param([Parameter(Mandatory = $true)]$SettingsFile)
    return Join-Path $SettingsFile.DirectoryName 'DiscordVpnSyncBackups\reconnect-pending.txt'
}

function Set-ProtonReconnectPending {
    param(
        [Parameter(Mandatory = $true)][string]$MarkerPath,
        [Parameter(Mandatory = $true)][DateTime]$SettingsChangedUtc
    )

    # The marker's write time records when the settings changed.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($MarkerPath, "Proton VPN yeniden baglanana kadar yeni split tunneling listesi uygulanmaz.`r`n", $utf8NoBom)
    [System.IO.File]::SetLastWriteTimeUtc($MarkerPath, $SettingsChangedUtc)
}

function Confirm-ProtonReconnectDialog {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($env:DISCORD_LAUNCHER_NO_DIALOG -or $env:CI) { return $null }

    $title = 'Proton VPN - Yeniden baglanin'
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $result = [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $title,
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return ($result -eq [System.Windows.Forms.DialogResult]::OK)
    }
    catch {
        try {
            $wshell = New-Object -ComObject WScript.Shell
            return ($wshell.Popup($Message, 0, $title, 1 + 48) -eq 1)
        }
        catch { return $null }
    }
}

function Wait-ProtonReconnect {
    param(
        [Parameter(Mandatory = $true)][string]$MarkerPath,
        [int]$TimeoutSeconds = 180
    )

    if (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        return
    }

    $sinceUtc = (Get-Item -LiteralPath $MarkerPath).LastWriteTimeUtc
    $state = Get-ProtonReconnectState -Events @(Get-ProtonConnectionEvents -LogPaths (Get-ProtonClientLogFiles)) -SinceUtc $sinceUtc
    if ($state -eq 'Applied') {
        Remove-Item -LiteralPath $MarkerPath -Force
        Write-Host '[VPN] Proton VPN yeni uygulama listesiyle baglandi.' -ForegroundColor Green
        return
    }
    if ($state -eq 'Disconnected') {
        Write-Warning 'Proton VPN bagli degil; yeni uygulama listesi bir sonraki baglantida uygulanacak.'
        return
    }
    if ($WhatIfPreference) {
        Write-Warning 'Proton VPN ayari degisti ancak baglanti henuz yeniden kurulmadi.'
        return
    }

    Write-Host '[VPN] Mevcut Proton VPN baglantisi eski uygulama listesini kullaniyor.' -ForegroundColor Yellow
    Write-Host '      Proton VPN uygulamasinda baglantiyi kesip yeniden baglanin.' -ForegroundColor Yellow
    $instructions = "Proton VPN split tunneling listesi guncellendi, ancak acik VPN baglantisi eski listeyi kullanmaya devam ediyor.`n`nProton VPN uygulamasinda baglantiyi kesip yeniden baglanin, ardindan Tamam'a basin."
    $message = $instructions
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($true) {
        $confirmed = Confirm-ProtonReconnectDialog -Message $message
        if ($confirmed -eq $false) {
            throw 'Proton VPN yeniden baglantisi iptal edildi; Discord eski VPN rotasiyla baslatilmadi.'
        }

        # Without a dialog, poll until the deadline; after a confirmation, give the reconnect a moment to reach the log.
        $pollUntil = if ($null -eq $confirmed) { $deadline } else { [DateTime]::UtcNow.AddSeconds(15) }
        do {
            $state = Get-ProtonReconnectState -Events @(Get-ProtonConnectionEvents -LogPaths (Get-ProtonClientLogFiles)) -SinceUtc $sinceUtc
            if ($state -eq 'Applied' -or $state -eq 'Unknown') { break }
            Start-Sleep -Seconds 1
        } while ([DateTime]::UtcNow -lt $pollUntil)

        if ($state -eq 'Applied') {
            Remove-Item -LiteralPath $MarkerPath -Force
            Write-Host '[VPN] Proton VPN yeni uygulama listesiyle yeniden baglandi.' -ForegroundColor Green
            return
        }
        if ($state -eq 'Unknown') {
            if ($confirmed) {
                Remove-Item -LiteralPath $MarkerPath -Force
                Write-Warning 'Proton logu okunamadi; yeniden baglanti kullanici onayiyla kabul edildi.'
            }
            else {
                Write-Warning 'Proton logu okunamadi; yeniden baglanti dogrulanamadi.'
            }
            return
        }
        if ($null -eq $confirmed) {
            throw "Proton VPN $TimeoutSeconds saniye icinde yeniden baglanmadi; Discord eski VPN rotasiyla baslatilmadi."
        }
        $message = "Yeniden baglanti henuz algilanamadi.`n`n$instructions"
    }
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
$reconnectMarkerPath = Get-ReconnectMarkerPath -SettingsFile $settingsFile

if (-not $update.Changed) {
    Write-Host "[STABIL] Proton VPN uygulama rotalari zaten guncel." -ForegroundColor Green
    # An earlier run may have changed the file without the tunnel being rebuilt.
    Wait-ProtonReconnect -MarkerPath $reconnectMarkerPath
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
        $settingsChangedUtc = [DateTime]::UtcNow
        $backupPath = Write-SettingsAtomically -SettingsFile $settingsFile -RootObject $settings.Root -Apps $update.Apps
        Set-ProtonReconnectPending -MarkerPath $reconnectMarkerPath -SettingsChangedUtc $settingsChangedUtc
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

Wait-ProtonReconnect -MarkerPath $reconnectMarkerPath
