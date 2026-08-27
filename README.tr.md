# Discord Proton Launcher

Discord yeni bir sürümlü `app-*` klasörüne taşındığında Proton VPN split tunneling
uygulama yolunu otomatik eşleyen, resmi olmayan bir Windows başlatıcısıdır.

Bu proje Proton AG, Discord veya Equicord ile bağlantılı/resmi değildir. Proton
VPN'in dahili ayar dosyasını düzenlediği için gelecekteki Proton sürümlerinde
uyumluluk güncellemesi gerekebilir. Her ayar değişikliğinden önce tarihli yedek
alır.

## Hangi edition'ı kullanmalıyım?

### Standard — çoğu kullanıcı için önerilen

[`Standard`](./Standard) edition'ı seçin:

- Normal Discord kullanıyorsanız veya
- Equicord kullanıyor fakat kaynak kodunu değiştirmiyor/build etmiyorsanız.

Equicord normal Equicord güncellemelerini zaten kendisi yönetir. Standard edition
yalnızca Discord'un sürümlü EXE yolunu ve Proton VPN kaydını yönetir.

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

## Gizlilik

Proton VPN `UserSettings*.json` dosyalarını veya yedeklerini GitHub'a yüklemeyin.
Bu dosyalar hesap/bağlantı bilgileri içerebilir. Loglar yerel Windows kullanıcı
adı ve klasör yollarını gösterebilir, bu yüzden paylaşmadan önce bunları gizleyin.
