param([string]$Version)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Standard/LauncherUpdate.ps1')
$parsed = Read-ReleaseVersion $Version
$output = Join-Path $root 'dist'
$null = New-Item -ItemType Directory -Path $output -Force
foreach ($edition in @('Standard', 'Developer-Equicord')) {
    $source = Join-Path $root $edition
    $meta = Get-Content -LiteralPath (Join-Path $source 'release.json') -Raw | ConvertFrom-Json
    if ((Read-ReleaseVersion $meta.Version) -ne $parsed -or $meta.Edition -cne $edition -or $meta.Protocol -ne 1) { throw "release.json does not match tag: $edition" }
    foreach ($shared in @('LauncherBootstrap.ps1', 'LauncherUpdate.ps1')) {
        if ((Get-FileHash (Join-Path $root "Standard/$shared")).Hash -ne (Get-FileHash (Join-Path $source $shared)).Hash) { throw "Shared file differs: $shared" }
    }
    $files = @(Get-ReleaseFiles $edition | ForEach-Object { Join-Path $source $_ })
    foreach ($file in $files | Where-Object { $_ -like '*.ps1' }) {
        $bytes = [IO.File]::ReadAllBytes($file)
        $text = [IO.File]::ReadAllText($file)
        if ($text -cmatch '[^\x00-\x7F]' -and -not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) {
            throw "Non-ASCII PowerShell scripts require UTF-8 BOM for Windows PowerShell 5.1: $file"
        }
    }
    $zip = Join-Path $output "Discord-Proton-Launcher-$edition.zip"
    Compress-Archive -LiteralPath $files -DestinationPath $zip -Force
    $digest = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$zip.sha256", "$digest  $([IO.Path]::GetFileName($zip))`n")
    Write-Host "Built $zip"
}
