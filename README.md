# Damla · 0.3

Mac çentiği için kişisel bir Liquid Glass uygulaması. macOS 26 veya üstü gerekir. Bu paket Apple Silicon için derlendi.

## Kullanım

Yanındaki **Damla.app** dosyasını aç. İstersen uygulamayı Applications klasörüne taşıyabilirsin. Menü çubuğundaki damla simgesi veya **Control + Option + Space** paneli açar. Çentiğin üzerine gelmek de paneli açar. İğne simgesi paneli açık tutar; **Esc**, çentik şeridine tıklamak veya fareyi panelden çekmek kapatır.

Panel varsayılan olarak farenin bulunduğu ekranı izler. Çentiksiz bir ekranda (harici monitör, iMac) menü çubuğunun ortasına, gerçek çentikle aynı şekilde sahte bir çentik çizer; menü çubuğunun yüksekliğini ekrandan okur. Aynı panel, HUD'lar ve sekmeler orada da çalışır. Ayarlar → "Çentiksiz ekran" ile bunun yerine menü çubuğunun altında yüzen bir ada seçilebilir; Ayarlar → Ekran ile panel çentikli ekrana sabitlenebilir. Ekran bağlama/çıkarma ve uykudan uyanma sonrası konumunu yeniden hesaplar.

