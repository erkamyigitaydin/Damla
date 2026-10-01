// Damla's site. The water (ebru) runs in a worker when the browser can hand it a canvas (engine.js); this file
// keeps the page: the notch menu, the panel replica and its pages, the pattern book and the print.

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
// Style writes only when a value changes: scrolling should not restyle the panel for nothing.
const written = new WeakMap();
function setVar(el, name, value) {
  let m = written.get(el);
  if (!m) written.set(el, m = new Map());
  if (m.get(name) === value) return;
  m.set(name, value); el.style.setProperty(name, value);
}
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
};

const PIG = { coral: '#f4a18b', saffron: '#ffcc5c', water: '#cce3ff', pale: '#fbf8f1', sea: '#8fb3e6', indigo: '#6d7fd6', teal: '#3a5a8a', abyss: '#233651', paper: '#ebe5d9' };

/* ————————————————— language ————————————————— */

const TR = {
  'skip': 'İçeriğe geç', 'menu': 'Menü',
  'nav.agents': 'Ajanlar', 'nav.notif': 'Bildirimler', 'nav.features': 'Müzik ve dosyalar', 'nav.more': 'Gerisi', 'nav.privacy': 'Gizlilik', 'nav.install': 'Kur',
  'hero.kicker': 'Claude Code · Codex CLI · macOS 26',
  'hero.title': 'Çentiğin, sonunda iş başında.',
  'hero.lede': "Claude Code ve Codex'i onayla, bildirimleri yanıtla, müziğini ve dosyalarını yönet; hepsi editörden çıkmadan. Çentiğin üstüne gel, panel içinden süzülsün; uzaklaş, geri çekilsin.",
  'copy': 'Kopyala', 'download': 'Mac için indir',
  'req': 'macOS 26 ve sonrası · Apple Silicon ve Intel · Ücretsiz',
  'hero.hint': 'Suya tıkla, bir damla bırak. Sürükle, tara.',

  'ag.summary': '1 çalışıyor · 1 bekliyor', 'ag.5h': '5 saat', 'ag.week': '7 gün',
  'ag.wants': 'komut çalıştırmak istiyor', 'ag.always': 'Hep izin ver', 'ag.asks': 'bir şey soruyor', 'ag.terminal': 'Terminalde yanıtla',
  'ag.editing': 'Dosya düzenliyor · 4 dk · 31 çağrı', 'ag.q3t': 'İkisi de',
  'ag.why': "Staging'deki bekleyen veritabanı göçlerini çalıştır", 'ag.goto': "Visual Studio Code'a git",
  'ag.deny': 'Reddet', 'ag.allow': 'İzin ver', 'ag.q': 'Ana başlıkta hangi yazı tipi olsun?',
  'agents.title': 'Her ajan, bir bakış uzağında.',
  'agents.body': 'Damla her Claude Code ve Codex oturumunu gösterir: hangi proje çalışıyor, hangisi seni bekliyor, ne zamandır. Biri izin istediğinde komutun tamamı çentikten süzülür.',
  'agents.p1': '<b>İzin ver, Reddet, Hep izin ver.</b> Claude Code ve Codex CLI için; ya da her uygulamadan <kbd>⌃⌥↩</kbd> ve <kbd>⌃⌥⌫</kbd>. Paneldekini dene.',
  'agents.p2': '<b>Sorularını yanıtla.</b> Claude Code senden seçim isteyince seçimi çentikte yaparsın.',
  'agents.p3': "<b>Bağlam ve limitler.</b> Her oturumun bağlamı ne kadar dolu, beş saatlik ve haftalık kullanımın ne durumda, Mac'inde hangi geliştirme sunucuları açık.",
  'agents.slip': "Ayarlar › Ajanlar'da tek tık, kancaları yedek alarak Claude Code ve Codex'e ekler. Yalnızca durumu bildirirler: aşama, araç adı, süre. İstemlerin ve çıktıların asla okunmaz.",

  'nc.body': 'Düzeltmeyi gönderdim. Akşamdan önce PR’a bakabilir misin?', 'nc.reply': 'Yanıtla…', 'nc.open': 'Aç', 'nc.send': 'Gönder',
  'nc.dismiss': 'Bildirimi kapat', 'nc.tap': 'Tıkla: yanıtla ya da düğmeleri göster',
  'nl.count': '3 bildirim', 'nl.clear': 'Temizle', 'nl.now': 'şimdi', 'nl.4m': '4 dk', 'nl.9m': '9 dk', 'nl.cal': 'Takvim',
  'nl.mail.t': "main'de CI geçti", 'nl.mail.d': 'landing-page · 214 test, 3 dk 12 sn', 'nl.cal.t': 'Tasarım incelemesi', 'nl.cal.d': '10 dakika sonra · Oda 2',
  'notif.title': 'Bildirimler çentikten düşer.',
  'notif.body': 'Bir mesaj, bir e-posta, bir takvim uyarısı: başka uygulamaların bildirimleri köşedeki balon yerine çentiğin altında bir kart olarak gelir. Tıkla: yanıtla ya da düğmelerini kullan; ✕ ile kapat.',
  'notif.p1': '<b>Olduğun yerden yanıtla.</b> WhatsApp mesajını editörden çıkmadan yanıtla; Aç seni sohbete götürür. Paneldeki karta tıkla.',
  'notif.p2': '<b>Kaçırdıkların bekler.</b> Bildirimler sayfası bu oturumda gelenleri uygulamaya göre deste yapar; okunmamışlar çentikte zil ve sayı olarak durur.',
  'notif.slip': 'Yalnızca bellekte tutulur. Diske hiçbir şey yazılmaz; Damla kapanınca gider.',

  'np.in': '8 dk', 'np.meeting': 'Tasarım incelemesi', 'np.speakers': 'Hoparlör',
  'music.title': 'Ne çalıyorsa, burada.',
  'music.body': 'Apple Music, Spotify, podcast’ler, tarayıcıda YouTube: kapak, ilerleme ve düğmeler; tüm panel dinlediğin albümün rengini alır.',
  'music.p1': '<b>Şarkıyla akan sözler.</b> Panel aşağı uzar, sözler akar.',
  'music.p2': "<b>Video çentiğin altında.</b> Chrome, Brave, Edge ya da Vivaldi'deki video çentiğin altında oynamaya devam eder; tarayıcı arka planda olsa da.",
  'music.p3': '<b>Akıllı devir.</b> Video başlayınca müzik durur, video bitince geri gelir. Duraklatılan oynatıcı birkaç saniye sonra çentikten çekilir.',

  'sh.drop': 'Dosyaları buraya bırak',
  'files.title': 'Dosyaların için bir raf.',
  'files.body': 'Herhangi bir yerde bir dosyayı sürüklemeye başla, çentik bir bırakma alanına dönüşsün. Boşluk ile önizle, başka bir uygulamaya sürükle ya da AirDrop ile gönder. Yeni ekran görüntüleri rafa kendiliğinden düşer.',
  'files.p1': "<b>Dönüştür ve küçült.</b> Bir görseli PNG, JPEG ya da HEIC olarak kaydet, sıkıştır ya da raftaki PDF'leri tek dosyada birleştir.",
  'files.p2': "<b>Burada dene.</b> Mac'inden bu sayfaya bir dosya bırak. Tarayıcından dışarı çıkmaz.",
  'files.slip': 'Damla yalnızca dosyalarının nerede olduğunu hatırlar. Onları asla taşımaz ya da değiştirmez.',

  'cam.nostalgia': 'Nostalji', 'cam.center': 'Ana Sahne', 'cam.film': 'Film görünümü', 'cam.timer': '3 saniye geri sayım', 'cam.shoot': '3 saniye sonra çek', 'cam.save': 'Fotoğrafı kaydet',
  'mirror.title': 'Çentikte bir anlık fotoğraf makinesi.',
  'mirror.body': "Ayna, görüşmeden önce saçına bakmanı sağlar. Deklanşöre bas; vizörde gördüğün kadraj aynen çekilir ve Resimler › Damla'ya geniş bir polaroid olarak kaydedilir.",
  'mirror.p1': '<b>Gerçek bir polaroid.</b> Krem çerçeve, köşede turuncu tarih damgası ve alt boşlukta el yazısıyla tarih; istersen. En yenisi köşede bekler.',
  'mirror.p2': '<b>Üç film.</b> Nostalji, siyah beyaz, doğal. 3 saniyelik zamanlayıcı ve Ana Sahne hep bir tık uzakta.',
  'mirror.try': 'Kendi kameranla dene',

  'book.title': 'Ve geri kalan her şey.',
  'book.lede': "Damla'nın sessiz işleri, her biri tarayıcında canlı çizilen bir ebru kâğıdının üstünde. Ebru ustaları desenlerine ad verir; adları her birinin altında.",
  'b.servers.t': 'Yerel sunucular', 'b.servers.d': "Mac'inde çalışan her geliştirme sunucusu ve veritabanı; açmak ya da durdurmak tek tık.",
  'v.srv': 'Yerel sunucular · 3', 'v.stop': 'Durdur',
  'b.sound.t': 'Ses, senin ayarınla', 'b.sound.d': 'Çıkışı tek dokunuşla değiştir, AirPods’un her kulaklığının ve kutusunun şarjını gör, her uygulamaya kendi ses seviyesini ver. Sesi çentikte kaydırarak değiştir.',
  'snd.output': 'Ses çıkışı', 'snd.mbp': 'MacBook Pro Hoparlörü', 'snd.volume': 'Ses seviyesi', 'snd.system': 'Sistem',
  'v.pods': 'S %80 · Sa %75 · K %60',
  'b.clip.t': 'Pano geçmişi', 'b.clip.d': 'Kopyaladıklarını ara ve sabitle. Sen açana kadar kapalı.',
  'v.search': 'Ara', 'v.link': 'Bağlantı', 'v.text': 'Metin', 'v.color': 'Renk', 'v.clip.text': 'Fatura #2041 gönderildi. Cuma hatırlat.',
  'b.pages.t': 'Sayfaların, senin sıran', 'b.pages.d': 'Sayfaları aç, kapat ve Ayarlar › Genel › Sayfalar’da sürükleyerek istediğin sıraya koy. Panelin altındaki kapsül de aynı sırayı izler.',
  'v.pages': 'Sayfalar', 'v.drag': 'Sıralamak için sürükle.', 'v.tab.home': 'Özet', 'v.tab.agents': 'Agent’lar', 'v.tab.notif': 'Bildirimler', 'v.tab.files': 'Dosyalar', 'v.tab.sc': 'Kestirmeler',
  'b.tour.t': 'Çentiğin içinde bir tanıtım', 'b.tour.d': 'İlk açılış Damla’yı tam yaşadığı yerde gezdirir. Bütün izinler tek sayfada ve hepsi isteğe bağlı: vermediğin izin yalnızca o özelliği kapatır.',
  'v.perm.t': 'İzinler', 'v.perm.ax': 'Erişilebilirlik', 'v.perm.ax.d': 'Ses göstergesi, video, bildirimler', 'v.perm.mu': 'Müzik', 'v.perm.mu.d': 'Parçayı göster, oynatmayı yönet',
  'v.perm.cam': 'Kamera', 'v.perm.cam.d': 'Ayna', 'v.perm.cal': 'Takvim', 'v.perm.cal.d': 'Sıradaki toplantı ve katılma bağlantısı', 'v.allow': 'İzin ver', 'v.skip': 'Geç', 'v.next': 'İleri',
  'b.mic.t': 'Mikrofon kullanımda mı?', 'b.mic.d': 'Görüşme sırasında çentik bunu gösterir; tek dokunuşla tüm uygulamalar için sessize alırsın.', 'v.muted': 'Mikrofon kapalı',
  'b.focus.t': 'Kadran gibi çevrilen odak zamanlayıcı', 'b.focus.d': 'Halkayı çevir, bir sayı yaz ya da kaydır; istediğin süre. Geri sayım doğrudan çentikte.',
  'b.shortcuts.t': 'Kestirmeler', 'b.shortcuts.d': 'Kestirmeler uygulamasında yaptığın her şey, tek dokunuşluk bir düğme olarak.',
  'v.sc.hint': 'Sık kullandıklarını sabitle; burada tek dokunuşluk düğme olurlar.', 'v.sc.1': 'Web için yeniden boyutla', 'v.sc.2': 'Toplantı notu başlat', 'v.sc.3': 'İndirilenleri topla',
  'b.battery.t': 'Düşük pil uyarıları', 'b.battery.d': 'Fare, klavye, izleme dörtgeni ve AirPods için; cümlenin ortasında kapanmadan önce.',
  'b.swipe.t': 'Sayfalar arasında kaydır', 'b.swipe.d': 'İzleme dörtgeninde iki parmak; sayfa parmağını takip eder. Kapatınca panel çentiğe geri çekilir.',
  'book.also': '<b>Ayrıca:</b> çentiği olmayan ekranlarda menü çubuğuna çizilen ve boştayken gizlenebilen bir çentik · tam ekran uygulamalarda menü çubuğuyla birlikte gizlenir · temizlik modu, silebilmen için klavyeyi 60 saniye kilitler · müzik ve ajanlar çalışırken bile işlemciyi yormaz · İngilizce ve Türkçe.',

  'pv.l1': 'Hesap yok.', 'pv.l2': 'Bulut yok.', 'pv.l3': 'Takip yok.',
  'pv.body': "Her şey Mac'inde kalır. Rafın, pano geçmişin ve zamanlayıcın <code>~/Library/Application Support/Damla/</code> içinde durur; bildirimler ve metinleri yalnızca bellekte tutulur.",
  'pv.net': "Ağa yalnızca iki şey dokunur: açarsan şarkı sözleri (şarkı adı, sanatçı, albüm ve süre lrclib.net'e gider) ve günlük güncelleme denetimi; bu denetim sayılır ama IP adresin ya da bir kimlik saklanmaz.",
  'pv.perms': 'Her izin isteğe bağlı',
  'pv.ax': 'Erişilebilirlik', 'pv.ax.d': 'Çentikte bildirimler, ses ve parlaklık göstergeleri, video, temizlik modu',
  'pv.auto': 'Otomasyon', 'pv.auto.d': "Apple Music'i, Spotify'ı ve videonu oynatan tarayıcıyı yönetmek",
  'pv.screen': 'Ekran kaydı', 'pv.screen.d': 'Çentikteki video için tarayıcının video penceresini bulmak. Hiçbir şey kaydedilmez',
  'pv.audio': 'Sistem sesi kaydı', 'pv.audio.d': 'Uygulama başına ses. Hiçbir şey kaydedilmez',
  'pv.cal': 'Takvimler', 'pv.cal.d': 'Sıradaki toplantın, sen açınca',
  'pv.cam': 'Kamera', 'pv.cam.d': 'Ayna sayfası, yalnızca açıkken',

  'print.caption': 'Senin ebrun: tıkladığın her damla, sürüklediğin her çizgi.', 'print.alt': 'Mermer desenli bir ebru', 'print.save': 'Ebrunu kaydet',
  'fin.title': 'Kurulumu tek satır.',
  'fin.lede': "Ücretsiz, Apple tarafından imzalanmış ve onaylanmış; kendini güncel tutar. Sonra Ayarlar › Ajanlar'dan Claude Code ya da Codex'i bağla.",
  'keys.open': '<b>Aç</b><span>çentiğin üstüne gel, menü çubuğundaki damlaya tıkla ya da <kbd>⌃</kbd><kbd>⌥</kbd><kbd>Boşluk</kbd></span>',
  'keys.answer': '<b>Yanıtla</b><span><kbd>⌃</kbd><kbd>⌥</kbd><kbd>↩</kbd> bekleyen isteğe izin verir, <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌫</kbd> reddeder</span>',
  'keys.close': '<b>Kapat</b><span>uzaklaş, çentiğe tıkla ya da <kbd>Esc</kbd></span>',
  'keys.settings': '<b>Ayarlar</b><span>dişli, menü çubuğu simgesi ya da <kbd>⌘</kbd><kbd>,</kbd></span>',
  'foot.issues': 'Sorun bildir',
  'foot.note': 'Erkam Yiğit Aydın yaptı. Bu sayfadaki ebru tarayıcında canlı çiziliyor; hiçbir şey takip edilmiyor.',
};

