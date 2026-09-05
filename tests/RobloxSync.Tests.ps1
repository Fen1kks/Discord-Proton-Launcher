$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
foreach ($edition in @('Standard', 'Developer-Equicord')) {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) "$edition/vpn_sync.ps1"
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse failure: $errors" }
    # Load functions only: never read or modify the user's Proton settings.
    foreach ($definition in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $other = [pscustomobject]@{ AppFilePath = 'C:\Other\Other.exe'; IsActive = $true }
    $old = [pscustomobject]@{ AppFilePath = 'C:\Roblox\Versions\version-old\RobloxPlayerBeta.exe'; IsActive = $false; AlternateAppFilePaths = @(); Custom = 'preserve' }
    $newPath = 'C:\Roblox\Versions\version-new\RobloxPlayerBeta.exe'
    $result = Set-TargetEntries -Apps @($other, $old) -Paths @($newPath)
    if (-not $result.Changed -or $result.Apps.Count -ne 2 -or $old.AppFilePath -ne $newPath -or -not $old.IsActive -or $old.Custom -ne 'preserve' -or $other.AppFilePath -ne 'C:\Other\Other.exe') { throw 'Migration failed' }
    $again = Set-TargetEntries -Apps $result.Apps -Paths @($newPath)
    if ($again.Changed) { throw 'Repeated synchronization must be stable' }
    $added = Set-TargetEntries -Apps @() -Paths @($newPath)
    if (-not $added.Changed -or $added.Apps.Count -ne 1) { throw 'First-time entry failed' }
    $missing = Get-LatestRobloxExecutable -VersionsDirectory (Join-Path $PSScriptRoot 'missing-roblox-installation')
    if ($null -ne $missing) { throw 'Missing install must return null' }
    Write-Host "$edition checks passed"
}
