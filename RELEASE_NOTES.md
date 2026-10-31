# v1.2.1 - Fast-forward-only Equicord sync

## Türkçe

- Developer-Equicord: Equicord deposu artık upstream'e yalnızca ileri sarılır (`--ff-only`), merge commit oluşturulmaz. Kendi eklentileriniz git tarafından yok sayılan `src/userplugins` klasöründe kaldığı için etkilenmez.
- Depoda yerel commit varsa ileri sarma yapılmaz; Discord önceki derlemeyle uyarıyla açılır ve orijinale dönmek için `git reset --hard <upstream>` önerilir.
- Standard sürümünde değişiklik yok; sürüm numarası iki sürümde ortak olduğu için 1.2.1'e yükseltildi.
- 1.2.0 kullanıcıları bu sürümü otomatik alır.

## English

- Developer-Equicord: the Equicord repository is now only fast-forwarded to upstream (`--ff-only`); no merge commits are created. Your own plugins live in the git-ignored `src/userplugins` folder and are unaffected.
- If the repository has local commits, the fast-forward is skipped; Discord starts with the previous build and a warning suggesting `git reset --hard <upstream>` to return to upstream.
- No changes in the Standard edition; its version moves to 1.2.1 because both editions share one version number.
- 1.2.0 users receive this release automatically.