// Strings the script writes itself, in both languages.
const DYN = {
  en: {
    title: 'Damla · your notch, finally at work',
    copied: 'Copied',
    waiting: s => `Waiting for approval: Bash · ${s} s · 12 calls`,
    working: 'Running: Bash · 13 calls',
    doneRun: 'Response complete · 13 calls',
    denied: 'You denied it in Damla',
    note: { allow: 'Allowed. The agent carries on.', always: 'Allowed, and the rule is saved for this project.', deny: 'Denied. Claude Code hears it straight away.' },
    summaryAfter: '2 working',
    items: n => `${n} ${n === 1 ? 'item' : 'items'}`,
    sec: s => `${s} s`, ago: s => `${s} sec`,
    answered: o => `Sent: “${o}”. Claude Code carries on.`,
    sent: 'Sent to Deniz from the notch.',
    camTry: 'Try it with your camera', camStop: 'Stop the camera', camDenied: 'No camera access, so the water poses instead.',
    films: { nostalgia: 'Nostalgia', bw: 'Black & white', natural: 'Natural' },
    shoot: on => on ? 'Take a photo in 3 seconds' : 'Take a photo',
  },
  tr: {
    title: 'Damla · çentiğin, sonunda iş başında',
    copied: 'Kopyalandı',
    waiting: s => `Bash için onay bekliyor · ${s} sn · 12 çağrı`,
    working: 'Çalışıyor: Bash · 13 çağrı',
    doneRun: 'Yanıt tamamlandı · 13 çağrı',
    denied: "Damla'dan reddettin",
    note: { allow: 'İzin verildi. Ajan devam ediyor.', always: 'İzin verildi; kural bu proje için kaydedildi.', deny: 'Reddedildi. Claude Code bunu hemen duyar.' },
    summaryAfter: '2 çalışıyor',
    items: n => `${n} öğe`,
    sec: s => `${s} sn`, ago: s => `${s} sn`,
    answered: o => `Gönderildi: “${o}”. Claude Code devam ediyor.`,
    sent: "Çentikten Deniz'e gönderildi.",
    camTry: 'Kendi kameranla dene', camStop: 'Kamerayı kapat', camDenied: 'Kamera izni yok; o yüzden su poz veriyor.',
    films: { nostalgia: 'Nostalji', bw: 'Siyah beyaz', natural: 'Doğal' },
    shoot: on => on ? '3 saniye sonra çek' : 'Çek',
  },
};

