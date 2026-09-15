# v1.1.0 - Automatic launcher updates

## Türkçe

- Standard, Developer-Equicord ve Roblox BAT/VBS girişlerine günlük otomatik güncelleme eklendi.
- `GuncellemeleriDenetle.bat` ile beklemeden manuel güncelleme yapılabilir; Discord açılmaz.
- Türkçe kullanım metinleri ve güncelleme mesajları düzeltildi; Windows PowerShell için Türkçe karakter kodlaması korundu.
- Kararlı GitHub paketleri SHA-256, sürüm, paket türü ve dosya kontrollerinden sonra ayrı klasörde etkinleştirilir.
- Kişisel ayarlar, loglar ve kısayollar korunur. İnternet veya paket doğrulama hatasında mevcut sürüm kullanılır.
- -CheckOnly ve -WhatIf güncelleme yapmaz. Git kaynak kopyaları otomatik güncellenmez.
- Sürüm etiketiyle test edilen paketleri içeren taslak GitHub release hazırlanır; yayınlama ayrı adımdır.
- Eski kullanıcıların bu paketi bir kez elle indirmesi gerekir.

## English

- Daily automatic updates for Standard, Developer-Equicord and Roblox BAT/VBS entry points.
- Use `GuncellemeleriDenetle.bat` to check and install updates immediately without launching Discord.
- Corrected Turkish documentation and update messages, preserving encoding for Windows PowerShell.
- Stable GitHub packages are checked for SHA-256 integrity, edition, version and expected files before atomic activation in a separate directory.
- Personal settings, logs and shortcuts remain in place. Network or validation failures keep the current release.
- CheckOnly/WhatIf and Git source checkouts skip updates.
- Tagged releases build tested packages into a draft GitHub release for review and publication.
- Existing users must download this updater-enabled package once.
