# Launcher updates / Başlatıcı güncellemeleri

## Türkçe

1.1.0 ile BAT/VBS kısayollarından açılan Standard, Developer-Equicord ve
Roblox başlatıcıları günde en fazla bir kez GitHub'daki son kararlı sürümü kontrol eder.
İnternet hatasında mevcut sürüm açılır. Kontrol için 5, indirme için 30 saniye
zaman aşımı vardır; başarısız kontrol de 24 saat bekler. Yeni sürüm yoksa
indirme yapılmaz. `-CheckOnly` ve `-WhatIf` güncelleme kontrolünü atlar.
Doğrudan PS1 çalıştırmak güncelleyiciyi atlar. Git kaynak kopyalarında da
otomatik güncelleme atlanır; yayınlanan ZIP paketlerini kullanın.

Paket GitHub'ın SHA-256 bilgisiyle doğrulanır; paket türü, sürüm, protokol,
dosya listesi ve PowerShell sözdizimi kontrol edilir. SHA-256 bir kod imzası
değildir: güven kaynağı HTTPS üzerinden bu GitHub deposunun release hesabıdır.
Taslaklar, ön sürümler ve eski sürümler kurulmaz.

Yeni dosyalar `.updates/release-...` altına alınır. Tüm kontroller bitince
`current.json` atomik olarak değiştirilir. İndirme/kontrol yarıda kesilirse
aktif sürüm değişmez. Eski sürümler ve ilk kurulum dosyaları korunur.
Bu kontrol uygulamanın her davranışını doğrulamaz; çalışma zamanı hatalarında
otomatik sürüm geri alma yapılmaz.

`launcher-config.json`, `launcher-state.json` ve `logs` ilk kurulum klasöründe
kalmaya devam eder. Proton ayarları ve Equicord kaynak deposu güncelleme paketinin
parçası değildir. Kullanıcılar mevcut kısayollarını kullanır.

### Yeni sürüm yayınlama

1. Her iki `release.json` dosyasının `Version` alanını aynı `X.Y.Z` sürümüne alın.
2. Ortak `LauncherUpdate.ps1` ve `LauncherBootstrap.ps1` dosyalarını iki pakette
   aynı tutun. Protokol 1 kök BAT/VBS/Bootstrap girişlerini sabit kabul eder;
   yeni sürümler bu girişle uyumlu kalmalıdır. Güncel iş mantığı ve güncelleyici
   aktif sürüm klasöründen yüklenir. Kök girişi değiştiren bir protokol geçişi
   ayrı bir geçiş planı gerektirir.
3. Testleri çalıştırın, `RELEASE_NOTES.md` dosyasını güncelleyin ve değişiklikleri commit edin.
4. `vX.Y.Z` etiketini GitHub'a gönderin. Release workflow testlerden sonra iki
   ZIP ve SHA-256 dosyalarıyla **taslak** sürüm oluşturur.
5. Taslaktaki paketleri kontrol edip GitHub'da kararlı sürüm olarak yayınlayın.
   Ancak bu adımdan sonra kullanıcılar güncellemeyi alır. Otomatik güncelleme
   için kaynak kod ZIP'ini değil, workflow'un ürettiği paketleri yayınlayın.

Yerel paketleme: `powershell.exe -NoProfile -File scripts/Build-Release.ps1 -Version v1.1.0`.
Dosyalar `dist` klasörüne yazılır; kişisel ayar/log dosyaları dahil edilmez.
Mevcut eski kullanıcıların 1.1.0 paketini bir kez elle indirmesi gerekir.
Bu depodaki değişiklikler tek başına kullanıcılara yayın yapmaz.

## English

Starting with 1.1.0, the BAT/VBS launchers check GitHub's latest stable release
at most once per day, including failed attempts. Metadata/download timeouts
are 5/30 seconds. Offline and invalid updates keep the current release.
`-CheckOnly`, `-WhatIf`, direct PS1 execution and Git source checkouts skip updates.

Packages are checked against GitHub's SHA-256 digest, the expected edition,
version, protocol, exact file list and PowerShell syntax before activation.
The digest is an integrity check, not a code signature; trust rests on the
repository's GitHub release account over HTTPS. Drafts, prereleases and
downgrades are excluded.

Validated versions live in `.updates/release-...`; an atomic `current.json`
switch activates them. Interrupted downloads leave the active version intact.
Previous versions remain on disk. Runtime failures do not automatically roll
back. Configuration, state and logs remain in the original installation folder.

To release, update both `release.json` versions and `RELEASE_NOTES.md`, keep
shared bootstrap/updater files identical, run tests, commit and push a matching
`vX.Y.Z` tag. The workflow creates a draft with both edition ZIPs and checksums.
Review and publish it as a stable release to enable delivery. Source ZIPs are
not update packages. Protocol 1 requires compatibility with the original root
BAT/VBS/bootstrap entry points; changing that contract needs a migration plan.
Existing users must manually install the updater-enabled package once.

API reference: [GitHub Releases](https://docs.github.com/en/rest/releases/releases).

## Manuel kontrol / Manual check

Her iki paketteki GuncellemeleriDenetle.bat dosyası günlük sınırı atlar ve varsa güncellemeyi kurar. Sonucu gösterir; Discord, Roblox veya Proton işlemlerini başlatmaz. Hatalar başarısız çıkış koduyla bildirilir. Kaynak kod kopyalarında güncelleme yapılmaz.

Both editions include GuncellemeleriDenetle.bat for an immediate update check and installation, bypassing the daily interval. It displays the result without launching Discord, Roblox or Proton operations. Failures return a nonzero exit code. Source checkouts remain excluded.