const EN = {};
let lang = 'en';
function captureEnglish() {
  for (const el of $$('[data-i18n]')) EN[el.dataset.i18n] = el.textContent;
  for (const el of $$('[data-i18n-html]')) EN[el.dataset.i18nHtml] = el.innerHTML;
  for (const el of $$('[data-i18n-aria]')) EN[el.dataset.i18nAria] = el.getAttribute('aria-label');
  for (const el of $$('[data-i18n-ph]')) EN[el.dataset.i18nPh] = el.getAttribute('placeholder');
}
function setLang(next) {
  lang = next === 'tr' ? 'tr' : 'en';
  const dict = lang === 'tr' ? TR : EN;
  document.documentElement.lang = lang;
  for (const el of $$('[data-i18n]')) { const v = dict[el.dataset.i18n] ?? EN[el.dataset.i18n]; if (v != null) el.textContent = v; }
  for (const el of $$('[data-i18n-html]')) { const v = dict[el.dataset.i18nHtml] ?? EN[el.dataset.i18nHtml]; if (v != null) el.innerHTML = v; }
  for (const el of $$('[data-i18n-aria]')) { const v = dict[el.dataset.i18nAria] ?? EN[el.dataset.i18nAria]; if (v != null) el.setAttribute('aria-label', v); }
  for (const el of $$('[data-i18n-ph]')) { const v = dict[el.dataset.i18nPh] ?? EN[el.dataset.i18nPh]; if (v != null) { el.setAttribute('placeholder', v); el.setAttribute('aria-label', v); } }
  for (const b of $$('.lang button')) b.setAttribute('aria-pressed', String(b.dataset.lang === lang));
  document.title = DYN[lang].title;
  store.set('damla.lang', lang);
  agents.refresh(); shelf.refreshCount(); mirror.relabel();
  // Copy changes height: the panel makes room for the longest chapter again.
  stage.measure(); stage.update();
  fitVignettes();
}
const t = () => DYN[lang];

/* ————————————————— the droplet ————————————————— */

/* ————————————————— the droplet ————————————————— */

const DROP = 'M55 3C61 19 86 38 86 63C86 83 70 98 50 98C30 98 14 83 14 63C14 39 40 22 55 3Z';
// The same drop as the app (Mascot.swift) and its icon, in a 100 × 100 box: a full drop whose tip leans right,
// lit from the top left, a curved glint, eyes with a catchlight and coral cheeks. Phases are CSS (site.css).
const MASCOT = `<g class="m-body"><path class="m-drop" d="${DROP}"/><path d="${DROP}" fill="url(#m-light)"/><rect y="60" width="100" height="40" fill="url(#m-glow)" clip-path="url(#m-clip)"/>`
  + `<path d="${DROP}" fill="none" stroke="rgba(255,255,255,.4)" stroke-width="1.6"/>`
  + `<path d="M23.8 56.5A27 27 0 0 1 35.5 40.2" fill="none" stroke="rgba(255,255,255,.85)" stroke-width="4.6" stroke-linecap="round"/><circle cx="29" cy="36" r="2.4" fill="rgba(255,255,255,.85)"/>`
  + `<g class="m-cheeks"><ellipse cx="30" cy="75" rx="5.4" ry="3.2"/><ellipse cx="70" cy="75" rx="5.4" ry="3.2"/></g>`
  + `<g class="m-eyes"><g class="m-eye"><ellipse cx="39" cy="64" rx="5.2" ry="6.6"/><circle cx="41" cy="61.2" r="1.9"/></g><g class="m-eye"><ellipse cx="61" cy="64" rx="5.2" ry="6.6"/><circle cx="63" cy="61.2" r="1.9"/></g></g>`
  + `<path class="m-ink m-smile" d="M43 76Q50 83 57 76"/><path class="m-ink m-work" d="M46 78Q51 81 56 78"/><ellipse class="m-ink m-o" cx="50" cy="80" rx="3.6" ry="4.6"/>`
  + `<g class="m-happy"><path class="m-ink" d="M33 66Q39 57 45 66M55 66Q61 57 67 66"/><path d="M41 76Q50 87 59 76Z"/></g>`
  + `<g class="m-spark"><path d="M84 9Q84 18 93 18Q84 18 84 27Q84 18 75 18Q84 18 84 9Z"/><path d="M93 28.5Q93 33 97.5 33Q93 33 93 37.5Q93 33 88.5 33Q93 33 93 28.5Z"/></g><g class="m-arm"><path d="M80 64Q92 58 93 42" fill="none" stroke-width="13" stroke-linecap="round"/><circle cx="93" cy="38" r="8.5"/></g></g>`;
function drawMascots() {
  const defs = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  defs.setAttribute('width', '0'); defs.setAttribute('height', '0'); defs.setAttribute('aria-hidden', 'true');
  defs.style.position = 'absolute';
  defs.innerHTML = `<defs><linearGradient id="m-light" gradientUnits="userSpaceOnUse" x1="30" y1="10" x2="70" y2="100"><stop offset="0" stop-color="#fff" stop-opacity=".42"/><stop offset=".55" stop-color="#fff" stop-opacity="0"/><stop offset=".56" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".2"/></linearGradient><radialGradient id="m-glow" gradientUnits="userSpaceOnUse" cx="50" cy="108" r="34"><stop offset=".12" stop-color="#fff" stop-opacity=".55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient><clipPath id="m-clip"><path d="${DROP}"/></clipPath></defs>`;
  document.body.append(defs);
  for (const svg of $$('svg.mascot')) svg.innerHTML = MASCOT;
}

/* ————————————————— the water ————————————————— */

