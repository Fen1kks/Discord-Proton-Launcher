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
            [pscustomobject]@{ Name = 'app-9.0.0'; FullName = 'C:\TestDiscord\app-9.0.0'; LastWriteTimeUtc = [datetime]'2026-09-06' }
        )
        function Get-ChildItem {
            param($LiteralPath, [switch]$Directory, $Filter, $ErrorAction)
            return $script:discordCandidates
        }
        function Test-Path {
            param($LiteralPath, $PathType)
            return $LiteralPath -ne 'C:\TestDiscord\app-9.0.0\Discord.exe'
        }
        if ((Get-LatestDiscordExecutable) -ne 'C:\TestDiscord\app-1.0.10\Discord.exe') {
            throw 'Discord selection must sort numeric versions, ignore folder recency, and skip missing executables.'
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
    Write-Host "$edition Discord checks passed: version selection, missing install, migration, repeat sync, first entry, atomic save and backup."
}