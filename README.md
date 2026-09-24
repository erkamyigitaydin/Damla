# Damla

Mac çentiği için Liquid Glass bir yardımcı: çalan müzik, ses, dosya rafı, pano, odak sayacı ve Claude Code / Codex ajanlarının durumu tek bir yerde, çentiğin içinde.

Çentiksiz ekranlarda (harici monitör, iMac) menü çubuğuna aynı biçimde bir çentik çizer. Hesap ya da sunucu yoktur, her şey Mac'inde kalır.

## Kurulum

**Gereken:** macOS 26 veya üstü. Apple Silicon ve Intel Mac'lerde çalışır.

Homebrew ile:

```sh
brew install --cask erkamyigitaydin/tap/damla
```

Ya da [son sürümün](https://github.com/erkamyigitaydin/Damla/releases/latest) `.dmg` dosyasını indir ve Damla'yı Applications klasörüne sürükle. Uygulama Apple tarafından noter onaylıdır, Gatekeeper uyarısı çıkmaz.

İlk açılışta kısa bir tanıtım izinleri tek tek sorar. Hepsi isteğe bağlıdır:

| İzin | Ne için |
|---|---|
| Otomasyon (Music, Spotify) | Apple Music ve Spotify'ı arka planda kumanda etmek, ses seviyelerini ayarlamak |
| Erişilebilirlik | Ses ve parlaklık tuşlarını yakalayıp macOS göstergesi yerine Damla'nınkini göstermek; Temizlik modu |
| Sistem sesi kaydı | Mikserde tek bir uygulamanın (ör. Chrome) sesini kısmak. Ses kaydedilmez, gönderilmez |

Tanıtıma sonradan menü çubuğu → **Tanıtım…** ile dönülebilir.

## Kullanım

- **Açmak:** çentiğin üzerine gel, menü çubuğundaki damla simgesine tıkla ya da **⌃⌥Space**.
- **Kapatmak:** fareyi panelden çek, çentik şeridine tıkla ya da **Esc**.
- **Açık tutmak:** paneldeki iğne düğmesi.
- **Ayarlar:** sekme kapsülündeki dişli, menü çubuğu → Ayarlar veya **⌘,**.

## Özellikler

### Müzik

- Apple Music, Spotify, Podcasts ve tarayıcıdaki YouTube / Spotify Web dahil, çalan her şey: kapak, parça, ilerleme, oynatma düğmeleri. Kurulum gerekmez.
- Aynı anda birden fazla oynatıcı varsa hepsi ayrı ayrı görünür ve aralarında geçilebilir.
- Bir video başlayınca çalan müzik duraklatılır ya da kısılır, video bitince kaldığı yerden devam eder (Ayarlar → Medya).
- Apple Music parçalarını favorilere ekleme.
- Vurgu rengi albüm kapağından gelir.

### Şarkı sözleri

Sağ alttaki düğme paneli aşağı uzatır ve sözleri Apple Music'teki gibi akıtır: söylenen satır parlak, bir satıra dokunmak şarkıyı oraya sarar. Varsayılan olarak kapalıdır.

Sözler [lrclib.net](https://lrclib.net)'ten gelir; yalnızca şarkının adı, sanatçısı, albümü ve süresi gönderilir.

### Ses

- Ses çıkışı seçici. Çıkış değişince (ör. AirPods bağlanınca) çentikte aygıt adı ve kulaklığın şarjı görünür.
- Mikser: sistem sesi, Apple Music ve Spotify'ın kendi seviyeleri ve ses çalan diğer uygulamalar ayrı ayrı.
- Çentik şeridinde dikey kaydırma sesi değiştirir, yatay kaydırma parça atlar.
- Ses ve parlaklık göstergesi çentikte gösterilir.

### Dosyalar

Bir dosyayı sürüklemeye başlayınca çentik bir bırakma sepetine dönüşür. Rafa bırakılan dosyalar küçük resimleriyle durur: **Boşluk** ile Quick Look, çift tıkla aç, başka bir uygulamaya sürükle, sağ tıkla paylaş (AirDrop, Mail…). Damla dosyaları taşımaz ya da kopyalamaz, yalnızca yerlerini hatırlar.

### Pano

Kopyalanan metin, bağlantı, renk ve görsellerin geçmişi; arama ve sabitleme ile. Varsayılan olarak kapalıdır. Parola yöneticilerinin gizli işaretlediği içerik kaydedilmez.

### Odak

25/45/50 dakikalık çalışma ve 5 dakikalık mola sayacı. Kalan süre kapalı çentikte görünür.

### Ajanlar

[Claude Code](https://code.claude.com/docs/en/hooks) ve Codex oturumlarının durumu: hangi proje çalışıyor, onay bekliyor ya da bitti. Kapalı çentikte küçük bir damla maskotu durumu gösterir, tıklamak oturumun açık olduğu uygulamaya götürür.

İsteğe bağlı olarak Claude Code'un izin soruları da çentikte açılır. Tam komutu görüp oradan **İzin ver** ya da **Reddet** diyebilirsin. Terminal öndeyse ya da süre dolarsa soru her zamanki gibi terminalde kalır.

Kurulum için ilk açılış tanıtımındaki Ajanlar adımını kullanabilir ya da betiği çalıştırabilirsin:

```sh
# Önce planı gösterir, --apply ile kurar; --approvals çentikten onayı da ekler.
python3 scripts/install-agent-hooks.py --binary /Applications/Damla.app/Contents/MacOS/Damla --apply
```

Kurucu mevcut `~/.claude/settings.json` ve `~/.codex/hooks.json` ayarlarını korur ve değiştirdiği dosyaların yedeğini bırakır. Codex'te yeni hook'ları `/hooks` ile onaylamak gerekir.

Hook'lar yalnızca durum bilgisini kaydeder: aşama, araç adı, süre. Mesajlar, komut çıktıları ve konuşmalar okunmaz.

### Ekranlar

Varsayılan olarak çentik tüm ekranlarda görünür, panel ise yalnızca farenin olduğu ekranda açılır. Ayarlar → Ekran'dan tek ekran ya da "fareyi izle" seçilebilir. Çentiksiz ekranda sahte çentik yerine menü çubuğunun altında yüzen bir ada da seçilebilir.

Tam ekran uygulamalarda kapalı çentik menü çubuğuyla birlikte gizlenir, fare üst kenara gidince geri gelir.

### Temizlik modu

Klavyeyi 60 saniye kilitler; ekranı ya da klavyeyi silerken yanlışlıkla bir şey yazılmasın diye. **Esc**'yi 2 saniye basılı tutmak ya da **Kilidi aç** düğmesi erken açar.

## Gizlilik

- Hesap, sunucu ya da analitik yok.
- Raf, pano ve sayaç verileri `~/Library/Application Support/Damla/` altında tutulur.
- Müzik bilgisi macOS'un kendi "Şu An Çalıyor" kaydından yerel olarak okunur. (Bu köprü çalışmazsa Apple Events yoluna düşülür; o yolda Spotify kapağı Spotify'ın sunucusundan indirilir.)
- Ağa çıkan iki şey var: açıksa şarkı sözleri (lrclib.net) ve güncelleme denetimi (bu depodaki `appcast.xml`). Güncelleme denetimi sistem bilgisi göndermez.

## Güncellemeler

Damla günde bir kez yeni sürüme bakar ([Sparkle](https://sparkle-project.org)). Yeni sürüm varsa çentikte bildirim çıkar. İndirilen dosya hem Apple noter onayıyla hem de Damla'nın imza anahtarıyla doğrulanır. Otomatik denetim Ayarlar → Hakkında'dan kapatılabilir.

## Geliştirme

Swift 6 ve Xcode Command Line Tools gerekir.

```sh
zsh build.sh                                  # derler, imzalar, ../Damla.app üretir ve kendi testini çalıştırır
../Damla.app/Contents/MacOS/Damla --self-test # otomatik kontroller
../Damla.app/Contents/MacOS/Damla --diagnose  # ekranlar, pil, ses, parlaklık ve ses çıkışları
```

- `--debug` ile başlatılan uygulama `app.local.damla.debug` dağıtık bildirimleriyle yönetilebilir (`open`, `close`, `tab-files`, `hud-volume`…). Ekran görüntüsü otomasyonu içindir.
- `PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-agent-hooks.py` hook kurucusunu sınar.
- **Arayüz dilleri:** Türkçe ve İngilizce. Anahtarlar Türkçe kaynak metinlerdir; İngilizcesi `Resources/en.lproj/Localizable.strings` içindedir.
- **Kod yapısı:** `Layout.swift` şekil ve pencere ölçülerinin tek kaynağıdır. `PanelController.swift` ekran başına bir pencere yönetir. `MediaSessionStore` medya kararlarını AppKit'ten bağımsız tutar.

### Yayın

`Resources/Info.plist`'te sürümü artırıp (`CFBundleShortVersionString` ve `CFBundleVersion`) commit'le, sürüm notlarını `dist/notes-<sürüm>.md` dosyasına yaz (yoksa son commit mesajı kullanılır) ve çalıştır:

```sh
zsh release.sh
```

Betik şunları yapar:

- evrensel derler ve Developer ID ile imzalar;
- dmg'yi Apple'a noter onayına gönderir;
- Sparkle anahtarıyla imzalar ve `appcast.xml`'e ekler;
- GitHub Release oluşturur ve Homebrew tarifini (`erkamyigitaydin/homebrew-tap`) günceller.

Bir kerelik hazırlık: Keychain'de "Developer ID Application" sertifikası, `xcrun notarytool store-credentials damla-notary` ve Sparkle'ın `generate_keys` anahtarı.

## Teşekkürler

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3, `Vendor/MediaRemoteAdapter`): macOS 15.4 sonrasında "Şu An Çalıyor" verisine erişim.
- [Sparkle](https://sparkle-project.org): güncellemeler.
- [LRCLIB](https://lrclib.net): şarkı sözleri.