// The page's side of the ebru. Everything is a message to the engine, which lives in a worker when the browser
// can transfer a canvas there, and on this page otherwise. Coordinates are CSS pixels of the viewport.
const water = {
  canvas: $('#tray'), w: innerWidth, h: innerHeight, worker: null, engine: null, queue: [], waiting: new Map(), seq: 0,
  async start() {
    this.w = document.documentElement.clientWidth; this.h = innerHeight;
    const init = { type: 'init', w: this.w, h: this.h, dpr: devicePixelRatio || 1, ground: PIG.paper };
    if (canWork()) {
      try {
        this.worker = new Worker(new URL('./ebru-worker.js', import.meta.url), { type: 'module' });
        this.worker.onmessage = e => this.receive(e.data);
        const off = this.canvas.transferControlToOffscreen();
        this.worker.postMessage({ ...init, canvas: off }, [off]);
        this.flush();
        return;
      } catch { this.worker = null; }
    }
    const { createEngine } = await import('./engine.js');
    this.engine = createEngine(msg => this.receive(msg));
    this.engine.handle({ ...init, canvas: this.canvas });
    this.flush();
  },
  ready() { return !!(this.worker || this.engine); },
  flush() { const q = this.queue; this.queue = []; for (const [m, tr] of q) this.post(m, tr); },
  post(msg, transfer = []) {
    if (this.worker) this.worker.postMessage(msg, transfer);
    else if (this.engine) this.engine.handle(msg);
    else this.queue.push([msg, transfer]);
  },
  // A canvas of the page handed to the engine (the viewfinder, a pattern sheet): transferred when it runs in a worker.
  give(canvas) { return this.worker && canvas.transferControlToOffscreen ? canvas.transferControlToOffscreen() : canvas; },
  ask(msg) {
    const id = ++this.seq;
    return new Promise(resolve => { this.waiting.set(id, resolve); this.post({ ...msg, id }); });
  },
  receive(msg) {
    const done = this.waiting.get(msg.id);
    if (done) { this.waiting.delete(msg.id); done(msg.bitmap || msg.stats); }
  },
  snapshot(rect, out) { return this.ask({ type: 'snapshot', rect, out }); },
  stats(reset = false) { return this.ask({ type: 'stats', reset }); },
  drop(x, y, r, color) { this.post({ type: 'drop', x, y, r, color }); },
  bloom(x, y, r, color, ms) { this.post({ type: 'bloom', x, y, r, color, ms }); },
};
function canWork() {
  if (!('transferControlToOffscreen' in HTMLCanvasElement.prototype) || typeof OffscreenCanvas !== 'function') return false;
  // Module workers (Safari 15+, Chrome 80+, Firefox 114+).
  let module = false;
  try { const url = URL.createObjectURL(new Blob([''], { type: 'text/javascript' })); new Worker(url, { get type() { module = true; return 'module'; } }).terminate(); URL.revokeObjectURL(url); } catch { return false; }
  return module;
}
let trayLive = true;          // hero or stage on screen

// A drop falls out of the notch and blooms where it lands.
function drip(fromX, fromY, toX, toY, r, color, delay = 0) {
  if (reduced.matches) { water.drop(toX, toY, r, color); return; }
  setTimeout(() => {
    const el = document.createElement('div');
    el.className = 'falling';
    el.innerHTML = `<svg viewBox="0 0 100 100" aria-hidden="true"><path d="M50 2C102 50 96 98 50 98C4 98-2 50 50 2Z" fill="${color}"/></svg>`;
    document.body.append(el);
    const dist = Math.max(40, toY - fromY), ms = 260 + Math.sqrt(dist) * 14;
    const anim = el.animate([
      { transform: `translate(${fromX}px, ${fromY}px) scale(.4, .6)`, opacity: 1 },
      { transform: `translate(${toX}px, ${toY}px) scale(.9, 1.25)`, opacity: 1 },
    ], { duration: ms, easing: 'cubic-bezier(.55,0,1,.45)', fill: 'forwards' });
    anim.onfinish = () => { el.remove(); water.bloom(toX, toY, r, color, 700 + r * 4); };
  }, delay);
}

// The opening drop lands in the free water above the headline and install block, never under them.
function heroSequence() {
  const { w } = water;
  const copyTop = $('.hero-inner').getBoundingClientRect().top + scrollY;
  const top = 48, bottom = Math.max(top + 140, copyTop - 28), room = bottom - top;
  // the rings reach 0.14 m above the centre; the needle pulls the tulip down to 0.32 m below it
  const m = Math.min(w * 0.8, 900, (room - 8) / 0.46);
  const cx = w / 2, cy = top + 0.14 * m + Math.max(0, room - 0.46 * m) / 2;
  // on paper the outermost ring is the deep blue that frames the rest
  const seq = [PIG.teal, PIG.water, PIG.sea, PIG.coral, PIG.pale, PIG.abyss, PIG.water, PIG.teal];
  let s = 3;
  const r = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
  seq.forEach((c, i) => {
    const R = m * (0.13 - i * 0.008);
    drip(cx, 30, cx + (r() - 0.5) * m * 0.05, cy + (r() - 0.5) * m * 0.04, R, c, reduced.matches ? 0 : 500 + i * 360);
  });
  // then a needle is pulled down through the rings: the drop becomes a tulip
  const needleAt = reduced.matches ? 0 : 500 + seq.length * 360 + 1100;
  setTimeout(() => {
    const path = [];
    for (let i = 0; i <= 40; i++) path.push([cx, cy - m * 0.2 + (m * 0.5) * i / 40]);
    water.post({ type: 'needle', path, ms: 1500, lambda: 18, instant: reduced.matches });
  }, needleAt);
}

// The water is yours: a click drops pigment where you click, a drag combs it (mouse and pen; touch scrolls).
const PALETTE = [PIG.teal, PIG.coral, PIG.sea, PIG.water, PIG.abyss];
let paletteAt = 0;
function stylusOnWater() {
  const zones = [$('.hero'), $('.stage-pin')];
  const skip = 'a, button, input, label, code, h1, h2, p, li, form, .brew, .panel-wrap, .chapter, .notch';
  for (const zone of zones) {
    let prev = null, start = null, moved = 0, queued = null;
    zone.addEventListener('pointerdown', e => {
      if (e.button !== 0 || e.target.closest(skip)) return;
      start = prev = [e.clientX, e.clientY]; moved = 0;
      if (e.pointerType !== 'touch') { zone.setPointerCapture(e.pointerId); e.preventDefault(); }
    });
    zone.addEventListener('pointermove', e => {
      if (!prev || e.pointerType === 'touch') return;
      moved += Math.hypot(e.clientX - prev[0], e.clientY - prev[1]);
      if (moved <= 6) return;
      // Pointer events can outpace the screen; one needle stroke per frame carries the whole move.
      if (!queued) { queued = prev; requestAnimationFrame(() => { if (queued && prev) water.post({ type: 'stylus', x0: queued[0], y0: queued[1], x1: prev[0], y1: prev[1], lambda: 18 }); queued = null; }); }
      prev = [e.clientX, e.clientY];
      $('.hero').classList.add('combed');
    });
    zone.addEventListener('pointerup', e => {
      if (start && moved <= 6) {
        const m = Math.min(water.w, water.h);
        const color = PALETTE[paletteAt++ % PALETTE.length];
        if (reduced.matches) water.drop(e.clientX, e.clientY, m * 0.05, color); else water.bloom(e.clientX, e.clientY, m * 0.05, color, 700);
        $('.hero').classList.add('combed');
      }
      start = prev = null;
    });
    zone.addEventListener('pointercancel', () => { start = prev = null; });
  }
}

/* ————————————————— home: now playing ————————————————— */

/* ————————————————— home: now playing ————————————————— */

