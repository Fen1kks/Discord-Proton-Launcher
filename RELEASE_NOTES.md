# v1.2.0 - Proton tunnel rebuild and safer Equicord sync

## Türkçe

- Split tunneling uygulama listesi değişince Proton tüneli otomatik yeniden kurulur; Discord yeni tünel bağlanmadan açılmaz. Otomatik kapatma başarısız olursa manuel yeniden bağlanma istemi gösterilir.
- Discord güncellemesinden sonra yeni Discord.exe'nin VPN dışında kalması düzeltildi. Başlatıcı Discord güncelleyici logunu kontrol eder ve updates.discord.com'a ulaşılamıyorsa yeniden bağlanma yönergesiyle hata verir.
- Eksik Discord kurulumları algılanır. VBS ile sessiz başlatmada oluşan hatalar artık iletişim kutusu ve log dosyasıyla bildirilir.
- Developer-Equicord: upstream değişiklikleri rebase yerine `--autostash` ile merge edilir; yayımlanmış fork geçmişi yeniden yazılmaz. Çakışma veya fetch hatasında Discord önceki derlemeyle uyarıyla açılır.
- Developer-Equicord: `src/userplugins` değişiklikleri artık yeniden derlemeyi tetikler.
- Yalnızca son beş Proton ayar yedeği ile mevcut ve önceki güncelleme sürümü saklanır.
- 1.1.0 kullanıcıları bu sürümü otomatik alır. Yeni hata iletişim kutusu kök BAT/VBS dosyalarına bağlı olduğundan yalnızca yeni ZIP'ten kurulumlarda görünür.

## English

- Changing the split tunneling app list now rebuilds the Proton tunnel automatically; Discord waits until the new tunnel is connected. A manual reconnect prompt remains the fallback.
- Fixed the updated Discord.exe bypassing the VPN after a Discord update. The launcher checks the Discord updater log and fails with reconnect guidance when updates.discord.com is unreachable.
- Incomplete Discord installations are detected. Silent VBS launches now report failures with a dialog and a log file.
- Developer-Equicord: upstream changes are merged with `--autostash` instead of rebased, so published fork history is not rewritten. On a conflict or fetch failure Discord starts with the previous build and a warning.
- Developer-Equicord: edits in `src/userplugins` now trigger a rebuild.
- Only the five newest Proton settings backups and the current plus previous update release are kept.
- 1.1.0 users receive this release automatically. The new failure dialog depends on the root BAT/VBS files, so it only appears for installs from the new ZIP.
