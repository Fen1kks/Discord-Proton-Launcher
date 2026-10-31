param([string]$LauncherPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Developer-Equicord/EquicordLauncher.ps1'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
# Sync-Upstream's merge commits need an identity; CI runners have no global git config.
$env:GIT_AUTHOR_NAME = $env:GIT_COMMITTER_NAME = 'test'
$env:GIT_AUTHOR_EMAIL = $env:GIT_COMMITTER_EMAIL = 'test@example.com'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($LauncherPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Parse failure: $errors" }
foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($definition.Name -in @('Invoke-External', 'Get-ExternalOutput', 'Sync-Upstream', 'Get-UserPluginsState')) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}

function Invoke-Git {
    param([string]$Directory, [string[]]$Arguments)
    $null = & git.exe -C $Directory -c user.name=test -c user.email=test@example.com @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in $Directory" }
}

function New-Commit {
    param([string]$Directory, [string]$File, [string]$Content)
    [IO.File]::WriteAllText((Join-Path $Directory $File), $Content)
    Invoke-Git $Directory @('add', '-A')
    Invoke-Git $Directory @('commit', '--quiet', '-m', "edit $File")
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('launcher-sync-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
try {
    $upstream = Join-Path $testRoot 'upstream'
    $repoPath = Join-Path $testRoot 'fork'
    $upstreamRemoteName = 'upstream'
    $upstreamBranchName = 'main'
    $null = New-Item -ItemType Directory -Path $upstream
    Invoke-Git $upstream @('init', '--quiet', '-b', 'main')
    New-Commit $upstream 'shared.txt' 'base'
    Invoke-Git $testRoot @('clone', '--quiet', '-o', 'upstream', $upstream, $repoPath)

    New-Commit $upstream 'upstream-only.txt' 'new upstream file'
    [IO.File]::WriteAllText((Join-Path $repoPath 'uncommitted.txt'), 'keep me')
    if (Sync-Upstream) { throw 'A clean fast-forward must not warn.' }
    if ((& git.exe -C $repoPath rev-parse HEAD) -ne (& git.exe -C $upstream rev-parse HEAD)) { throw 'A clean sync must leave the repo identical to upstream.' }
    if ([IO.File]::ReadAllText((Join-Path $repoPath 'uncommitted.txt')) -ne 'keep me') { throw 'Uncommitted files were not preserved.' }

    New-Commit $upstream 'shared.txt' 'upstream side'
    New-Commit $repoPath 'shared.txt' 'fork side'
    $headBefore = (& git.exe -C $repoPath rev-parse HEAD)
    $warning = Sync-Upstream
    if (-not $warning -or $warning -notlike '*ileri sarilamadi*') { throw 'A diverged repo must return a warning.' }
    if ((& git.exe -C $repoPath rev-parse HEAD) -ne $headBefore) { throw 'A refused fast-forward must leave HEAD unchanged.' }
    if ([IO.File]::ReadAllText((Join-Path $repoPath 'uncommitted.txt')) -ne 'keep me') { throw 'A refused fast-forward must keep uncommitted files.' }

    $upstreamRemoteName = 'missing'
    if ((Sync-Upstream) -notlike '*alinamadi*') { throw 'A failed fetch must return a warning instead of throwing.' }

    if ($null -ne (Get-UserPluginsState)) { throw 'A repository without userplugins needs no extra build input.' }
    $userPlugins = Join-Path $repoPath 'src\userplugins'
    $null = New-Item -ItemType Directory -Path $userPlugins
    [IO.File]::WriteAllText((Join-Path $userPlugins 'plugin.ts'), 'one')
    $first = (Get-UserPluginsState).Fingerprint
    if ($first -notlike 'mtime:*') { throw 'Plain userplugins folders must use file times.' }
    Invoke-Git $userPlugins @('init', '--quiet')
    New-Commit $userPlugins 'plugin.ts' 'two'
    $state = Get-UserPluginsState
    if ($state.Fingerprint -ne (& git.exe -C $userPlugins rev-parse HEAD) -or $state.Status) { throw 'A userplugins repository must use its HEAD and clean status.' }
    [IO.File]::WriteAllText((Join-Path $userPlugins 'plugin.ts'), 'three')
    if (-not (Get-UserPluginsState).Status) { throw 'Uncommitted userplugins changes must be reported.' }

    Write-Host 'Passed: fast-forward, diverged repo refusal, fetch failure, preserved local files, and userplugins build inputs.'
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'launcher-sync-test-*') {
        throw 'Unexpected test cleanup path.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