const TRACKS = [
  { title: 'Golden Hour', by: 'Nova Lane', tint: PIG.coral, len: 214, at: 85,
    art: `<defs><linearGradient id="c0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f58a6a"/><stop offset=".55" stop-color="#e24f8e"/><stop offset="1" stop-color="#7a3fa6"/></linearGradient></defs><rect width="100" height="100" fill="url(#c0)"/><circle cx="50" cy="40" r="20" fill="#fbd18a"/><g fill="#6a3596"><rect y="70" width="100" height="4"/><rect y="79" width="100" height="5"/><rect y="89" width="100" height="6"/></g>` },
  { title: 'Ferry at Dusk', by: 'Kıyı', tint: PIG.indigo, len: 242, at: 64,
    art: `<defs><linearGradient id="c1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b2250"/><stop offset=".6" stop-color="#4556c2"/><stop offset="1" stop-color="#9fb0ff"/></linearGradient></defs><rect width="100" height="100" fill="url(#c1)"/><circle cx="70" cy="30" r="10" fill="#ede7dc"/><path d="M18 62h40l-5 7H24Z" fill="#0e1330"/><rect x="30" y="54" width="18" height="8" fill="#0e1330"/><g stroke="#c9d3ff" stroke-opacity=".55" stroke-width="1.6"><path d="M0 76h100M10 83h80M22 90h56"/></g>` },
  { title: 'Paper Lanterns', by: 'Low Tide', tint: '#d98aa0', len: 178, at: 41,
    art: `<defs><linearGradient id="c2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f3b7c6"/><stop offset="1" stop-color="#7a3550"/></linearGradient></defs><rect width="100" height="100" fill="url(#c2)"/><g fill="#5a2340"><rect x="22" y="30" width="16" height="22" rx="7"/><rect x="44" y="20" width="16" height="22" rx="7"/><rect x="64" y="34" width="16" height="22" rx="7"/></g><g stroke="#ffd9e2" stroke-width="1.4"><path d="M30 18v12M52 8v12M72 22v12"/></g><path d="M0 80q25-8 50 0t50 0V100H0Z" fill="#4a1d35"/>` },
];
const music = {
  i: 0, playing: true, at: TRACKS[0].at, byHand: 0, lyricsByHand: null,
  panel: $('#panel'),
  set(i, fromScroll = false) {
    i = (i + TRACKS.length) % TRACKS.length;
    if (i === this.i) return;
    this.i = i; this.at = TRACKS[i].at;
    if (!fromScroll) this.byHand = performance.now();
    this.paint();
  },
  paint() {
    const tr = TRACKS[this.i];
    $('.cover-art').innerHTML = tr.art;
    $('.np-title').textContent = tr.title;
    $('.np-by').textContent = tr.by;
    document.documentElement.style.setProperty('--tint', tr.tint);
    this.tick(0);
  },
  tick(dt) {
    const tr = TRACKS[this.i];
    if (this.playing) this.at = Math.min(tr.len, this.at + dt);
    const fmt = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
    $('.bar-fill').style.width = `${(this.at / tr.len) * 100}%`;
    $('.t-now').textContent = fmt(this.at);
    $('.t-left').textContent = `-${fmt(tr.len - this.at)}`;
  },
  lyricsOn(sub) { return this.lyricsByHand ?? (this.i === 1 && sub >= 0.6); },
  scrollLyrics(sub) {
    const lines = $$('.lyrics li');
    const k = this.lyricsByHand ? (this.at / 30) % lines.length : clamp((sub - 0.6) / 0.4) * (lines.length - 1);
    const now = Math.round(k);
    lines.forEach((li, j) => { setVar(li, '--line', k.toFixed(2)); if (li.classList.contains('now') !== (j === now)) li.classList.toggle('now', j === now); });
  },
  init() {
    this.paint();
    $('.lyrics-btn').addEventListener('click', () => {
      this.lyricsByHand = !this.panel.classList.contains('lyrics-on');
      if (this.lyricsByHand && this.i !== 1) this.set(1);
      this.byHand = performance.now();
      stage.update();
    });
    $('[data-act="play"]').addEventListener('click', e => {
      this.playing = !this.playing;
      this.panel.classList.toggle('paused', !this.playing);
      $('#notch').classList.toggle('paused', !this.playing);
      e.currentTarget.setAttribute('aria-label', this.playing ? 'Pause' : 'Play');
    });
    $('[data-act="next"]').addEventListener('click', () => this.set(this.i + 1));
    $('[data-act="prev"]').addEventListener('click', () => this.set(this.i - 1));
    $('.heart').addEventListener('click', e => e.currentTarget.setAttribute('aria-pressed', String(e.currentTarget.getAttribute('aria-pressed') !== 'true')));
  },
};

/* ————————————————— agents ————————————————— */

/* ————————————————— agents ————————————————— */

const agents = {
  page: $('.page-agents'), wait: 44, answered: null, asked: null, doneAt: 0, forceList: false,
  refresh() {
    const card = $('.session.waiting'), state = $('.s-state', card), mascot = $('.mascot', card);
    if (!this.answered) { state.textContent = t().waiting(this.wait); mascot.dataset.phase = 'waiting'; }
    else if (this.answered === 'deny') { state.textContent = t().denied; mascot.dataset.phase = 'idle'; }
    else { state.textContent = this.doneAt ? t().doneRun : t().working; mascot.dataset.phase = this.doneAt ? 'done' : 'working'; }
    card.classList.toggle('approved', !!this.answered);
    $('[data-tab="agents"]').classList.toggle('dot', !this.answered);
    $('.a-api').textContent = t().ago(Math.max(2, this.wait - 34));
    $('.a-landing').textContent = t().ago(5);
    $('.ask-timer').textContent = t().sec(Math.max(1, 162 - this.wait));
    $('.q-timer').textContent = t().sec(Math.max(1, 140 - this.wait));
    $('.ns-agents').textContent = t().sec(this.wait);
    $('.ask-done').textContent = this.answered ? t().note[this.answered] : '';
    $('.ag-sum').textContent = this.answered ? t().summaryAfter : (lang === 'tr' ? TR['ag.summary'] : EN['ag.summary']);
    stage.notchMascot();
  },
  answer(kind) {
    if (this.answered) return;
    this.answered = kind; this.doneAt = 0;
    this.page.dataset.answered = kind;
    this.refresh();
    if (kind !== 'deny') setTimeout(() => { if (this.answered && this.answered !== 'deny') { this.doneAt = 1; this.refresh(); } }, 2600);
    // show the list so the droplet can be seen reacting
    setTimeout(() => {
      if (!this.answered) return;
      this.page.dataset.view = 'list'; this.forceList = true;
      setTimeout(() => { this.forceList = false; }, 3200);
    }, 1300);
  },
  reset() {
    this.answered = null; this.asked = null; this.doneAt = 0; this.forceList = false;
    delete this.page.dataset.answered; delete this.page.dataset.asked;
    for (const b of $$('.q-opt')) b.setAttribute('aria-pressed', 'false');
    $('.q-done').textContent = '';
    this.refresh();
  },
  init() {
    for (const b of $$('[data-answer]')) b.addEventListener('click', () => this.answer(b.dataset.answer));
    for (const b of $$('.q-opt')) b.addEventListener('click', () => {
      for (const o of $$('.q-opt')) o.setAttribute('aria-pressed', String(o === b));
      this.asked = b.textContent; this.page.dataset.asked = '1';
      $('.q-done').textContent = t().answered(b.textContent);
    });
    addEventListener('keydown', e => {
      if (stage.chapter !== 'agents' || this.answered || !e.ctrlKey || !e.altKey) return;
      if (e.key === 'Enter') { e.preventDefault(); this.answer('allow'); }
      if (e.key === 'Backspace') { e.preventDefault(); this.answer('deny'); }
    });
    setInterval(() => { if (!document.hidden && !this.answered) { this.wait++; this.refresh(); } }, 1000);
    this.refresh();
  },
};

/* ————————————————— notifications ————————————————— */

const notes = {
  page: $('.page-notif'), byHand: 0, done: false,
  set view(v) { if (this.page.dataset.view !== v) { this.page.dataset.view = v; stage.layout(); } },
  get view() { return this.page.dataset.view; },
  hold() { this.byHand = performance.now(); },
  reveal() {
    this.hold();
    this.view = this.view === 'card' ? 'reply' : this.view;
    if (this.view === 'reply' && matchMedia('(hover: hover)').matches) setTimeout(() => $('.nc-reply input').focus({ preventScroll: true }), 380);
  },
  read() {
    // Read, then gone from the notch: the page keeps it, the bell and the dot clear.
    this.done = true;
    $('[data-tab="notif"]').classList.remove('dot');
    $('.ns-notif b').textContent = '2';
  },
  reset() {
    this.done = false; this.byHand = 0;
    this.page.classList.remove('sent', 'gone');
    $('.nc-sent').textContent = ''; $('.nc-reply input').value = '';
    $('[data-tab="notif"]').classList.add('dot');
    $('.ns-notif b').textContent = '3';
    this.page.dataset.view = 'card';
  },
  // Scrolling plays the story unless the visitor is busy with the card.
  follow(sub) {
    if (performance.now() - this.byHand < 6000 || this.done) return;
    this.view = sub < 0.4 ? 'card' : sub < 0.68 ? 'reply' : 'list';
  },
  init() {
    const row = $('.nc-row');
    row.addEventListener('click', e => { if (!e.target.closest('.nc-x')) this.reveal(); });
    row.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); this.reveal(); } });
    $('.nc-x').addEventListener('click', () => {
      this.hold(); this.page.classList.add('gone');
      setTimeout(() => { this.page.classList.remove('gone'); this.view = 'list'; this.read(); }, 420);
    });
    $('.nc-reply').addEventListener('submit', e => {
      e.preventDefault();
      const input = $('.nc-reply input');
      if (!input.value.trim()) { input.focus(); return; }
      this.hold(); input.value = ''; input.blur();
      $('.nc-sent').textContent = t().sent; this.page.classList.add('sent');
      setTimeout(() => { this.page.classList.remove('sent'); this.view = 'list'; this.read(); }, 1600);
    });
    $('.nc-reply input').addEventListener('focus', () => this.hold());
    $('.nc-reply input').addEventListener('input', () => this.hold());
  },
};

/* ————————————————— shelf ————————————————— */

/* ————————————————— shelf ————————————————— */

