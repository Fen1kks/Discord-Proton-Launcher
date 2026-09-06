param([string]$LauncherPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Developer-Equicord/EquicordLauncher.ps1'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($LauncherPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Parse failure: $errors" }
foreach ($definition in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($definition.Name -in @('Get-ExternalOutput', 'Assert-RepositoryReady')) {
        . ([scriptblock]::Create($definition.Extent.Text))
    }
}
$source = [IO.File]::ReadAllText($LauncherPath)
$guardPosition = $source.IndexOf('    Assert-RepositoryReady -RepositoryPath $repoPath')
if ($guardPosition -lt 0 -or $guardPosition -gt $source.IndexOf('    if ($CheckOnly)') -or $guardPosition -gt $source.IndexOf('    Write-Step "Discord kapatiliyor"')) {
    throw 'Repository preflight must run before CheckOnly and stopping Discord.'
}
$testRepo = Join-Path ([IO.Path]::GetTempPath()) ('launcher-git-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRepo
try {
    & git.exe init --quiet $testRepo
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize test repository.' }
    Assert-RepositoryReady -RepositoryPath $testRepo
    foreach ($operation in @('rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'sequencer')) {
        $marker = Join-Path $testRepo ".git/$operation"
        if ($operation -in @('rebase-merge', 'rebase-apply', 'sequencer')) {
            $null = New-Item -ItemType Directory -Path $marker
        }
        else {
            [IO.File]::WriteAllText($marker, 'test')
        }
        $rejected = $false
        try { Assert-RepositoryReady -RepositoryPath $testRepo }
        catch {
            if ($_.Exception.Message -notlike "*tamamlanmamis Git islemi var: $operation.*") { throw }
            $rejected = $true
        }
        if (-not $rejected -or -not (Test-Path -LiteralPath $marker)) { throw "Pending $operation was not preserved and rejected." }
        Remove-Item -LiteralPath $marker
    }
    $blob = 'test' | & git.exe -C $testRepo hash-object -w --stdin
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create test blob.' }
    "100644 $blob 1`tconflict.txt`n100644 $blob 2`tconflict.txt" | & git.exe -C $testRepo update-index --index-info
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create unmerged test index.' }
    $rejected = $false
    try { Assert-RepositoryReady -RepositoryPath $testRepo }
    catch {
        if ($_.Exception.Message -notlike '*cozulmemis dosya cakismalari*') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Unmerged index was accepted.' }
    & git.exe -C $testRepo read-tree --empty
    if ($LASTEXITCODE -ne 0) { throw 'Cannot clear test index.' }
    [IO.File]::WriteAllText((Join-Path $testRepo 'local-change.txt'), 'preserve')
    Assert-RepositoryReady -RepositoryPath $testRepo
    Write-Host 'Passed: clean repository, six pending operations, unmerged index, local files, and preflight ordering.'
}
finally {
    $resolvedTestRepo = [IO.Path]::GetFullPath($testRepo)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedTestRepo.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolvedTestRepo -Leaf) -notlike 'launcher-git-test-*') {
        throw 'Unexpected test cleanup path.'
    }
    Remove-Item -LiteralPath $resolvedTestRepo -Recurse -Force
}