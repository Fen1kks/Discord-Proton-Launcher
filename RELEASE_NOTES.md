# Roblox support / Roblox desteği

## Türkçe

Roblox için isteğe bağlı Proton VPN yolu eşitleme desteği eklendi.

- Her iki paketteki `RobloxVpnSync.bat`, güncellemeden sonra en yeni Roblox oyuncu uygulamasını bulur ve Proton VPN kaydını ekler veya günceller.
- Discord başlatıcıları, Proton listesinde zaten bulunan Roblox kaydını da günceller. Roblox kullanmayanların hiçbir değişiklik yapması gerekmez.
- En yeni sürüm, klasör adı yerine uygulamanın sayısal sürüm bilgisiyle seçilir.
- Roblox eşitlemesi Discord gerektirmez; Roblox'u açmaz ve arka planda güncelleme takibi yapmaz. Roblox güncellemesi tamamlandıktan sonra oyuna girmeden önce çalıştırın.
- Salt okunur kontrol: `RobloxVpnSync.bat -WhatIf`.

## English

Added optional Proton VPN path synchronization for Roblox.

- Both editions include `RobloxVpnSync.bat`, which finds the latest Roblox player after an update and adds or updates its Proton VPN entry.
- Discord launchers also refresh Roblox entries already present in Proton. Users who do not use Roblox do not need to change anything.
- The latest version is selected using numeric executable version metadata rather than the folder name.
- Roblox synchronization does not require Discord, launch Roblox, or monitor updates in the background. Run it after Roblox finishes updating, before joining a game.
- Read-only check: `RobloxVpnSync.bat -WhatIf`.