const DEMO_FILES = [
  { name: 'Mountain Sunrise.png', art: `<svg viewBox="0 0 112 84"><defs><linearGradient id="f0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f59a4f"/><stop offset="1" stop-color="#d6477e"/></linearGradient></defs><rect width="112" height="84" fill="url(#f0)"/><circle cx="62" cy="36" r="11" fill="#ffe2d0"/><path d="M0 84 30 44l24 26 20-18 38 32Z" fill="#3a2350"/></svg>` },
  { name: 'Launch Plan.pdf', art: `<svg viewBox="0 0 112 84"><rect width="112" height="84" fill="#fff"/><g fill="#9aa2f0"><rect x="18" y="46" width="11" height="26" rx="2"/><rect x="35" y="34" width="11" height="38" rx="2"/><rect x="52" y="42" width="11" height="30" rx="2"/><rect x="69" y="18" width="11" height="54" rx="2" fill="#6f79e6"/><rect x="86" y="28" width="11" height="44" rx="2"/></g></svg>` },
  { name: 'Ocean Blue.png', art: `<svg viewBox="0 0 112 84"><defs><linearGradient id="f2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5fb4ea"/><stop offset="1" stop-color="#1c4fa8"/></linearGradient></defs><rect width="112" height="84" fill="url(#f2)"/></svg>` },
  { name: 'Wallpaper.heic', art: `<svg viewBox="0 0 112 84"><defs><radialGradient id="f3" cx=".35" cy=".45" r=".8"><stop offset="0" stop-color="#d77ea0"/><stop offset=".5" stop-color="#5a4f93"/><stop offset="1" stop-color="#1e2a55"/></radialGradient></defs><rect width="112" height="84" fill="url(#f3)"/></svg>` },
];
const shelf = {
  el: $('#shelf'), shown: 0, user: [],
  build() { for (const f of DEMO_FILES) this.el.append(this.tile(f.name, f.art)); },
  tile(name, art) {
    const el = document.createElement('div');
    el.className = 'tile';
    el.innerHTML = `<div class="thumb">${art}</div><p></p>`;
    $('p', el).textContent = name;
    return el;
  },
  show(n) {
    n = Math.max(0, Math.min(DEMO_FILES.length, n));
    if (n === this.shown) return;
    $$('.tile:not(.mine)', this.el).forEach((el, i) => el.classList.toggle('in', i < n));
    this.shown = n;
    this.refreshCount();
  },
  refreshCount() {
    const n = this.shown + this.user.length;
    this.el.classList.toggle('has-items', n > 0);
    $('.sh-count').textContent = t().items(n);
    $('.ns-files').textContent = n;
    $('[data-tab="files"]').classList.toggle('dot', n > 0);
  },
  addFiles(files) {
    for (const f of [...files].slice(0, 6)) {
      const el = this.tile(f.name, '<span class="ext"></span>');
      el.classList.add('mine');
      if (f.type.startsWith('image/')) {
        const img = document.createElement('img');
        img.alt = ''; img.src = URL.createObjectURL(f);
        $('.thumb', el).replaceChildren(img);
      } else $('.ext', el).textContent = (f.name.split('.').pop() || 'FILE').slice(0, 5).toUpperCase();
      this.el.prepend(el);
      requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add('in')));
      this.user.push(f.name);
    }
    this.refreshCount();
  },
  init() {
    this.build();
    const active = () => stage.chapter === 'files';
    addEventListener('dragover', e => { if (!active()) return; e.preventDefault(); this.el.classList.add('dragging'); });
    addEventListener('dragleave', e => { if (e.relatedTarget == null) this.el.classList.remove('dragging'); });
    addEventListener('drop', e => {
      if (!active()) return;
      e.preventDefault(); this.el.classList.remove('dragging');
      if (e.dataTransfer?.files?.length) this.addFiles(e.dataTransfer.files);
    });
    this.refreshCount();
  },
};

/* ————————————————— mirror: the instant camera ————————————————— */

const FILMS = ['nostalgia', 'bw', 'natural'];
const FILTER = { nostalgia: 'sepia(.38) saturate(1.35) contrast(1.06) brightness(1.06) hue-rotate(-10deg)', bw: 'grayscale(1) contrast(1.25) brightness(1.05)', natural: 'none' };
const PHOTO_W = 760, PHOTO_H = 324;              // the viewfinder's 380 × 162, at 2×
const CARD = { side: 0.06, bottom: 0.3, cream: '#f7f2e6' };  // PolaroidCard: borders per photo height
const mirror = {
  finder: $('.finder'), cv: $('.finder-cv'), video: $('.finder-video'), stream: null, active: false, shot: false, busy: false,
  film: 'nostalgia', timer: true, photo: null, taken: null, given: false,
  enter() {
    this.active = true; this.shot = false;
    if (!this.given) { const c = water.give(this.cv); water.post({ type: 'finder', canvas: c }, c === this.cv ? [] : [c]); this.given = true; }
    water.post({ type: 'finderView', rect: stage.finderRect() });
  },
  leave() { this.active = false; water.post({ type: 'finderView', rect: null }); this.stop(); },
  autoShoot() { if (!this.shot && !this.busy) { this.shot = true; this.shoot(); } },
  async shoot() {
    if (this.busy) return;
    this.busy = true; this.shot = true;
    this.finder.classList.add('busy');
    const count = $('.count', this.finder);
    if (this.timer && !reduced.matches) {
      for (const n of [3, 2, 1]) {
        count.textContent = n; count.classList.remove('tick'); void count.offsetWidth; count.classList.add('tick');
        await new Promise(r => setTimeout(r, 1000));
        if (!this.active) { this.busy = false; this.finder.classList.remove('busy'); return; }
      }
    }
    count.textContent = '';
    const photo = await this.capture();
    const flash = $('.flash', this.finder); flash.classList.remove('go'); void flash.offsetWidth; flash.classList.add('go');
    this.photo = photo; this.taken = new Date();
    this.fly(photo);
  },
  // What the viewfinder frames, with its film look: the camera if it is on, otherwise the water under the panel.
  async capture() {
    const c = document.createElement('canvas'); c.width = PHOTO_W; c.height = PHOTO_H;
    const ctx = c.getContext('2d');
    ctx.filter = FILTER[this.film];
    if (this.stream && this.video.videoWidth) {
      const vw = this.video.videoWidth, vh = this.video.videoHeight, sc = Math.max(PHOTO_W / vw, PHOTO_H / vh);
      ctx.translate(PHOTO_W, 0); ctx.scale(-1, 1);
      ctx.drawImage(this.video, (PHOTO_W - vw * sc) / 2, (PHOTO_H - vh * sc) / 2, vw * sc, vh * sc);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
    } else {
      const bitmap = await water.snapshot(stage.finderRect(), [PHOTO_W, PHOTO_H]);
      if (bitmap) { ctx.drawImage(bitmap, 0, 0); bitmap.close?.(); }
    }
    ctx.filter = 'none';
    if (this.film === 'bw') {
      const g = ctx.createRadialGradient(PHOTO_W / 2, PHOTO_H / 2, PHOTO_H * 0.4, PHOTO_W / 2, PHOTO_H / 2, PHOTO_W * 0.62);
      g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,.5)');
      ctx.fillStyle = g; ctx.fillRect(0, 0, PHOTO_W, PHOTO_H);
    }
    return c;
  },
  // The flash, a beat on the full picture, then it shrinks into the corner as its cream frame grows.
  fly(photo) {
    const fly = $('.f-fly', this.finder), thumb = $('.f-thumb', this.finder);
    $('canvas', fly).getContext('2d').drawImage(photo, 0, 0);
    fly.classList.remove('landed'); fly.classList.add('on');
    thumb.hidden = true;
    setTimeout(() => fly.classList.add('landed'), reduced.matches ? 0 : 300);
    setTimeout(() => {
      this.card($('canvas', thumb), 256);
      thumb.hidden = false; fly.classList.remove('on', 'landed');
      this.busy = false; this.finder.classList.remove('busy');
    }, reduced.matches ? 0 : 950);
  },
  // The Polaroid, as the app saves it: the photo exactly as framed, cream borders, the stamp and the handwritten date.
  card(canvas, width) {
    const aspect = PHOTO_W / PHOTO_H, ph = width / (aspect + 2 * CARD.side), pw = ph * aspect;
    const height = Math.round(ph * (1 + CARD.side + CARD.bottom));
    canvas.width = width; canvas.height = height;
    const ctx = canvas.getContext('2d'), x = ph * CARD.side, y = ph * CARD.side;
    ctx.fillStyle = CARD.cream; ctx.fillRect(0, 0, width, height);
    ctx.drawImage(this.photo, x, y, pw, ph);
    const d = this.taken;
    ctx.save();
    ctx.font = `600 ${ph * 0.068}px ui-monospace, "SF Mono", "JetBrains Mono", monospace`; ctx.textAlign = 'right'; ctx.textBaseline = 'alphabetic';
    ctx.shadowColor = 'rgba(255,102,13,.9)'; ctx.shadowBlur = ph * 0.012 * 2; ctx.fillStyle = '#ff8f29';
    ctx.fillText(stamp(d), x + pw - ph * 0.06, y + ph - ph * 0.06);
    ctx.restore();
    ctx.font = `700 ${ph * 0.11}px "Bradley Hand", "Segoe Script", cursive`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillStyle = 'rgba(48,56,87,.85)';
    const caption = d.toLocaleDateString(lang === 'tr' ? 'tr-TR' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric' })
      + ' · ' + d.toLocaleTimeString(lang === 'tr' ? 'tr-TR' : 'en-GB', { hour: '2-digit', minute: '2-digit' });
    ctx.fillText(caption, width / 2, y + ph + (height - y - ph) / 2);
    return canvas;
  },
  save() {
    if (!this.photo) return;
    const c = this.card(document.createElement('canvas'), 1600);
    c.toBlob(b => {
      if (!b) return;
      const a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = `damla-ayna-${Date.now()}.png`;
      document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    }, 'image/png');
  },
  async camera() {
    const btn = $('.cam-try');
    if (this.stream) { this.stop(); return; }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { width: 1280, height: 720 }, audio: false });
      this.video.srcObject = this.stream; await this.video.play();
      this.finder.classList.add('live'); btn.textContent = t().camStop;
      if (stage.chapter !== 'mirror') stage.scrollToChapter('mirror');
    } catch {
      this.stream = null; btn.textContent = t().camDenied;
    }
  },
  stop() {
    if (this.stream) for (const tr of this.stream.getTracks()) tr.stop();
    this.stream = null; this.video.srcObject = null;
    this.finder.classList.remove('live');
    const btn = $('.cam-try'); if (btn) btn.textContent = t().camTry;
  },
  relabel() {
    $('.f-film').textContent = t().films[this.film];
    $('.shutter').setAttribute('aria-label', t().shoot(this.timer));
  },
  init() {
    $('.f-stamp').textContent = stamp(new Date());
    $('.film-btn').addEventListener('click', () => {
      this.film = FILMS[(FILMS.indexOf(this.film) + 1) % FILMS.length];
      this.finder.dataset.film = this.film; this.relabel();
    });
    $('.timer-btn').addEventListener('click', e => {
      this.timer = !this.timer;
      e.currentTarget.classList.toggle('on', this.timer); e.currentTarget.setAttribute('aria-pressed', String(this.timer)); this.relabel();
    });
    $('.f-stage').addEventListener('click', e => { const on = e.currentTarget.classList.toggle('on'); e.currentTarget.setAttribute('aria-pressed', String(on)); });
    $('.shutter').addEventListener('click', () => this.shoot());
    $('.f-thumb').addEventListener('click', () => this.save());
    $('.cam-try').addEventListener('click', () => this.camera());
    document.addEventListener('visibilitychange', () => { if (document.hidden) this.stop(); });
  },
};
// "’26 10 1", the way film cameras printed the date.
function stamp(d) { return `’${String(d.getFullYear() % 100).padStart(2, '0')} ${d.getMonth() + 1} ${d.getDate()}`; }

