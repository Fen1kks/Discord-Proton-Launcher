# Git preflight fix / Git ön kontrol düzeltmesi

## Türkçe

Developer-Equicord başlatıcısı artık yarım kalmış Git işlemlerini Discord'u kapatmadan önce tespit eder.

- Devam eden rebase, merge, cherry-pick ve revert işlemleri ile çözülmemiş dosya çakışmaları ön kontrolde bildirilir.
- Böyle bir durumda yeni bir rebase başlatılmaz; mevcut Git işlemi ve açık Discord oturumu korunur. Kullanıcıya işlemi tamamlayıp veya iptal edip yeniden denemesi gerektiği açıklanır.
- `EquicordLauncher.bat -CheckOnly` aynı Git kontrollerini de çalıştırır.
- Git ön kontrolü için otomatik testler eklendi. Her iki pakette Discord sürüm seçimi, Proton kaydı güncelleme, tekrar eşitleme, ilk kayıt ve yedekli atomik kaydetme testleri eklendi.
- Standard paketin çalışma davranışı değişmedi. Discord ve Roblox testleri Windows PowerShell 5.1 ile her iki paket için geçti.

Bu sürüm yarım kalmış Git işlemlerini otomatik tamamlamaz, iptal etmez veya Git işlem dosyalarını silmez.

## English

The Developer-Equicord launcher now detects unfinished Git operations before closing Discord.

- Preflight checks report pending rebases, merges, cherry-picks, reverts, and unresolved file conflicts.
- When a pending operation is found, no new rebase starts. The existing Git operation and running Discord session are preserved, with guidance to finish or abort the operation before retrying.
- `EquicordLauncher.bat -CheckOnly` now runs the same Git checks.
- Added automated Git preflight tests, plus Discord version selection, Proton entry migration, repeated synchronization, first-time entry, and atomic save with backup tests for both editions.
- Standard runtime behavior is unchanged. Discord and Roblox tests passed for both editions on Windows PowerShell 5.1.

This release does not automatically continue or abort unfinished Git operations, or delete Git operation files.
