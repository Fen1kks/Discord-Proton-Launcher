param(
    [ValidateSet('DiscordLauncher.ps1', 'EquicordLauncher.ps1', 'vpn_sync.ps1')][string]$Target,
    [switch]$UpdateOnly
)

# Keep this small entry point compatible with update protocol 1.
$ErrorActionPreference = 'Stop'
$forwardArguments = @($args)
$root = $PSScriptRoot
$readOnly = @($forwardArguments | Where-Object { $_ -match '^-(CheckOnly|WhatIf)(:.*)?$' }).Count -gt 0
$sha = [Security.Cryptography.SHA256]::Create()
try { $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-', '') }
finally { $sha.Dispose() }
$mutex = New-Object Threading.Mutex($false, "Local\DiscordProtonUpdate-$key")
$locked = $false
$code = 1
try {
    if (-not $UpdateOnly -and -not $Target) { throw 'Başlatılacak uygulama belirtilmedi.' }
    if ($UpdateOnly -and $forwardArguments.Count) { throw 'Manuel güncelleme ek başlatma parametresi kabul etmez.' }
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Bu başlatıcı zaten çalışıyor.' }
    $active = $root
    $pointer = Join-Path $root '.updates/current.json'
    if (Test-Path -LiteralPath $pointer) {
        try {
            $id = (Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json).Directory
            if ($id -notmatch '^release-[a-f0-9]{32}$') { throw 'Geçersiz sürüm klasörü.' }
            $candidate = Join-Path $root ".updates/$id"
            foreach ($required in @($Target, 'LauncherUpdate.ps1', 'release.json', 'vpn_sync.ps1') | Where-Object { $_ }) {
                if (-not (Test-Path -LiteralPath (Join-Path $candidate $required) -PathType Leaf)) { throw 'Eksik sürüm dosyası.' }
            }
            $active = $candidate
        }
        catch { Write-Warning "Kayıtlı sürüm okunamadı; ilk kurulum kullanılıyor: $_" }
    }
    $sourceCheckout = Test-Path -LiteralPath (Join-Path (Split-Path $root -Parent) '.git')
    if ($UpdateOnly -and $sourceCheckout) { throw 'Kaynak kod klasörü güncellenmez. Yayımlanan ZIP paketini kullanın.' }
    if (-not $readOnly -and -not $sourceCheckout) {
        try {
            . (Join-Path $active 'LauncherUpdate.ps1')
            if ($UpdateOnly) {
                Write-Host 'Güncellemeler denetleniyor...'
                $active = Invoke-LauncherUpdate -Root $root -Active $active -Force
            }
            else { $active = Invoke-LauncherUpdate -Root $root -Active $active }
        }
        catch {
            if ($UpdateOnly) { throw }
            Write-Warning "Güncelleme atlandı; mevcut sürümle devam ediliyor: $_"
        }
    }
    if ($UpdateOnly) { $code = 0 }
    else {
        $env:DISCORD_PROTON_DATA_ROOT = $root
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $active $Target) @forwardArguments
        $code = $LASTEXITCODE
    }
}
catch { Write-Host "[HATA] $_" -ForegroundColor Red }
finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $code
