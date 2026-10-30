$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
foreach ($shared in @('LauncherBootstrap.ps1', 'LauncherUpdate.ps1', 'vpn_sync.ps1')) {
    if ((Get-FileHash (Join-Path $project "Standard/$shared")).Hash -ne (Get-FileHash (Join-Path $project "Developer-Equicord/$shared")).Hash) {
        throw "Shared file differs between editions: $shared. Copy the edited one over the other."
    }
}
Write-Host 'Passed: shared scripts are identical in both editions.'
