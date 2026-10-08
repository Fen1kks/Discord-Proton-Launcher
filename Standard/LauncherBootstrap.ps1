param(
    [ValidateSet('DiscordLauncher.ps1', 'EquicordLauncher.ps1', 'vpn_sync.ps1')][string]$Target,
    [switch]$UpdateOnly
)

# Keep this small entry point compatible with update protocol 1.
$ErrorActionPreference = 'Stop'
$forwardArguments = @($args)
$root = $PSScriptRoot
$readOnly = @($forwardArguments | Where-Object { $_ -match '^-(CheckOnly|WhatIf)(:.*)?$' }).Count -gt 0
function Show-LauncherFailureDialog {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$LogPath = $null
    )

    if ($env:DISCORD_LAUNCHER_NO_DIALOG -or $env:CI) { return }

    $dialogText = "Baslatici bir hata nedeniyle tamamlanamadi:`n`n$Message"
    $hasLog = ($LogPath -and (Test-Path -LiteralPath $LogPath -PathType Leaf))
    if ($hasLog) {
        $dialogText += "`n`nAyrintili hata gunlugunu (log) Not Defteri ile acmak ister misiniz?"
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $buttons = if ($hasLog) { [System.Windows.Forms.MessageBoxButtons]::YesNo } else { [System.Windows.Forms.MessageBoxButtons]::OK }
        $result = [System.Windows.Forms.MessageBox]::Show($dialogText, $Title, $buttons, [System.Windows.Forms.MessageBoxIcon]::Error)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes -and $hasLog) {
            Start-Process -FilePath 'notepad.exe' -ArgumentList $LogPath
        }
    }
    catch {
        try {
            $wshell = New-Object -ComObject WScript.Shell
            $btnType = if ($hasLog) { 4 } else { 0 }
            $res = $wshell.Popup($dialogText, 0, $Title, $btnType + 16)
            if ($res -eq 6 -and $hasLog) {
                Start-Process -FilePath 'notepad.exe' -ArgumentList $LogPath
            }
        }
        catch { }
    }
}

$sha = [Security.Cryptography.SHA256]::Create()
try { $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant()))).Replace('-', '') }
finally { $sha.Dispose() }
$mutex = New-Object Threading.Mutex($false, "Local\DiscordProtonUpdate-$key")
$locked = $false
$code = 1
$bootstrapFailure = $null
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
catch {
    $bootstrapFailure = $_
    Write-Host "[HATA] $_" -ForegroundColor Red
}
finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    if ($bootstrapFailure -and -not $readOnly -and -not $env:DISCORD_LAUNCHER_NO_DIALOG -and -not $env:CI) {
        $logDir = Join-Path $root 'logs'
        $bootstrapLog = $null
        try {
            if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $bootstrapLog = Join-Path $logDir ("launcher-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
            $logContent = "[{0}] [HATA]`r`n{1}`r`n`r`nAyrintilar:`r`n{2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $bootstrapFailure.Exception.Message, $bootstrapFailure.ScriptStackTrace
            [IO.File]::WriteAllText($bootstrapLog, $logContent, [Text.Encoding]::UTF8)
        }
        catch { }
        Show-LauncherFailureDialog -Title 'Launcher - Hata' -Message $bootstrapFailure.Exception.Message -LogPath $bootstrapLog
    }
}
exit $code
