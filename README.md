# Damla · 0.3

Mac çentiği için kişisel bir Liquid Glass uygulaması. macOS 26 veya üstü gerekir. Bu paket Apple Silicon için derlendi.

## Kullanım

Yanındaki **Damla.app** dosyasını aç. İstersen uygulamayı Applications klasörüne taşıyabilirsin. Menü çubuğundaki damla simgesi veya **Control + Option + Space** paneli açar. Çentiğin üzerine gelmek de paneli açar. İğne simgesi paneli açık tutar; **Esc**, çentik şeridine tıklamak veya fareyi panelden çekmek kapatır.

Varsayılan olarak çentik **tüm ekranlarda** aynı anda görünür: kapalı çentik, HUD'lar ve sürükleme tepsisi her ekranda, açık panel ise yalnızca fareyle üzerine geldiğin (veya kısayolu bastığın anda farenin bulunduğu) ekranda. Böylece ekranlar arasında zıplayan bir şey yoktur. Çentiksiz bir ekranda (harici monitör, iMac) menü çubuğunun ortasına, gerçek çentikle aynı şekilde sahte bir çentik çizer; menü çubuğunun yüksekliğini ekrandan okur. Ayarlar → Ekran ile "Fareyi izle" (tek çentik, fareyle taşınır) veya "Çentikli" (yalnızca çentikli ekran) seçilebilir; Ayarlar → "Çentiksiz ekran" ile sahte çentik yerine menü çubuğunun altında yüzen bir ada seçilebilir. Ekran bağlama/çıkarma ve uykudan uyanma sonrası pencereler yeniden kurulur.