/* ————————————————— the stage ————————————————— */

const CHAPTERS = [
  { id: 'agents', from: 0.04, to: 0.3, tab: 'agents', mode: 'agents' },
  { id: 'notif', from: 0.3, to: 0.5, tab: 'notif', mode: 'notif' },
  { id: 'music', from: 0.5, to: 0.68, tab: 'music', mode: 'music' },
  { id: 'files', from: 0.68, to: 0.82, tab: 'files', mode: 'files' },
  { id: 'mirror', from: 0.82, to: 0.96, tab: 'mirror', mode: 'brand' },
];
const PANEL_H = 218, LYRICS_H = 330, CARD_H = 116, REPLY_H = 152, PILL = 8 + 36;
const stage = {
  el: $('#stage'), wrap: $('.panel-wrap'), panel: $('#panel'), notch: $('#notch'),
  chapter: null, t: 0, top: 0, height: 0, vh: innerHeight, ps: 1, lyricsH: LYRICS_H, lyrics: false,
  // The panel takes the room the chapter text leaves it, so the two never overlap at any size.
  measure() {
    const r = this.el.getBoundingClientRect();
    this.top = r.top + scrollY; this.height = this.el.offsetHeight; this.vh = innerHeight;
    const vw = document.documentElement.clientWidth;
    document.body.classList.remove('tight');
    for (let pass = 0; pass < 2; pass++) {
      let text = 0;
      for (const a of $$('.chapter')) text = Math.max(text, a.offsetHeight);
      const room = this.vh - text - (vw < 720 ? 10 : 22);
      this.ps = Math.min(1.6, (vw - 24) / 392, room / (PANEL_H + PILL));
      this.lyricsH = clamp(room / Math.max(this.ps, 0.01) - PILL, PANEL_H, LYRICS_H);
      // Very short windows: drop the fine print so the panel keeps a readable size.
      if (this.ps >= 0.72 || pass) break;
      document.body.classList.add('tight');
    }
    this.ps = Math.max(0.5, this.ps);
    setVar(this.wrap, '--ps', this.ps.toFixed(3));
  },
  // Where the viewfinder looks: straight through the panel at the water behind it.
  finderRect() {
    const w = 380 * this.ps, h = 162 * this.ps;
    return [Math.round((water.w - w) / 2), Math.round(38 * this.ps), Math.round(w), Math.round(h)];
  },
  pageHeight() {
    const page = this.panel.dataset.page;
    if (page === 'music' && this.lyrics) return this.lyricsH;
    if (page === 'notif') return notes.view === 'card' ? CARD_H : notes.view === 'reply' ? REPLY_H : PANEL_H;
    return PANEL_H;
  },
  // Shape of the panel for the page on show: the notification card drops from the notch without the pill.
  layout() {
    const card = this.panel.dataset.page === 'notif' && notes.view !== 'list';
    this.panel.classList.toggle('as-card', card);
    this.wrap.classList.toggle('no-pill', card);
    setVar(this.panel, '--page-h', `${this.pageHeight()}px`);
  },
  update() {
    const span = this.height - this.vh;
    const t = span > 0 ? clamp((scrollY - this.top) / span) : 0;
    this.t = t;
    const inStage = scrollY >= this.top - this.vh * 0.2 && scrollY <= this.top + span + this.vh * 0.2;
    let open = t < 0.04 ? t / 0.04 : t > 0.96 ? (1 - t) / 0.04 : 1;
    if (scrollY < this.top) open = 0;
    open = reduced.matches ? (open > 0.01 ? 1 : 0) : 1 - Math.pow(1 - clamp(open), 3);
    const content = clamp((open - 0.55) / 0.45);
    const ch = CHAPTERS.find(c => t >= c.from && t < c.to) || (t >= 0.96 ? CHAPTERS[CHAPTERS.length - 1] : CHAPTERS[0]);
    const sub = clamp((t - ch.from) / (ch.to - ch.from));
    const active = inStage && open > 0.5 ? ch.id : null;

    if (active !== this.chapter) this.enter(active);
    // Golden Hour, then Paper Lanterns, then Ferry at Dusk, whose lyrics roll in the last stretch
    if (ch.id === 'music' && active && performance.now() - music.byHand > 2500) music.set(sub < 0.2 ? 0 : sub < 0.4 ? 2 : 1, true);
    this.lyrics = ch.id === 'music' && music.lyricsOn(sub);
    if (this.panel.classList.contains('lyrics-on') !== this.lyrics) {
      this.panel.classList.toggle('lyrics-on', this.lyrics);
      $('.lyrics-btn').setAttribute('aria-pressed', String(this.lyrics));
    }
    if (ch.id === 'agents' && active && !agents.forceList) { const v = sub < 0.34 ? 'list' : sub < 0.68 ? 'ask' : 'q'; if (agents.page.dataset.view !== v) agents.page.dataset.view = v; }
    if (ch.id === 'notif' && active) notes.follow(sub);
    if (ch.id === 'music' && active) music.scrollLyrics(sub);
    if (ch.id === 'files' && active) shelf.show(Math.floor((sub - 0.08) * 6));
    if (ch.id === 'mirror' && active && sub > 0.18) mirror.autoShoot();

    setVar(this.panel, '--open', open.toFixed(3));
    setVar(this.panel, '--content', content.toFixed(3));
    setVar(this.wrap, '--content', content.toFixed(3));
    setVar(this.wrap, 'visibility', open > 0.001 ? 'visible' : 'hidden');
    this.layout();
    const mode = active ? ch.mode : 'brand';
    if (this.notch.dataset.mode !== mode) this.notch.dataset.mode = mode;
  },
  enter(id) {
    const prev = this.chapter;
    this.chapter = id;
    if (id) this.panel.dataset.page = id;
    const ch = CHAPTERS.find(c => c.id === id);
    for (const s of $$('.tabbar span[data-tab]')) s.classList.toggle('on', !!ch && s.dataset.tab === ch.tab);
    for (const a of $$('.chapter')) a.classList.toggle('on', a.dataset.chapter === id);
    if (prev === 'agents' && id !== 'agents') agents.reset();
    if (prev === 'notif' && id !== 'notif') notes.reset();
    if (prev === 'mirror' && id !== 'mirror') mirror.leave();
    if (id === 'mirror') mirror.enter();
    this.notchMascot();
  },
  notchMascot() {
    const m = $('.notch .mascot');
    if (!m) return;
    m.dataset.phase = this.chapter === 'agents' ? $('.session.waiting .mascot').dataset.phase : this.chapter === 'music' ? 'working' : 'idle';
  },
  scrollToChapter(id) {
    const ch = CHAPTERS.find(c => c.id === id) || CHAPTERS[0];
    const y = this.top + (this.height - this.vh) * (ch.from + 0.02);
    scrollTo({ top: y, behavior: reduced.matches ? 'auto' : 'smooth' });
  },
};

