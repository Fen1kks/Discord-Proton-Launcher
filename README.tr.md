# Discord Proton Launcher

Discord yeni bir sürümlü `app-*` klasörüne taşındığında Proton VPN split tunneling
uygulama yolunu otomatik eşleyen, resmi olmayan bir Windows başlatıcısıdır.
Her iki paket ayrıca Roblox güncellemelerinden sonra isteğe bağlı VPN yolu
eşitleme desteği sunar.

Bu proje Proton AG, Discord, Roblox Corporation veya Equicord ile bağlantılı/resmi değildir. Proton
VPN'in dahili ayar dosyasını düzenlediği için gelecekteki Proton sürümlerinde
uyumluluk güncellemesi gerekebilir. Her ayar değişikliğinden önce tarihli yedek
alır.

## Hangi edition'ı kullanmalıyım?

### Standard — çoğu kullanıcı için önerilen

[`Standard`](./Standard) edition'ı seçin:

- Normal Discord kullanıyorsanız veya
- Equicord kullanıyor fakat kaynak kodunu değiştirmiyor/build etmiyorsanız.

Equicord normal Equicord güncellemelerini zaten kendisi yönetir. Standard edition
Discord'un sürümlü EXE yolunu ve Proton VPN kaydını yönetir; isteğe bağlı Roblox
desteğini de içerir.

### Developer-Equicord — yalnızca özel fork geliştiricileri

[`Developer-Equicord`](./Developer-Equicord) edition'ı yalnızca şu durumlarda
seçin:

- Equicord kaynak kodunu değiştiriyorsanız
- Kendi Equicord fork'unuzu tutuyorsanız
- Equicord'u kaynaktan build ve inject ediyorsanız
- Kişisel commit'lerinizi upstream Equicord değişiklikleri üzerine taşıyorsanız

Bu edition yapılandırılabilir upstream fetch/rebase, dependency kurulumu, build,
inject onarımı ve Proton VPN yol senkronizasyonunu birlikte yapar.

> Emin değilseniz Standard edition'ı kullanın.

## İsteğe bağlı Roblox desteği

| Kullanım | Çalıştırılacak dosya | Ne yapar? |
| --- | --- | --- |
| Discord / normal Equicord | `Standard/DiscordLauncher.bat` | Discord'u açar ve VPN yolunu eşitler; Proton'da zaten kayıtlıysa Roblox yolunu da günceller. |
| Özel Equicord fork'u | `Developer-Equicord/EquicordLauncher.bat` | Geliştirici işlemlerini ve aynı VPN yolu eşitlemesini yapar. |
| Yalnızca Roblox | `Standard/RobloxVpnSync.bat` | Roblox VPN kaydını ekler veya günceller; Discord gerektirmez ve açmaz. |

**Roblox kullanmıyorsanız hiçbir değişiklik yapmanız gerekmiyor.** Mevcut Discord
başlatıcınızı kullanmaya devam edin. Roblox kurulu değilse bu adım atlanır;
kurulu olsa bile Proton listesinde yoksa Discord başlatıcısı onu otomatik eklemez.

Roblox güncellemesi bittikten sonra oyuna girmeden önce `RobloxVpnSync.bat`
dosyasını çalıştırın. Bu dosya her iki pakette de bulunur; aynı klasördeki
`vpn_sync.ps1` ile birlikte tutulmalıdır. Tek başına Roblox eşitlemesi Discord,
Git, Node.js veya pnpm gerektirmez.

Proton VPN'de split tunneling etkin ve yalnızca listedeki uygulamaların VPN
kullanacağı mod seçili olmalıdır. Salt okunur kontrol için
`RobloxVpnSync.bat -WhatIf` kullanın. Betik Roblox'u açmaz ve arka planda güncelleme
izlemez. Yol değiştiğinde ayarlar yedeklenir; Proton açıksa yeniden başlatılır.

Yeni sürüm, `%LocalAppData%\Roblox\Versions` altındaki `RobloxPlayerBeta.exe`
dosyalarının sayısal sürüm bilgisi karşılaştırılarak seçilir. Klasör adları sürüm
sırasını belirtmez. Sürümler eşitse klasörün son değiştirilme tarihi kullanılır;
oyuncu dosyası bulunmayan klasörler atlanır.

## Gizlilik

Proton VPN `UserSettings*.json` dosyalarını veya yedeklerini GitHub'a yüklemeyin.
Bu dosyalar hesap/bağlantı bilgileri içerebilir. Loglar yerel Windows kullanıcı
adı ve klasör yollarını gösterebilir, bu yüzden paylaşmadan önce bunları gizleyin.