- **Özet:** Sistemin "Şu An Çalıyor" verisi: Apple Music, Spotify, Podcasts ve tarayıcıdaki YouTube / YouTube Music / Spotify Web dahil o an çalan ne varsa parça, sanatçı, kapak, ilerleme ve oynatma düğmeleri; kaynağın uygulama simgesine tıklamak o uygulamayı öne getirir. Bağlantı kurmak veya izin vermek gerekmez. Pil, ses ve odak sayacı da burada.
- **Ses / parlaklık:** Seviye değişince çentik yana doğru genişler ve tek satırda simge, ad, renkli çubuk ve değer gösterir (ses beyaz, parlaklık kehribar, şarj yeşil). Ayarlar → "Sistem ses/parlaklık baloncuğunu gizle" açıkken ses, sessiz ve parlaklık tuşlarını Damla sistemden önce yakalayıp kendisi uygular; macOS kendi göstergesini çizmez. Bu, Erişilebilirlik izni ister (Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik). ⇧ ile ses geri bildirimi, ⌥⇧ ile ince adım macOS'taki gibi çalışır. Parlaklık yalnızca yerleşik ekranda uygulanır; harici ekran parlaklık tuşları sisteme bırakılır.
- **Dosyalar:** Herhangi bir yerde dosya sürüklemeye başladığın anda çentik "Buraya bırak" sepetine genişler (fare sürükleme olayları ve sürükleme panosu izlenir, izin gerekmez); üzerine gelince vurgulanır, bırakınca raf açılır. Sepet çentiğin altına 104 pt iner, dosyayı kesikli alana bırak; ekranın üst kenarına dayanmak gerekmez (orada macOS Mission Control açar). Dosya/klasörleri çentiğe bırak veya + düğmesini kullan. Raf yatay kutucuklardan oluşur ve kutucuklar Quick Look küçük resimleri gösterir (görsel, PDF, video, metin; üretilemezse dosya simgesi). Tek tık seçer, **Boşluk** veya göz düğmesi sistem Quick Look panelinde önizler (ok tuşlarıyla raf içinde gezilir, Esc kapatır), çift tık açar, × kaldırır, sağ tık Finder'da gösterir. Sürüklerken tepside sürüklenen dosyanın küçük resmi ve adı (birden fazlaysa sayısı) görünür. Raftan başka uygulamaya sürükle. Raftan kaldırmak orijinal dosyayı silmez. Damla dosyayı taşımaz veya kopyalamaz; kalıcı bir referans tutar.
- **Pano:** Varsayılan olarak kapalıdır. Açıldıktan sonra kopyalanan metin/görselleri yatay kartlar halinde kaydeder; bağlantı, renk (#hex önizlemeli), metin ve görsel türlerini ayırt eder. Arama, sabitleme, yeniden kopyalama ve tek tek kaldırma vardır. Bir karta tıklayıp hedef uygulamada ⌘V ile yapıştır. En fazla 60 öğe / toplam 24 MB; metin başına 200 KB, görsel başına 4 MB. Sınır aşılınca sabitlenenler öncelikli tutulur. Görsellerde OCR araması yoktur.
- **Odak:** 25/45/50 dakikalık çalışma, 5 dakikalık mola, duraklatma/devam ve sıfırlama. Çalışırken halka ve düğme nane yeşiline döner; kapalı çentikte kalan süre görünür. Bitişte yerel ses ve çentik bildirimi. Uyku sonrası gerçek saat üzerinden devam eder; uygulama kapalıyken bildirim vermez.
- **Ayarlar:** Tek ekran, kaydırmasız: dört anahtar iki sütunlu bir ızgarada sağa yaslı (üzerine gelince açılma, girişte başlatma, pano geçmişi, sistem HUD'unu gizleme), altında ayraçlı satırlar halinde ekran seçimi (Tümü / Fareyi izle / Çentikli), çentiksiz ekran biçimi (Menü çubuğu / Ada) ve Temizlik modu düğmesi; en altta sürüm/kısayol ve Çıkış. Erişilebilirlik izni bekleniyorsa sürüm yazısının yerinde Sistem Ayarları'na giden uyarı görünür.

## Paylaşım, agent durumu ve Temizlik modu

- **Raftan paylaşım:** Dosyaya sağ tık → **Paylaş…** veya rafın üstündeki paylaşım düğmesi. Düğme seçili dosyayı, seçim yoksa ilk dosyayı macOS paylaşım seçicisine verir. AirDrop, Mail ve diğer seçenekler sistemde kullanılabilen servislere göre gelir. Alıcı ve gönderim sistem arayüzünde seçilir. Paylaşım boyunca çentik sistem pencerelerinin altında kalır; iptal veya tamamlanma sonrası eski seviyesine döner.
- **Agent’lar:** Claude Code ve Codex'in yaşam döngüsü hook'larından gelen durum. Üstte özet ("2 çalışıyor · 1 onay bekliyor · bugün 14 tur") ve onay beklerken ses anahtarı (varsayılan kapalı, "Tink"). Her satır: maskot (kurulu uygulamanın simgesi; sol altta oturumu barındıran uygulama: Terminal, VS Code, Claude, ChatGPT…), proje adı, ne yaptığı ("Komut çalıştırıyor · 4 dk · 31 çağrı"; beklerken "Bash için onay bekliyor · 3 dk 12 sn" kehribar), sağda son güncelleme. Satıra tıklamak barındıran uygulamayı öne getirir; üzerine gelince × listeden kaldırır. Çalışan ve bekleyenlerle son 15 dakikada bitenler üstte, gerisi katlanmış "Geçmiş" altında. Kapalı çentikte agent'ın **maskotu** görünür (Damla hiçbir marka görseli paketlemez): çalışırken nefes alır ve nane halkayla parlar, sağda üç nokta; onay beklerken kehribar halka daha hızlı nefes alır, el rozeti; HUD kapandığı anda maskot bir kez sıçrar. Maskota tıklamak barındıran uygulamaya gider. Ada dinamiktir: tek etkinlikte simge solda, durum sağda; video/müzik ile agent aynı anda çalışıyorsa yanlar genişler ve her biri kendi yarısını alır (solda kapak + ekolayzer, sağda üç nokta + maskot). Odak sayacı da bir etkinliktir; üçü birden varsa sayaç ve agent gösterilir. Aşama değişince HUD'da simge ve kısa durum yazısı çıkar. `Stop` yanıtın bittiğini gösterir; işin başarılı olduğu anlamına gelmez. 30 dakika sinyal gelmeyen etkin oturum "Durum güncel değil" olur.
- **Temizlik modu:** Ayarlar veya menü çubuğu → **Temizlik modu · 60 sn**. Erişilebilirlik izni varsa tüm klavyelerin yazı, değiştirici ve medya tuşları geçici tutulur. Fare/trackpad çalışır; güç/Touch ID tuşu kapsam dışıdır. Süre sonunda, **Kilidi aç** düğmesiyle veya **Esc’yi 2 saniye basılı tutarak** açılır. Uyku, kullanıcı oturumunun kilitlenmesi, event tap'in devre dışı kalması veya uygulamanın kapanması kilidi kaldırır. Kilit durumu kaydedilmez; uygulama açıldığında klavye kilitlenmez. Tuş içerikleri kaydedilmez.

Agent bağlantısı için uygulamayı derledikten sonra:

```sh
python3 scripts/install-agent-hooks.py --binary "$(cd .. && pwd)/Damla.app/Contents/MacOS/Damla"
# Yukarıdaki komut yalnızca planı gösterir. Kurmak için:
python3 scripts/install-agent-hooks.py --binary "$(cd .. && pwd)/Damla.app/Contents/MacOS/Damla" --apply
```

Kurucu mevcut `~/.claude/settings.json` ve `~/.codex/hooks.json` içeriğini koruyarak yalnızca Damla'nın hook kayıtlarını ekler; değiştirdiği dosyaların tarihli yedeğini yanında bırakır. Codex için `CODEX_HOME` farklıysa kurulum yolu ayrıca uyarlanmalıdır. İzin/güven ayarlarını değiştirmez ve hook'ları otomatik güvenilir yapmaz. **Codex'te `/hooks` ile yeni Damla hook'larını inceleyip güvenilir olarak onaylamak gerekir.** Mevcut oturumlar ayarları yeniden yükleyene kadar olay üretmeyebilir; yeni oturumda kontrol edilir. Hook'lar kapatılmışsa kurucu bunu açmaz. Uygulama taşınırsa kurucu yeni `--binary` yolu ile yeniden çalıştırılmalıdır.

Hook komutu `Damla --agent-event claude|codex` yalnızca standart girdiden gelen olayın durum metadatasını `~/Library/Application Support/Damla/agents/` altında, kullanıcıya özel izinlerle tutar: aşama, çalışan aracın adı, onay istenen aracın adı, tur başlangıcı, araç çağrısı sayısı, bekleme başlangıcı ve hook sürecinin üst süreç zincirinden bulunan barındırıcı uygulamanın paket kimliği (Terminal, Claude, VS Code…). `Stop` olayları `stats.json` içinde günlük tur sayacını artırır. Kurucu Claude için `PermissionDenied` olayını da kaydeder; önceki kurulumdan sonra `--apply` ile yeniden çalıştırmak gerekir. Mesaj, araç girdisi/çıktısı veya konuşma dosyası okunmaz/kaydedilmez. Komut sessizdir; hiçbir onay isteğini kabul/ret etmez. Arayüz son 24 saatin en fazla 64 kaydını okur, en güncel/öncelikli 12 oturumu listeler. Agent sekmesindeki uygulama düğmeleri ilgili uygulamayı açar; belirli bir göreve yönlendirme yapmaz.

Kaynaklar: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Codex hooks ve güven onayı](https://learn.chatgpt.com/docs/hooks), [Apple paylaşım seçicisi](https://developer.apple.com/documentation/appkit/nssharingservicepicker).

Doğrulama (22 Eylül 2026): Claude Code hook'ları kurulumdan sonra bu Mac'teki canlı oturumdan "Damla · Çalışıyor" olarak geldi; Codex (ChatGPT uygulaması içindeki, paket kimliği `com.openai.codex`) gerçek bir oturumdan `Stop` olayı üretti ve listede "Yanıt tamamlandı" göründü. Sentetik olaylarla çalışıyor → onay bekliyor → tamamlandı geçişleri, maskot ve HUD ekran görüntüsüyle kontrol edildi. `--self-test`, klavye zaman aşımı/Esc kurallarını ve agent olay geçişlerini izole dosyalarla kontrol eder. `PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-agent-hooks.py`, kurulumun mevcut ayarları ve hook'ları koruduğunu, yedeklemeyi ve tekrar çalıştırılabilirliğini sınar. Gerçek klavye engelleme/Erişilebilirlik, alıcıya dosya iletimi ve iki agent uygulamasından gerçek hook teslimi ayrıca canlı kontrol gerektirir.

## 0.3 görünüm ve hareket

- **Siyah → renk → berrak cam:** Yüzey çentikte tam siyah başlar; orta bölüm albüm rengini taşır, alt kavis `.clear` Liquid Glass'a açılır. Camın kendi `tint`'ine albüm rengi hafifçe (%28 × ambiyans şiddeti) eklenir; böylece açıkta kalan alt ve yan kenarlar da kapak rengini taşır. Siyah perde kontrollerin altında incelerek biter; yoğun albüm dolgusu alt kenara ulaşmadan kaybolur ve yan kenarlardan 1,5 pt içeride kalır. Cam ve içerik aynı hareketli çentik şekliyle kırpılır; kenar yansımaları ve kırılma sistemin kendi efektinden gelir. Çizilmiş beyaz kenar veya parlama katmanı yoktur. Metin her zaman beyazdır.
- **Cam görünümlü kontroller:** Oynatma, ileri/geri, sıfırla, mola, + ve kapsül seçenekler cam gibi görünür ama gerçek `glassEffect` kullanmaz: panelin camının içine ikinci bir Liquid Glass koyunca (cam içinde cam) bileşik katman panelin siyah üstünden bile arkadaki pencereyi hayalet gibi geçiriyor (macOS 27'de gözlendi). Bu yüzden kontroller katmanlı çizilir: hafif beyaz dolgu, üstte parlama kenarı, gölge; seçili durum nane dolgulu.
- **Kapak ambiyansı:** Albüm kapağının baskın rengi (`Palette.accent`, 24×24 örnekleme, en renkli ton kovası) çentiğin hemen altında belirir, içerik alanının orta bölümünde yoğunlaşır ve altına doğru söner; camın kendi hafif renk tonu alt kenarda devam eder. Böylece çentik ayrı bir siyah blok gibi görünmez. Özet'te tam, diğer sekmelerde %45 şiddetinde; Ayarlar'da yok. Rengin üstündeki koyu perde metni okunur tutar. İlerleme çubuğu ve kapalı çentikteki ekolayzer aynı renge boyanır. Parça değişince 0,9 s'de geçiş yapar; gri kapaklarda renk yoktur.
- **Çentik şekli:** Üst köşelerde ekrana eriyen içbükey "kulaklar", altta 26 pt yuvarlak köşeler. Kapalıyken şekil fiziksel çentiğe yapışır; müzik veya sayaç varken iki yana açılıp kapak/ekolayzer ve süre gösterir. Boştayken görünmez.
- **Hareket:** Pencere artık çerçeve animasyonu yapmıyor; sabit boyutlu saydam bir pencere içinde şeklin kendisi SwiftUI yayıyla büyüyor (açılış 0.5 s, hafif sıçrama; kapanış 0.36 s). İçerik açılışta bulanıklıktan netleşerek geliyor; kapanışta medya bilgileri sabit yerleşimlerini koruyup 0,12 s içinde sönüyor, panel daralırken geride kalmıyor. Sekme kapsülü panelle birlikte iniyor. Sistem "hareketi azalt" ayarı açıkken kısa geçişler kullanılır.
- **Sekmeler:** Beş sekme, iğne ve ayarlar panelin altında ayrı bir cam kapsülde. Rafta öğe varsa nokta rozeti görünür.
- **Özet girişi:** Panel açılırken kapak sol alttan büyüyerek, başlık sağdan kayarak, kontroller alttan gelerek kademeli belirir (40 ms başlangıç, 50 ms aralık). "Hareketi azalt" açıkken atlanır.
- **Pencere katmanı:** Çentikli ekranda macOS menü çubuğu malzemesini ekran koruyucu seviyesinin altındaki her pencerenin üstüne çiziyor (macOS 27'de ölçüldü: 999 boyanıyor, 1000 boyanmıyor). Panel bu yüzden `.screenSaver` seviyesinde; dosya seçici açıkken geçici olarak iner. Bağlam menüleri bu seviyede de panelin üstünde açılıyor. Bu seviye sürükleme katmanının (`kCGDraggingWindowLevel` = 500) üstünde kaldığı için AppKit paneli bırakma hedefi olarak görmez; dosya sürüklemesi algılandığı sürece panel 499'a iner (o anda menü çubuğu tonu hafifçe görünür) ve sürükleme bitince geri çıkar.

## Veriler ve bağlantılar

Hesap veya sunucu yok. Dosya referansları, pano içeriği ve sayaç durumu `~/Library/Application Support/Damla/` içinde tutulur; tercihler uygulamanın UserDefaults alanındadır. Pano kaydını kapatmak mevcut geçmişi silmez. Parola yöneticilerinin gizli/geçici olarak işaretlediği içerikler kaydedilmez.

Müzik bilgisi ve kapak macOS'un kendi "Şu An Çalıyor" kaydından yerel olarak okunur; ağa çıkılmaz. Köprü çalışmazsa (adaptör kendi testinde başarısız olursa) eski Apple Events yolu devreye girer: Apple Music / Spotify seçilir, Otomasyon izni istenir, Spotify kapağı HTTPS'ten indirilir.

## Teknik kapsam

- SwiftUI + AppKit, **glassEffect(.clear)** ile yerel Liquid Glass. macOS 26+.
- `Layout.swift` tek gerçek kaynak: şekil boyutları, pencere boyutu ve fare takibi için görünür dikdörtgen buradan hesaplanır.
- 0.4.3: Saydam pencerenin görünür panel dışında kalan kısmı fare olaylarını almaz. Panel kapanınca alttaki Safari ve diğer uygulamalar yeniden tıklama hedefi olur; bu yönlendirme iki ekranda canlı kontrol edildi. Fare hareketi ve panel/HUD/tepsi durumu değişiklikleri geçişi günceller. `--self-test` görünür alan kontrolleri dahil 63/63 geçti.
- `PanelManager` ekran başına bir `PanelController` (pencere + `ScreenMetrics`) tutar; ekran değişince yeniden kurar. Genel durum `AppState`'te, hangi ekranın paneli açtığı `activeScreenID`'de; HUD ve tepsi her pencerede çizilir. Kısayol, sürükleme algılama ve Quick Look sahipliği tek yerde (yönetici) durur.
- Pil: IOKit; ses: CoreAudio dinleyicileri (ses/sessiz değişimi anında gelir), parlaklık ve pil 1 s'de bir yoklanır. Ekran kaydı istemez. Erişilebilirlik izni yalnızca "sistem baloncuğunu gizle" seçeneği için gerekir (`CGEvent` tap ile NX_SYSDEFINED medya tuşları yutulur, ses CoreAudio ile, parlaklık `DisplayServicesSetBrightness` ile uygulanır).
- Enerji: kapalı çentik saat tıkını yayınlamaz, cam katmanı yalnızca panel açıkken çizilir, müzik yenilemesi boşta 6 s'ye düşer. Boşta CPU yaklaşık %1 (önceki sürümde %2,5).
- Parlaklık okuma, desteklenen yerleşik ekranlarda isteğe bağlı `DisplayServicesGetBrightness` sembolünü kullanır. Harici monitör parlaklığı hedeflenmez.
- Müzik: `Vendor/MediaRemoteAdapter` (ungive/mediaremote-adapter, BSD-3) uygulamaya paketlenir; `NowPlayingBridge`, `/usr/bin/perl` içinde çalışan adaptörün `stream` çıktısını (JSON satırları, fark tabanlı) okur, `send`/`seek` ile kumanda eder. Apple 15.4'ten beri MediaRemote'u üçüncü taraf süreçlere kapattığı için yalnızca Apple imzalı perl üzerinden çalışır; macOS 27.0 (26A428) üzerinde doğrulandı. Başlangıçta `test` komutu koşulur, 0 dönmezse Apple Events yoluna düşülür. Konum, `elapsedTime` + `timestamp` üzerinden yerel olarak ilerletilir.
- İmza: `build.sh`, Keychain'deki ilk "Apple Development" sertifikasıyla imzalar (`DAMLA_SIGN_IDENTITY` ile değiştirilebilir, yoksa ad-hoc). Tasarlanmış gereksinim takım sertifikasına bağlı olduğu için Erişilebilirlik/Otomasyon izinleri yeniden derlemede korunur. App Store/Developer ID dağıtımı ve noter onayı yapılmadı.

## Güncellemeler (Sparkle)

Damla, [Sparkle](https://sparkle-project.org) ile günde bir kez `appcast.xml` dosyasına (bu depoda, `raw.githubusercontent.com` üzerinden) bakar; yeni sürüm varsa çentikte "Damla X hazır" bildirimi çıkar, tıklayınca Sparkle'ın kendi penceresi indirir ve yeniden başlatır. Ayarlar → Güncellemeler anahtarı otomatik denetimi kapatır; "Şimdi denetle" ve menü çubuğundaki "Güncellemeleri denetle…" elle bakar. Sunucu yoktur: dmg'ler GitHub Release'te, appcast depoda durur; indirilen dosya hem Apple noter onayı hem de `Info.plist`'teki EdDSA açık anahtarıyla doğrulanır (gizli anahtar yalnızca yayıncının Keychain'inde). Damla hiçbir veri göndermez; Sparkle'ın sistem profili paylaşımı kapalıdır.

Doğrulama (22 Eylül 2026): 0.4.0 olarak işaretli uygulama appcast'ten 0.4.1'i buldu, dmg'yi indirip açtı, Sparkle penceresi göründü; "çıkışta yükle" seçildikten sonra uygulama kapanınca paket 0.4.1'e (Developer ID imzalı, damgalı) dönüştü. Not: `/private/tmp` altına kopyalanmış bir sürüm kopyasında zamanlanmış denetim indirme başlatmadı; normal konumda (Applications veya proje klasörü) çalışıyor.

## Paylaşım (Developer ID + noter onayı)

Bir kez: Xcode → Settings → Accounts → Manage Certificates → **Developer ID Application** sertifikası; ardından `xcrun notarytool store-credentials damla-notary --team-id <TAKIM>` ile uygulamaya özel parolayı Keychain'e kaydet. Sonra her sürümde:

```sh
zsh release.sh
```

Evrensel ikili (arm64 + x86_64) derler, hardened runtime ve zaman damgasıyla Developer ID imzalar (Sparkle çerçevesi, XPC servisleri, adaptör çerçevesi ve test istemcisi dahil), `dist/Damla-<sürüm>.dmg` üretir, Apple'a noter onayına gönderip damgalar; ardından dmg'yi Keychain'deki Sparkle anahtarıyla imzalar, `appcast.xml`'e girdi ekleyip commit'ler ve `gh release create` ile GitHub Release'e yükler. Sürüm notu için `dist/notes-<sürüm>.md` varsa onu, yoksa son commit mesajını kullanır. `--no-publish` appcast ve Release adımını atlar; `--no-notarize` yalnızca imzalar. Çalışma ağacı temiz olmalı ve `Info.plist`'teki sürüm daha önce yayınlanmamış olmalı. Bir kez: Sparkle anahtarı için `.build/artifacts/sparkle/Sparkle/bin/generate_keys` (açık anahtar `SUPublicEDKey`). Alıcı `.dmg`'yi açıp uygulamayı Applications'a sürükler; Gatekeeper uyarısı çıkmaz. Erişilebilirlik ve Otomasyon izinlerini herkes kendi Mac'inde verir. Not: paketlenmiş Now Playing adaptörü arm64; Intel Mac'te Apple Events yedeği devreye girer, evrensel adaptör için `zsh Vendor/MediaRemoteAdapter/build-adapter.sh --universal`.

## Derleme

Xcode Command Line Tools / Swift 6+ kurulu bir Mac'te:

```sh
zsh build.sh
```

Kaynak dizininin yanına `Damla.app` üretir. Derleme önbelleğini başka yerde tutmak için `DAMLA_BUILD_DIR` değişkenini kullan. Harici paket bağımlılığı yoktur.

```sh
../Damla.app/Contents/MacOS/Damla --self-test
../Damla.app/Contents/MacOS/Damla --diagnose
```

`--debug` ile başlatıldığında uygulama `app.local.damla.debug` dağıtık bildirimlerini dinler (`open`, `close`, `tab-files`, `hud-volume`, `display-notch`, `files-demo`, `clip-demo` …). Ekran görüntüsü otomasyonu içindir; normal başlatmada kapalıdır.

## Doğrulama — 22 Eylül 2026

- macOS 27 / Xcode 27 üzerinde Release derlemesi ve ad-hoc imza doğrulaması. 41 otomatik kontrol (sayaç, pano kuralları, raf referansı, yerleşim boyutları, Temizlik modu zaman aşımı/Esc kuralları, agent olayları ve durum kaydı).
- Gerçek Mac'te ekran görüntüsüyle kontrol edildi: kapalı çentik (kapak + ekolayzer, sayaç), hover ile açılış kareleri, Özet (Apple Music parçası, kapak, ilerleme), Dosyalar (5 öğe), Pano (bağlantı/metin/renk kartları), Odak (çalışan sayaç), Ayarlar, ses ve parlaklık HUD'ları.
- Harici 5K monitörde (çentiksiz, ana ekran): menü çubuğundaki sahte çentik (müzik, sayaç), HUD ve açık panel; ayrıca yüzen ada biçimi kontrol edildi. "Tümü" modunda iki ekranda aynı anda kapalı çentik ve ses HUD'u, panelin yalnızca farenin olduğu ekranda açıldığı ve diğer ekranın kapalı kaldığı ekran görüntüsüyle doğrulandı. "Fareyi izle" modunda panel fareyle ekran değiştiriyor.
- Pencere seviyesi piksel ölçümüyle doğrulandı; bağlam menüsünün panelin üstünde açıldığı görüldü.
- "Şu An Çalıyor" köprüsü canlı doğrulandı: adaptör testi 0 döndü, Apple Music'ten parça/kapak/ilerleme akışla geldi, kaynak simgesi göründü; kapalı çentikte kapak. Tarayıcı kaynağı kullanıcı tarafından doğrulandı: YouTube sekmesinde başlık, kapak ve oynat/duraklat çalışıyor.
- Quick Look: raf küçük resimleri (metin ve ikon dosyaları), seçim halkası, Boşluk ile açılan sistem paneli, panel açıkken/kapanınca çentiğin yerinde kalması ve tepsi önizlemesi ekran görüntüsüyle doğrulandı.
- Sepet zinciri canlı doğrulandı: fare basılıyken sürükleme panosuna dosya adresi yazılınca panel 499 seviyesine indi ve "Buraya bırak" bandı açıldı; bırakınca 1000'e döndü. Finder'dan gerçek bırakma kullanıcı tarafından denenmeli.
- Ses ve parlaklık uygulayıcıları debug komutlarıyla doğrulandı (1/16 adım, gerçek CoreAudio ve DisplayServices üzerinden okunup geri alındı). Tuş yakalama akışı Erişilebilirlik izni gerektirdiği için kullanıcı tarafından denenmeli.
- Tam ekran: kapalı çentik menü çubuğuyla birlikte gizleniyor. Harici ekranda menü çubuğu penceresinin kaybolmasına, çentikli ekranda Space türüne (tam ekran) ve farenin üst kenara değmesine bakılıyor. İki ekranda da tam ekrana alınan bir pencereyle doğrulandı: gizlendi, fare üste gidince geri geldi, çıkınca normale döndü. HUD, sepet ve açık panel tam ekranda da görünüyor.
- Denenmeyenler: gerçek sürükle-bırak akışı, Spotify, uzun süreli enerji kullanımı.
