param([string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
foreach ($launcher in @('Standard/DiscordLauncher.ps1', 'Developer-Equicord/EquicordLauncher.ps1')) {
    $path = Join-Path $ProjectRoot $launcher
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failure: $errors" }
    foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        if ($definition.Name -eq 'Assert-DiscordUpdaterReachable') {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }
    $source = [IO.File]::ReadAllText($path)
    $waitPosition = $source.LastIndexOf('Wait-ForDiscordExecutable')
    $checkPosition = $source.IndexOf('    Assert-DiscordUpdaterReachable -SinceUtc $launchStartedUtc')
    if ($checkPosition -lt 0 -or $checkPosition -lt $waitPosition -or $checkPosition -gt $source.IndexOf('[TAMAM]')) {
        throw "$launcher must verify the Discord updater after the final launch and before reporting success."
    }

    $testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('discord-updater-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $testDirectory
    try {
        $logPath = Join-Path $testDirectory 'Discord_updater_rCURRENT.log'
        $failure = '[2026-10-20 13:57:43.697625 +03:00] ERROR [updater_client]: Failed 0: Other(Reqwest(reqwest::Error { kind: Request, source: hyper::Error(Connect, Os { code: 10054, kind: ConnectionReset, message: "reset" }) }))'
        $complete = '[2026-10-20 14:10:23.477481 +03:00] INFO [updater_client::install]: Update to latest complete.'
        [IO.File]::WriteAllText($logPath, "$failure`n")
        $launchUtc = [DateTime]::SpecifyKind([DateTime]'2026-10-20T10:57:40', [DateTimeKind]::Utc)

        $rejected = $false
        try { Assert-DiscordUpdaterReachable -SinceUtc $launchUtc -TimeoutSeconds 1 -LogPath $logPath }
        catch {
            if ($_.Exception.Message -notlike 'Discord guncelleme sunucusuna ulasamadi*') { throw }
            $rejected = $true
        }
        if (-not $rejected) { throw 'A connection reset after launch must fail the launch.' }

        [IO.File]::AppendAllText($logPath, "$complete`n")
        Assert-DiscordUpdaterReachable -SinceUtc $launchUtc.AddMinutes(5) -TimeoutSeconds 1 -LogPath $logPath

        $warnings = @(Assert-DiscordUpdaterReachable -SinceUtc $launchUtc.AddHours(1) -TimeoutSeconds 1 -LogPath $logPath 3>&1)
        if ($warnings.Count -ne 1 -or [string]$warnings[0] -notlike '*VPN rotasi dogrulanamadi*') { throw 'A missing updater result must only warn.' }
        $missing = @(Assert-DiscordUpdaterReachable -SinceUtc $launchUtc -TimeoutSeconds 1 -LogPath (Join-Path $testDirectory 'missing.log') 3>&1)
        if ($missing.Count -ne 1) { throw 'A missing updater log must only warn.' }
    }
    finally {
        $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTestDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedTestDirectory -Leaf) -notlike 'discord-updater-test-*') { throw 'Unexpected test cleanup path.' }
        Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
    }
    Write-Host "$launcher updater checks passed: launch order, connection reset, completed update, older failures and missing results."
}
