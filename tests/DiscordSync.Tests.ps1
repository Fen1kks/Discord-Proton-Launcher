param([string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
foreach ($edition in @('Standard', 'Developer-Equicord')) {
    $path = Join-Path $ProjectRoot "$edition/vpn_sync.ps1"
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failure: $errors" }
    foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    & {
        $script:discordCandidates = @(
            [pscustomobject]@{ Name = 'app-1.0.9'; FullName = 'C:\TestDiscord\app-1.0.9'; LastWriteTimeUtc = [datetime]'2026-09-06' },
            [pscustomobject]@{ Name = 'app-1.0.10'; FullName = 'C:\TestDiscord\app-1.0.10'; LastWriteTimeUtc = [datetime]'2026-09-01' },
            [pscustomobject]@{ Name = 'app-1.0.11'; FullName = 'C:\TestDiscord\app-1.0.11'; LastWriteTimeUtc = [datetime]'2026-09-02' },
            [pscustomobject]@{ Name = 'app-9.0.0'; FullName = 'C:\TestDiscord\app-9.0.0'; LastWriteTimeUtc = [datetime]'2026-09-06' }
        )
        function Get-ChildItem {
            param($LiteralPath, [switch]$Directory, $Filter, $ErrorAction)
            return $script:discordCandidates
        }
        function Test-Path {
            param($LiteralPath, $PathType)
            if ($LiteralPath -eq 'C:\TestDiscord\app-9.0.0\Discord.exe') { return $false }
            if ($LiteralPath -like 'C:\TestDiscord\app-1.0.11\resources\*') { return $false }
            return $true
        }
        if ((Get-LatestDiscordExecutable) -ne 'C:\TestDiscord\app-1.0.10\Discord.exe') {
            throw 'Discord selection must sort numeric versions, ignore folder recency, and skip missing executables or incomplete installations.'
        }
        $script:discordCandidates = @()
        $rejected = $false
        try { Get-LatestDiscordExecutable | Out-Null }
        catch {
            if ($_.Exception.Message -ne 'Guncel Discord.exe bulunamadi.') { throw }
            $rejected = $true
        }
        if (-not $rejected) { throw 'Missing Discord installation must be reported.' }
    }
    $other = [pscustomobject]@{ AppFilePath = 'C:\Roblox\RobloxPlayerBeta.exe'; IsActive = $true }
    $old = [pscustomobject]@{ AppFilePath = 'C:\Discord\app-1.0.9255\Discord.exe'; IsActive = $false; AlternateAppFilePaths = @(); Custom = 'preserve' }
    $newPath = 'C:\Discord\app-1.0.9256\Discord.exe'
    $result = Set-TargetEntries -Apps @($other, $old) -Paths @($newPath)
    if (-not $result.Changed -or $result.Apps.Count -ne 2 -or $old.AppFilePath -ne $newPath -or -not $old.IsActive -or $old.Custom -ne 'preserve' -or $other.AppFilePath -ne 'C:\Roblox\RobloxPlayerBeta.exe') { throw 'Discord migration must preserve other apps and custom fields.' }
    $again = Set-TargetEntries -Apps $result.Apps -Paths @($newPath)
    if ($again.Changed) { throw 'Repeated Discord synchronization must be stable.' }
    $added = Set-TargetEntries -Apps @() -Paths @($newPath)
    if (-not $added.Changed -or $added.Apps.Count -ne 1 -or $added.Apps[0].AppFilePath -ne $newPath) { throw 'First-time Discord entry failed.' }

    $testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('discord-sync-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $testDirectory
    try {
        $settingsPath = Join-Path $testDirectory 'UserSettings-test.json'
        $original = '{"SplitTunnelingInverseAppsList":"[]","UnrelatedSetting":"preserve"}'
        [IO.File]::WriteAllText($settingsPath, $original)
        $settingsFile = Get-Item -LiteralPath $settingsPath
        $settings = Read-ProtonSettings -SettingsFile $settingsFile
        $backup = Write-SettingsAtomically -SettingsFile $settingsFile -RootObject $settings.Root -Apps $result.Apps
        if ([IO.File]::ReadAllText($backup) -ne $original) { throw 'Atomic replacement must back up the exact original.' }
        $saved = Read-ProtonSettings -SettingsFile $settingsFile
        if ($saved.Root.UnrelatedSetting -ne 'preserve' -or $saved.Apps.Count -ne 2 -or $saved.Apps[1].AppFilePath -ne $newPath) { throw 'Saved Discord settings did not round-trip correctly.' }
        if (@(Get-ChildItem -LiteralPath $testDirectory -Filter '*.tmp').Count -ne 0) { throw 'Atomic save left temporary files.' }
    }
    finally {
        $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTestDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedTestDirectory -Leaf) -notlike 'discord-sync-test-*') { throw 'Unexpected test cleanup path.' }
        Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
    }

    $reconnectDirectory = Join-Path ([IO.Path]::GetTempPath()) ('discord-sync-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $reconnectDirectory
    $previousNoDialog = $env:DISCORD_LAUNCHER_NO_DIALOG
    $env:DISCORD_LAUNCHER_NO_DIALOG = '1'
    try {
        # Sequence from a real failure: the client restart re-attached to the running tunnel without reconnecting.
        $script:testProtonLog = Join-Path $reconnectDirectory 'client-logs.txt'
        [IO.File]::WriteAllText($script:testProtonLog, (@(
            '2026-10-20T04:26:26.423Z | INFO  | CONN.CONNECT:TRIGGER | [CONNECTION_PROCESS] Status updated to Disconnected. | {}',
            '2026-10-20T04:26:28.800Z | INFO  | CONN.CONNECT:TRIGGER | [CONNECTION_PROCESS] Status updated to Connecting. | {}',
            '2026-10-20T04:26:31.997Z | INFO  | CONN.CONNECT:TRIGGER | [CONNECTION_PROCESS] Status updated to Connected. Connected to server US-MA#170 | {}',
            '2026-10-20T07:49:56.853Z | INFO  | PROCESS.COMM | Received connection details change while connected to server | {}',
            '2026-10-20T07:50:05.904Z | INFO  | CONN.CONNECT:TRIGGER | [CONNECTION_PROCESS] Status updated to Connected. Connected to server US-MA#170 | {}'
        ) -join "`r`n") + "`r`n")
        function Get-ProtonClientLogFiles { return @($script:testProtonLog) }
        $changedUtc = [DateTime]::SpecifyKind([DateTime]'2026-10-20T07:49:53', [DateTimeKind]::Utc)

        # Proton keeps its log open for writing while it runs.
        $writer = New-Object IO.FileStream($script:testProtonLog, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        try { $events = @(Get-ProtonConnectionEvents -LogPaths (Get-ProtonClientLogFiles)) }
        finally { $writer.Dispose() }
        if ($events.Count -ne 4 -or $events[0].Status -ne 'Disconnected' -or $events[-1].Status -ne 'Connected' -or $events[1].TimeUtc -ne [DateTime]::SpecifyKind([DateTime]'2026-10-20T04:26:28.800', [DateTimeKind]::Utc)) {
            throw 'Proton connection events must be parsed in UTC from a log that is open for writing.'
        }
        if ((Get-ProtonReconnectState -Events $events -SinceUtc $changedUtc) -ne 'Pending') { throw 'Re-attaching to a running tunnel must not count as a reconnect.' }
        if ((Get-ProtonReconnectState -Events $events -SinceUtc $changedUtc.AddHours(-4)) -ne 'Applied') { throw 'A connection attempt after the change must apply the new list.' }
        if ((Get-ProtonReconnectState -Events @() -SinceUtc $changedUtc) -ne 'Unknown') { throw 'An unreadable Proton log must be reported as unknown.' }
        $disconnected = @($events) + [pscustomobject]@{ TimeUtc = $changedUtc.AddMinutes(5); Status = 'Disconnected' }
        if ((Get-ProtonReconnectState -Events $disconnected -SinceUtc $changedUtc) -ne 'Disconnected') { throw 'A disconnected tunnel must not wait for a reconnect.' }

        $settingsFile = [pscustomobject]@{ DirectoryName = $reconnectDirectory }
        $markerPath = Get-ReconnectMarkerPath -SettingsFile $settingsFile
        Wait-ProtonReconnect -MarkerPath $markerPath -TimeoutSeconds 1
        $null = New-Item -ItemType Directory -Path (Split-Path $markerPath -Parent)
        Set-ProtonReconnectPending -MarkerPath $markerPath -SettingsChangedUtc $changedUtc
        if ((Get-Item -LiteralPath $markerPath).LastWriteTimeUtc -ne $changedUtc) { throw 'The reconnect marker must record the settings change time.' }
        $timedOut = $false
        try { Wait-ProtonReconnect -MarkerPath $markerPath -TimeoutSeconds 1 }
        catch {
            if ($_.Exception.Message -notlike 'Proton VPN 1 saniye icinde yeniden baglanmadi*') { throw }
            $timedOut = $true
        }
        if (-not $timedOut -or -not (Test-Path -LiteralPath $markerPath)) { throw 'A stale tunnel must stop the launch and keep the reconnect pending.' }
        [IO.File]::AppendAllText($script:testProtonLog, "2026-10-20T08:00:00.000Z | INFO  | CONN.CONNECT:TRIGGER | [CONNECTION_PROCESS] Status updated to Connecting. | {}`r`n")
        Wait-ProtonReconnect -MarkerPath $markerPath -TimeoutSeconds 1
        if (Test-Path -LiteralPath $markerPath) { throw 'A reconnect after the change must clear the pending marker.' }
    }
    finally {
        $env:DISCORD_LAUNCHER_NO_DIALOG = $previousNoDialog
        $resolvedReconnectDirectory = [IO.Path]::GetFullPath($reconnectDirectory)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedReconnectDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedReconnectDirectory -Leaf) -notlike 'discord-sync-test-*') { throw 'Unexpected test cleanup path.' }
        Remove-Item -LiteralPath $resolvedReconnectDirectory -Recurse -Force
    }
    Write-Host "$edition Discord checks passed: version selection, missing install, migration, repeat sync, first entry, atomic save and backup, Proton reconnect detection."
}