/* ————————————————— scrolling combs the water ————————————————— */

// Once per frame, however many scroll events arrive: the stage follows and the water is combed by the distance.
let lastY = scrollY, scrollQueued = false;
function onScroll() {
  if (scrollQueued) return;
  scrollQueued = true;
  requestAnimationFrame(() => {
    scrollQueued = false;
    const y = scrollY, dy = y - lastY; lastY = y;
    stage.update();
    if (!trayLive || reduced.matches || !dy) return;
    // A jump (a menu link, the scrollbar) combs like a fast scroll, not a tear through the water.
    water.post({ type: 'comb', dy: clamp(dy, -90, 90), hero: y < innerHeight });
  });
}

/* ————————————————— the notch menu ————————————————— */

function notchMenu() {
  const notch = $('#notch'), btn = $('#notch-toggle');
  let timer;
  const set = open => { notch.dataset.open = String(open); btn.setAttribute('aria-expanded', String(open)); };
  const hover = matchMedia('(hover: hover)');
  notch.addEventListener('pointerenter', () => { if (!hover.matches) return; clearTimeout(timer); timer = setTimeout(() => set(true), 60); });
  notch.addEventListener('pointerleave', () => { if (!hover.matches) return; clearTimeout(timer); timer = setTimeout(() => set(false), 260); });
  btn.addEventListener('click', () => set(notch.dataset.open !== 'true'));
  notch.addEventListener('focusout', e => { if (!notch.contains(e.relatedTarget)) set(false); });
  addEventListener('keydown', e => { if (e.key === 'Escape' && notch.dataset.open === 'true') { set(false); btn.focus(); } });
  document.addEventListener('pointerdown', e => { if (!notch.contains(e.target)) set(false); });
  const inStage = { stage: 'agents', notifications: 'notif', music: 'music' };
  for (const a of $$('.notch-menu a')) a.addEventListener('click', e => {
    const id = a.getAttribute('href').slice(1);
    set(false);
    if (inStage[id]) { e.preventDefault(); stage.scrollToChapter(inStage[id]); }
  });
  for (const b of $$('.lang button')) b.addEventListener('click', () => setLang(b.dataset.lang));
}

/* ————————————————— pattern book ————————————————— */

function fitVignettes() {
  for (const v of $$('.vig')) {
    const sheet = v.parentElement, w = parseFloat(getComputedStyle(v).getPropertyValue('--w')) || 300;
    const vs = Math.min(1.55, (sheet.clientWidth * 0.84) / w, (sheet.clientHeight * 0.84) / (v.offsetHeight || 1));
    v.style.setProperty('--vs', vs.toFixed(3));
  }
}
// Each sheet is marbled once, by the engine, a little before it scrolls into view.
function swatches() {
  const io = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      io.unobserve(e.target);
      const li = e.target, colors = li.dataset.colors.split(','), cv = $('canvas', li);
      const w = cv.clientWidth, h = cv.clientHeight;
      const c = water.give(cv);
      water.post({ type: 'swatch', canvas: c, w, h, dpr: devicePixelRatio || 1, pattern: li.dataset.pattern, colors, seed: li.dataset.pattern.length * 97 + colors[0].charCodeAt(2) }, c === cv ? [] : [c]);
    }
  }, { rootMargin: '900px 0px' });
  for (const li of $$('.swatches li')) io.observe(li);
}

/* ————————————————— the print ————————————————— */

function print() {
  const out = $('#print'), ctx = out.getContext('2d');
  const W = out.width, H = out.height;
  const draw = async () => {
    // the middle of the tray, in the print's 3:2
    const w = Math.min(water.w, water.h * 1.5), h = w / 1.5;
    const bitmap = await water.snapshot([(water.w - w) / 2, Math.max(0, (water.h - h) * 0.35), w, h], [W, H]);
    if (!bitmap) return;
    ctx.drawImage(bitmap, 0, 0); bitmap.close?.();
    ctx.fillStyle = 'rgba(22,25,31,.5)';
    ctx.font = '800 22px "Nunito", sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText('damla · ebru', W - 28, H - 26);
  };
  const io = new IntersectionObserver(es => { if (es.some(e => e.isIntersecting)) draw(); }, { rootMargin: '300px 0px' });
  io.observe($('#sheet'));
  $('#save-print').addEventListener('click', async () => {
    await draw();
    out.toBlob(blob => {
      if (!blob) return;
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = 'damla-ebru.png';
      document.body.append(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    }, 'image/png');
  });
}

/* ————————————————— small things ————————————————— */

function copyButtons() {
  for (const b of $$('.copy')) b.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy); } catch { return; }
    const label = $('span', b);
    b.classList.add('done'); label.textContent = t().copied;
    setTimeout(() => { b.classList.remove('done'); label.textContent = lang === 'tr' ? TR.copy : EN.copy; }, 1800);
  });
}

async function latestRelease() {
  try {
    // The newest release, from this site's own worker (the dmg button already points at /download/latest).
    const r = await fetch('/latest.json');
    if (!r.ok) return;
    const { version } = await r.json();
    if (version) for (const s of $$('.version')) s.textContent = `v${version}`;
  } catch { /* offline or opened from disk: the button still works */ }
}

function trayVisibility() {
  const seen = new Set();
  const io = new IntersectionObserver(es => {
    for (const e of es) e.isIntersecting ? seen.add(e.target) : seen.delete(e.target);
    const was = trayLive;
    trayLive = seen.size > 0;
    water.canvas.style.visibility = trayLive ? 'visible' : 'hidden';
    if (trayLive !== was) water.post({ type: 'live', on: trayLive });
  });
  io.observe($('.hero')); io.observe(stage.el);
}

/* ————————————————— go ————————————————— */

captureEnglish();
drawMascots();
music.init();
agents.init();
notes.init();
mirror.init();
shelf.init();
notchMenu();
copyButtons();
stylusOnWater();
window.__damla = { water, stage, music, agents, notes, mirror };

const saved = store.get('damla.lang');
setLang(saved || ((navigator.language || '').toLowerCase().startsWith('tr') ? 'tr' : 'en'));

water.start();
water.post({ type: 'seed', tones: ['#e6dfd1', '#f1ece2', '#e2dac9', '#ede7dc', '#ddd4c2', '#efe9de'] });
stage.measure();
stage.update();
trayVisibility();
swatches();
print();

addEventListener('scroll', onScroll, { passive: true });
let resizeTimer;
addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    water.w = document.documentElement.clientWidth; water.h = innerHeight;
    water.post({ type: 'resize', w: water.w, h: water.h, dpr: devicePixelRatio || 1 });
    stage.measure(); stage.update(); fitVignettes();
    if (mirror.active) water.post({ type: 'finderView', rect: stage.finderRect() });
  }, 120);
});
(document.fonts?.ready || Promise.resolve()).then(() => { fitVignettes(); stage.measure(); stage.update(); heroSequence(); });
latestRelease();

let lastTick = performance.now();
setInterval(() => {
  const now = performance.now();
  if (stage.chapter === 'music') music.tick((now - lastTick) / 1000);
  lastTick = now;
}, 500);