- **Özet:** Apple Music veya Spotify bağlantısı, parça/kapak bilgisi, oynatma düğmeleri ve sürüklenebilir ilerleme çubuğu (geçen / kalan süre); pil, ses ve odak sayacı. Müzik sağlayıcısını ilk kez seçtiğinde macOS Otomasyon izni isteyebilir. Reddedilirse Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon bölümünden yönetilebilir.
- **Ses / parlaklık:** Seviye değişince çentik yana doğru genişler ve tek satırda simge, ad, renkli çubuk ve değer gösterir (ses beyaz, parlaklık kehribar, şarj yeşil). Ayarlar → "Sistem ses/parlaklık baloncuğunu gizle" açıkken ses, sessiz ve parlaklık tuşlarını Damla sistemden önce yakalayıp kendisi uygular; macOS kendi göstergesini çizmez. Bu, Erişilebilirlik izni ister (Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik). ⇧ ile ses geri bildirimi, ⌥⇧ ile ince adım macOS'taki gibi çalışır. Parlaklık yalnızca yerleşik ekranda uygulanır; harici ekran parlaklık tuşları sisteme bırakılır.
- **Dosyalar:** Dosya/klasörleri çentiğe bırak veya + düğmesini kullan. Raf yatay kutucuklardan oluşur; çift tık açar, üzerine gelince × kaldırır, sağ tık Finder'da gösterir. Raftan başka uygulamaya sürükle. Raftan kaldırmak orijinal dosyayı silmez. Damla dosyayı taşımaz veya kopyalamaz; kalıcı bir referans tutar.
- **Pano:** Varsayılan olarak kapalıdır. Açıldıktan sonra kopyalanan metin/görselleri yatay kartlar halinde kaydeder; bağlantı, renk (#hex önizlemeli), metin ve görsel türlerini ayırt eder. Arama, sabitleme, yeniden kopyalama ve tek tek kaldırma vardır. Bir karta tıklayıp hedef uygulamada ⌘V ile yapıştır. En fazla 60 öğe / toplam 24 MB; metin başına 200 KB, görsel başına 4 MB. Sınır aşılınca sabitlenenler öncelikli tutulur. Görsellerde OCR araması yoktur.
- **Odak:** 25/45/50 dakikalık çalışma, 5 dakikalık mola, duraklatma/devam ve sıfırlama. Çalışırken halka ve düğme nane yeşiline döner; kapalı çentikte kalan süre görünür. Bitişte yerel ses ve çentik bildirimi. Uyku sonrası gerçek saat üzerinden devam eder; uygulama kapalıyken bildirim vermez.
- **Ayarlar:** Üzerine gelince açılma, pano kaydı, sistem baloncuğunu gizleme, ekran seçimi (Fareyi izle / Çentikli ekran) ve çentiksiz ekran biçimi (Menü çubuğu / Ada).

## 0.3 görünüm ve hareket

- **Siyah cam:** Yüzey çentikte tam siyah başlar, aşağıya doğru saydamlaşarak `.clear` Liquid Glass'a açılır; alt kısımda duvar kağıdı kırılarak görünür. Metin her zaman beyaz; panel sistem temasından bağımsız koyu kalır.
- **Çentik şekli:** Üst köşelerde ekrana eriyen içbükey "kulaklar", altta 26 pt yuvarlak köşeler. Kapalıyken şekil fiziksel çentiğe yapışır; müzik veya sayaç varken iki yana açılıp kapak/ekolayzer ve süre gösterir. Boştayken görünmez.
- **Hareket:** Pencere artık çerçeve animasyonu yapmıyor; sabit boyutlu saydam bir pencere içinde şeklin kendisi SwiftUI yayıyla büyüyor (açılış 0.5 s, hafif sıçrama; kapanış 0.36 s). İçerik bulanıklıktan netleşerek geliyor, sekme kapsülü panelle birlikte iniyor. Sistem "hareketi azalt" ayarı açıkken kısa geçişler kullanılır.
- **Sekmeler:** Dört sekme, iğne ve ayarlar panelin altında ayrı bir cam kapsülde. Rafta öğe varsa nokta rozeti görünür.
- **Pencere katmanı:** Çentikli ekranda macOS menü çubuğu malzemesini ekran koruyucu seviyesinin altındaki her pencerenin üstüne çiziyor (macOS 27'de ölçüldü: 999 boyanıyor, 1000 boyanmıyor). Panel bu yüzden `.screenSaver` seviyesinde; dosya seçici açıkken geçici olarak iner. Bağlam menüleri bu seviyede de panelin üstünde açılıyor.

## Veriler ve bağlantılar

Hesap veya sunucu yok. Dosya referansları, pano içeriği ve sayaç durumu `~/Library/Application Support/Damla/` içinde tutulur; tercihler uygulamanın UserDefaults alanındadır. Pano kaydını kapatmak mevcut geçmişi silmez. Parola yöneticilerinin gizli/geçici olarak işaretlediği içerikler kaydedilmez.

Spotify seçildiğinde albüm kapakları Spotify'ın sağladığı HTTPS adresinden indirilir. Apple Music kapağı ve müzik bilgileri yerel uygulamadan okunur. Tarayıcıdaki YouTube/Spotify Web bu sürümün müzik kaynağı değildir.

## Teknik kapsam

- SwiftUI + AppKit, **glassEffect(.clear)** ile yerel Liquid Glass. macOS 26+.
- `Layout.swift` tek gerçek kaynak: şekil boyutları, pencere boyutu ve fare takibi için görünür dikdörtgen buradan hesaplanır.
- Pil: IOKit; ses: CoreAudio. Ekran kaydı istemez. Erişilebilirlik izni yalnızca "sistem baloncuğunu gizle" seçeneği için gerekir (`CGEvent` tap ile NX_SYSDEFINED medya tuşları yutulur, ses CoreAudio ile, parlaklık `DisplayServicesSetBrightness` ile uygulanır). Ad-hoc imza her derlemede değiştiği için izin yeniden derleme sonrası tekrar verilmelidir.
- Parlaklık okuma, desteklenen yerleşik ekranlarda isteğe bağlı `DisplayServicesGetBrightness` sembolünü kullanır. Harici monitör parlaklığı hedeflenmez.
- Müzik: Apple Events ile Apple Music / Spotify. Konum, 2 saniyelik yenilemeler arasında yerel olarak ilerletilir.
- Yerel ad-hoc imza; App Store/Developer ID dağıtımı ve noter onayı yapılmadı.

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

- macOS 27 / Xcode 27 üzerinde Release derlemesi ve ad-hoc imza doğrulaması. 22 otomatik kontrol (sayaç, pano kuralları, raf referansı, yerleşim boyutları).
- Gerçek Mac'te ekran görüntüsüyle kontrol edildi: kapalı çentik (kapak + ekolayzer, sayaç), hover ile açılış kareleri, Özet (Apple Music parçası, kapak, ilerleme), Dosyalar (5 öğe), Pano (bağlantı/metin/renk kartları), Odak (çalışan sayaç), Ayarlar, ses ve parlaklık HUD'ları.
- Harici 5K monitörde (çentiksiz, ana ekran): menü çubuğundaki sahte çentik (müzik, sayaç), HUD ve açık panel; ayrıca yüzen ada biçimi kontrol edildi. "Fareyi izle" modunda panel fareyle ekran değiştiriyor.
- Pencere seviyesi piksel ölçümüyle doğrulandı; bağlam menüsünün panelin üstünde açıldığı görüldü.
- Ses ve parlaklık uygulayıcıları debug komutlarıyla doğrulandı (1/16 adım, gerçek CoreAudio ve DisplayServices üzerinden okunup geri alındı). Tuş yakalama akışı Erişilebilirlik izni gerektirdiği için kullanıcı tarafından denenmeli.
- Denenmeyenler: gerçek sürükle-bırak akışı, Spotify, tam ekran uygulama geçişleri, uzun süreli enerji kullanımı.
