$ErrorActionPreference = 'Stop'
$env:DISCORD_LAUNCHER_NO_DIALOG = '1'
$project = Split-Path $PSScriptRoot -Parent
. (Join-Path $project 'Standard/LauncherUpdate.ps1')
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('launcher-update-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory $sandbox
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action) {
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    Assert $rejected 'Expected rejection.'
}
try {
    foreach ($edition in @('Standard', 'Developer-Equicord')) {
        $root = Join-Path $sandbox $edition
        $null = New-Item -ItemType Directory $root
        Copy-Item "$project/$edition/*" $root -Exclude logs
        $launcher = if ($edition -eq 'Standard') { 'DiscordLauncher.ps1' } else { 'EquicordLauncher.ps1' }
        $originalLauncher = [IO.File]::ReadAllText((Join-Path $root $launcher))
        [IO.File]::WriteAllText((Join-Path $root $launcher), 'exit 0')
        & powershell.exe -NoProfile -File (Join-Path $root 'LauncherBootstrap.ps1') -Target $launcher -WhatIf
        Assert ($LASTEXITCODE -eq 0 -and -not (Test-Path (Join-Path $root '.updates'))) 'Read-only bootstrap created update state.'
        [IO.File]::WriteAllText((Join-Path $root $launcher), $originalLauncher)
        $payload = Join-Path $sandbox "$edition-payload"
        $null = New-Item -ItemType Directory $payload
        foreach ($file in Get-ReleaseFiles $edition) { Copy-Item (Join-Path $root $file) $payload }
        [IO.File]::WriteAllText((Join-Path $payload 'release.json'), (@{Version='1.1.1';Edition=$edition;Protocol=1} | ConvertTo-Json))
        $script:fixtureZip = Join-Path $sandbox "$edition.zip"
        Compress-Archive "$payload/*" $script:fixtureZip
        $script:digest = 'sha256:' + (Get-FileHash $script:fixtureZip).Hash
        $script:requests = 0
        $script:offline = $false
        $script:release = [pscustomobject]@{
            draft=$false; prerelease=$false; tag_name='v1.1.1'
            assets=@([pscustomobject]@{name="Discord-Proton-Launcher-$edition.zip";size=1000;digest=$script:digest;browser_download_url="https://github.com/Fen1kks/Discord-Proton-Launcher/releases/download/v1.1.1/Discord-Proton-Launcher-$edition.zip"})
        }
        function Invoke-RestMethod { param($Uri,$Headers,$TimeoutSec) $script:requests++; if ($script:offline) { throw 'Offline' }; return $script:release }
        function Invoke-WebRequest { param($Uri,$Headers,$OutFile,$TimeoutSec,[switch]$UseBasicParsing) Copy-Item $script:fixtureZip $OutFile }
        [IO.File]::WriteAllText((Join-Path $root 'launcher-config.json'), '{"personal":"keep"}')
        $active = Invoke-LauncherUpdate -Root $root -Active $root
        Assert ($active -ne $root) 'New release was not activated.'
        Assert ((Get-Content (Join-Path $root 'launcher-config.json') -Raw) -eq '{"personal":"keep"}') 'Personal config changed.'
        Assert ((Get-Content (Join-Path $root 'release.json') -Raw | ConvertFrom-Json).Version -eq '1.1.0') 'Original install changed.'
        Assert ((Invoke-LauncherUpdate -Root $root -Active $active) -eq $active) 'Cached version changed.'
        Assert ($script:requests -eq 1) 'Daily throttle failed.'
        Assert ((Invoke-LauncherUpdate -Root $root -Active $active -Force) -eq $active) 'Manual check changed current version.'
        Assert ($script:requests -eq 2) 'Manual check did not bypass daily throttle.'
        Set-ActiveRelease -Root $root -Directory (Split-Path $active -Leaf)
        Assert (Test-Path (Join-Path $root '.updates/current.json.bak')) 'Atomic replacement did not retain old pointer.'
        Remove-Item (Join-Path $root '.updates/last-check.txt')
        $script:release.tag_name = 'v1.0.0'
        Assert ((Invoke-LauncherUpdate -Root $root -Active $active) -eq $active) 'Downgrade accepted.'
        Remove-Item (Join-Path $root '.updates/last-check.txt')
        $script:release.tag_name = 'v1.1.1'
        $script:offline = $true
        $pointerBefore = Get-Content (Join-Path $root '.updates/current.json') -Raw
        Assert-Rejected { Invoke-LauncherUpdate -Root $root -Active $active }
        Assert ((Get-Content (Join-Path $root '.updates/current.json') -Raw) -eq $pointerBefore) 'Offline request changed active release.'
        Assert-Rejected { Expand-VerifiedRelease $script:fixtureZip ('sha256:' + ('0' * 64)) (Join-Path $sandbox 'bad-hash') $edition ([version]'1.1.1') }
        Assert-Rejected { Expand-VerifiedRelease $script:fixtureZip $script:digest (Join-Path $sandbox "$edition-bad-version") $edition ([version]'1.1.2') }
        [IO.File]::WriteAllText((Join-Path $payload 'unexpected.ps1'), 'throw "unexpected"')
        $badZip = Join-Path $sandbox "$edition-extra.zip"
        Compress-Archive "$payload/*" $badZip
        Assert-Rejected { Expand-VerifiedRelease $badZip ('sha256:' + (Get-FileHash $badZip).Hash) (Join-Path $sandbox "$edition-extra") $edition ([version]'1.1.1') }
        # Test the real bootstrap in a child process without starting Discord or Proton.
        $launcher = if ($edition -eq 'Standard') { 'DiscordLauncher.ps1' } else { 'EquicordLauncher.ps1' }
        [IO.File]::WriteAllText((Join-Path $active $launcher), 'Write-Output ("FORWARDED=" + ($args -join "|")); Write-Output ("DATA=" + $env:DISCORD_PROTON_DATA_ROOT); exit 7')
        $output = & powershell.exe -NoProfile -File (Join-Path $root 'LauncherBootstrap.ps1') -Target $launcher -CheckOnly -RepositoryPath 'C:\path with spaces'
        Assert ($LASTEXITCODE -eq 7) 'Bootstrap lost exit code.'
        Assert (($output -join "`n") -like '*FORWARDED=-CheckOnly|-RepositoryPath|C:\path with spaces*') 'Bootstrap lost arguments.'
        Assert (($output -join "`n").Contains("DATA=$root")) 'Data root was not preserved.'
        [IO.File]::WriteAllText((Join-Path $active 'LauncherUpdate.ps1'), 'function Invoke-LauncherUpdate { param($Root,$Active,[switch]$Force) if (-not $Force) { throw "Force missing" }; Write-Host "MANUAL_OK"; return $Active }')
        $output = & powershell.exe -NoProfile -File (Join-Path $root 'LauncherBootstrap.ps1') -UpdateOnly
        Assert ($LASTEXITCODE -eq 0) 'Manual bootstrap failed.'
        Assert (($output -join "`n").Contains('MANUAL_OK')) 'Manual updater was not invoked.'
        Assert (-not ($output -join "`n").Contains('FORWARDED=')) 'Manual update launched an application.'
        # Force a network error in the selected updater; bootstrap must still launch it.
        [IO.File]::WriteAllText((Join-Path $active 'LauncherUpdate.ps1'), 'function Invoke-LauncherUpdate { throw "simulated offline" }')
        $output = & powershell.exe -NoProfile -File (Join-Path $root 'LauncherBootstrap.ps1') -Target $launcher
        Assert ($LASTEXITCODE -eq 7) 'Bootstrap did not continue after update failure.'
        $output = & powershell.exe -NoProfile -File (Join-Path $root 'LauncherBootstrap.ps1') -UpdateOnly
        Assert ($LASTEXITCODE -eq 1) 'Manual update failure was not reported.'
        Assert (-not ($output -join "`n").Contains('FORWARDED=')) 'Failed manual update launched an application.'
        Assert-Rejected { Set-ActiveRelease $root '../escape' }
    }
    foreach ($invalid in @('v1.2.3-beta', '../x', '1.2', '01.2.3')) { Assert-Rejected { Read-ReleaseVersion $invalid } }
    Assert ((Read-ReleaseVersion 'v1.10.0') -gt (Read-ReleaseVersion 'v1.9.0')) 'Version comparison is lexical.'
    Write-Host 'Passed: both editions, verified install, cache, downgrade, offline fallback, hash/version/extra-file rejection, preserved settings, bootstrap arguments and exit code.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($sandbox)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'launcher-update-test-*') { throw 'Unsafe cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
