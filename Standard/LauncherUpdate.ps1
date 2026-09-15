function Read-ReleaseVersion {
    param([string]$Text)
    if ($Text -notmatch '^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Sürüm X.Y.Z biçiminde olmalı.' }
    return [version]$Text.TrimStart('v')
}

function Get-ReleaseFiles {
    param([string]$Edition)
    $launcher = switch ($Edition) {
        'Standard' { 'DiscordLauncher.ps1' }
        'Developer-Equicord' { 'EquicordLauncher.ps1' }
        default { throw 'Bilinmeyen paket türü.' }
    }
    return @($launcher, 'vpn_sync.ps1', 'LauncherUpdate.ps1', 'LauncherBootstrap.ps1', 'release.json',
        $launcher.Replace('.ps1', '.bat'), 'DiscordBaslat.vbs', 'RobloxVpnSync.bat', 'GuncellemeleriDenetle.bat', 'KULLANIM.txt', 'USAGE.txt')
}

function Expand-VerifiedRelease {
    param([string]$Archive, [string]$Digest, [string]$Destination, [string]$Edition, [version]$Version)
    if ($Digest -notmatch '^sha256:[a-fA-F0-9]{64}$') { throw 'GitHub SHA-256 bilgisi eksik.' }
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $Digest.Substring(7)) { throw 'Paket SHA-256 doğrulaması başarısız.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $allowed = @(Get-ReleaseFiles $Edition)
        $seen = @{}
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -cnotin $allowed -or $seen.ContainsKey($entry.FullName) -or $entry.Length -gt 5MB) { throw 'Paket beklenmeyen dosya içeriyor.' }
            $seen[$entry.FullName] = $true
        }
        if ($seen.Count -ne $allowed.Count) { throw 'Paket dosyaları eksik.' }
        $null = New-Item -ItemType Directory -Path $Destination -ErrorAction Stop
        foreach ($entry in $zip.Entries) {
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Destination $entry.FullName))
        }
    }
    finally { $zip.Dispose() }
    $meta = Get-Content -LiteralPath (Join-Path $Destination 'release.json') -Raw | ConvertFrom-Json
    if ($meta.Edition -cne $Edition -or $meta.Protocol -ne 1 -or (Read-ReleaseVersion $meta.Version) -ne $Version) { throw 'Paket sürümü veya türü uyuşmuyor.' }
    foreach ($file in $allowed | Where-Object { $_ -like '*.ps1' }) {
        $tokens = $null
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Destination $file), [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "Paket betiği okunamıyor: $file" }
    }
}

function Set-ActiveRelease {
    param([string]$Root, [string]$Directory)
    if ($Directory -notmatch '^release-[a-f0-9]{32}$') { throw 'Geçersiz sürüm klasörü.' }
    $pointer = Join-Path $Root '.updates/current.json'
    $temporary = "$pointer.new"
    [IO.File]::WriteAllText($temporary, (@{ Directory = $Directory } | ConvertTo-Json))
    if (Test-Path -LiteralPath $pointer) { [IO.File]::Replace($temporary, $pointer, "$pointer.bak") }
    else { [IO.File]::Move($temporary, $pointer) }
}

function Invoke-LauncherUpdate {
    param([string]$Root, [string]$Active, [switch]$Force)
    $meta = Get-Content -LiteralPath (Join-Path $Active 'release.json') -Raw | ConvertFrom-Json
    $current = Read-ReleaseVersion $meta.Version
    $null = Get-ReleaseFiles $meta.Edition
    $cache = Join-Path $Root '.updates'
    $stamp = Join-Path $cache 'last-check.txt'
    if (-not $Force -and (Test-Path -LiteralPath $stamp)) {
        $checked = [datetime]::MinValue
        if ([datetime]::TryParse((Get-Content -LiteralPath $stamp -Raw), [ref]$checked) -and $checked.ToUniversalTime() -le [datetime]::UtcNow -and $checked.ToUniversalTime() -gt [datetime]::UtcNow.AddDays(-1)) { return $Active }
    }
    $null = New-Item -ItemType Directory -Path $cache -Force
    [IO.File]::WriteAllText($stamp, [datetime]::UtcNow.ToString('o'))
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'Discord-Proton-Launcher'; 'Accept' = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Fen1kks/Discord-Proton-Launcher/releases/latest' -Headers $headers -TimeoutSec 5
    if ($release.draft -or $release.prerelease) {
        if ($Force) { Write-Host 'Uygun kararlı güncelleme bulunamadı.' }
        return $Active
    }
    $version = Read-ReleaseVersion $release.tag_name
    if ($version -le $current) {
        if ($Force) { Write-Host "Başlatıcınız güncel. Sürüm: $current" -ForegroundColor Green }
        return $Active
    }
    $assetName = "Discord-Proton-Launcher-$($meta.Edition).zip"
    $assets = @($release.assets | Where-Object { $_.name -ceq $assetName })
    if ($assets.Count -ne 1) { throw 'Bu sürüm için güncelleme paketi bulunamadı.' }
    $asset = $assets[0]
    $expectedUrl = 'https://github.com/Fen1kks/Discord-Proton-Launcher/releases/download/' + $release.tag_name + '/' + $assetName
    if ($asset.browser_download_url -cne $expectedUrl -or $asset.size -gt 10MB -or $asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$') { throw 'Geçersiz indirme bilgisi.' }
    Write-Host "Başlatıcı güncelleniyor: $current -> $version"
    $id = 'release-' + [guid]::NewGuid().ToString('N')
    $archive = Join-Path $cache "$id.zip"
    $destination = Join-Path $cache $id
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $expectedUrl -Headers $headers -OutFile $archive -TimeoutSec 30
        Expand-VerifiedRelease -Archive $archive -Digest $asset.digest -Destination $destination -Edition $meta.Edition -Version $version
        Set-ActiveRelease -Root $Root -Directory $id
        if ($Force) { Write-Host "Güncelleme tamamlandı. Sürüm: $version" -ForegroundColor Green }
        return $destination
    }
    finally { if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force } }
}
