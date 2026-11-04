# v1.2.2 - Wait for Proton VPN before starting Discord

## Türkçe

- Discord artık Proton VPN'in bağlandığı görülmeden başlatılmaz. Başlatıcı en fazla 180 saniye bekler; VPN'in geç bağlanması artık "Discord güncelleme sunucusuna ulaşamadı" hatasına yol açmaz.
- VPN bu sürede bağlanmazsa Discord açılmaz ve hata penceresi gösterilir. Bu nedenle Discord artık VPN bağlantısı olmadan bu başlatıcıyla açılamaz.
- Proton VPN hâlâ bağlanırken gereksiz "bağlantıyı kesip yeniden bağlanın" penceresi artık çıkmaz.
- Roblox VPN eşitlemesi ve `-CheckOnly` eskisi gibi beklemeden çalışır.
- 1.2.1 kullanıcıları bu sürümü otomatik alır.

## English

- Discord no longer starts until Proton VPN is seen connected. The launcher waits up to 180 seconds, so a slow VPN connection no longer causes the "could not reach the Discord update server" error.
- If the VPN does not connect in that time, Discord stays closed and an error dialog is shown. As a result, this launcher can no longer open Discord without a VPN connection.
- The unnecessary "disconnect and reconnect" dialog no longer appears while Proton VPN is still connecting.
- Roblox VPN sync and `-CheckOnly` still run without waiting.
- 1.2.1 users receive this release automatically.
