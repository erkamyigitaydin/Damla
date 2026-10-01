import { Tray, patterns, rng } from './ebru.js';

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const store = {
  get(k) { try { return localStorage.getItem(k); } catch { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
};

const PIG = { coral: '#f4a18b', saffron: '#ffcc5c', mint: '#cce3ff', pale: '#f3f6fa', sea: '#8fb3e6', indigo: '#6d7fd6', rose: '#d98aa0', teal: '#3a5a8a', bone: '#ece9e2', deep: '#162236', night: '#111a27' };

/* ————————————————— language ————————————————— */

const TR = {
  'v.tour.t': 'Damla’ya hoş geldin', 'v.tour.d': 'Çentikte yaşar. İmleci çentiğe getir ya da ⌃⌥Space’e bas.', 'v.skip': 'Geç', 'v.next': 'İleri',
  'v.muted': 'Mikrofon kapalı', 'v.pods': 'S %80 · Sa %75 · K %60',
  'v.sc.hint': 'Sık kullandıklarını sabitle; burada tek dokunuşluk düğme olurlar.', 'v.sc.1': 'Web için yeniden boyutla', 'v.sc.2': 'Toplantı notu başlat', 'v.sc.3': 'İndirilenleri topla',
  'v.srv': 'Yerel sunucular · 3', 'v.stop': 'Durdur', 'v.search': 'Ara', 'v.link': 'Bağlantı', 'v.text': 'Metin', 'v.color': 'Renk',
  'v.clip.text': 'Fatura #2041 gönderildi. Cuma hatırlat.',
  'book.lede': "Damla'nın sessiz işleri, her biri tarayıcında canlı çizilen bir ebru kâğıdının üstünde. Ebru ustaları desenlerine ad verir; adları her birinin altında.",
  'np.in': '8 dk', 'np.meeting': 'Tasarım incelemesi', 'np.speakers': 'Hoparlör',
  'ag.summary': '1 çalışıyor · 1 bekliyor', 'ag.5h': '5 saat', 'ag.week': '7 gün',
  'ag.wants': 'komut çalıştırmak istiyor', 'ag.always': 'Hep izin ver', 'ag.asks': 'bir şey soruyor', 'ag.terminal': 'Terminalde yanıtla',
  'ag.editing': 'Dosya düzenliyor · 4 dk · 31 çağrı', 'ag.q3t': 'İkisi de',
  'cam.empty': 'Çektiklerin burada birikir', 'cam.folder': 'Klasör',
  'snd.volume': 'Ses seviyesi', 'snd.system': 'Sistem', 'snd.mbp': 'MacBook Pro Hoparlörü',
  'skip': 'İçeriğe geç', 'menu': 'Menü',
  'nav.features': 'Özellikler', 'nav.agents': 'Ajanlar', 'nav.more': 'Küçük şeyler', 'nav.privacy': 'Gizlilik', 'nav.install': 'Kur',
  'hero.title': 'Çentik sonunda bir işe yarıyor.',
  'hero.lede': 'Müzik, ses, dosyalar, pano, odak ve yapay zekâ kodlama ajanların; hepsi ekranının tepesinde, bir bakış uzağında. Çentiğin üstüne gel, panel içinden süzülsün; uzaklaş, geri çekilsin.',
  'copy': 'Kopyala', 'download': 'Mac için indir',
  'req': 'macOS 26 ve sonrası · Apple Silicon ve Intel · Ücretsiz',
  'hero.hint': 'Suya tıkla, bir damla bırak. Sürükle, tara.',
  'ag.why': "Staging'deki bekleyen veritabanı göçlerini çalıştır",
  'ag.goto': "Visual Studio Code'a git",
  'ag.deny': 'Reddet', 'ag.allow': 'İzin ver',
  'sh.drop': 'Dosyaları buraya bırak',
  'snd.output': 'Ses çıkışı', 'snd.case': 'Kutu', 'snd.mixer': 'Uygulama başına ses',
  'music.title': 'Ne çalıyorsa, burada.',
  'music.body': 'Apple Music, Spotify, Podcasts, tarayıcıda YouTube: ne çalıyorsa Damla gösterir. Kapak, ilerleme, oynat ve atla, Apple Music favorilerin için de bir kalp.',
  'music.p1': '<b>Renkler kapaktan.</b> Tüm panel dinlediğin albümün rengini alır. Şarkıyı atla, değişimi izle.',
  'music.p2': '<b>Şarkıyla akan sözler.</b> Panel aşağı uzar, sözler Apple Music tarzında akar.',
  'music.p3': '<b>Her oynatıcı ve akıllı devir.</b> Çalan uygulamalar arasında tek dokunuşla geç. Bir video başlat, müziğin durur; durdur, müzik geri gelir.',
  'music.p4': "<b>Video çentikte.</b> Chrome, Brave, Edge ya da Vivaldi'de bir şey mi oynuyor? Tek dokunuşla çentiğin altında oynamaya devam eder; tarayıcı arka planda olsa da.",
  'ag.q': 'Ana başlıkta hangi yazı tipi olsun?',
  'ag.q1': 'Yeni logoyla uyumlu', 'ag.q2': 'Yerel, indirme yok',   'cam.nostalgia': 'Nostalji', 'cam.bw': 'Siyah beyaz', 'cam.natural': 'Doğal', 'cam.countdown': '3-2-1 geri sayım', 'cam.center': 'Ana Sahne',
  'mirror.title': 'Çentikte bir anlık fotoğraf makinesi.',
  'mirror.body': "Ayna, görüşmeden önce saçına bakmanı sağlar, sonra küçük bir anlık fotoğraf makinesine dönüşür: filmini seç, 3-2-1 say; tarih damgalı bir kart çentikten basılıp banyo olur. Resimler › Damla'ya kaydedilir.",
  'mirror.p1': '<b>Üç film.</b> Nostalji, siyah beyaz ve doğal. Ana Sahne seni kadrajda tutar.',
  'mirror.try': 'Kendi kameranla dene',
  'mirror.slip': 'Kamera yalnızca bu sayfa açıkken çalışır. Burada çektiğin fotoğraf tarayıcından çıkmaz.',
  'agents.title': 'Yapay zekâ ajanların, bir bakışta.',
  'agents.body': 'Arka planda Claude Code ya da Codex mi çalışıyor? Damla her oturumu gösterir: hangi proje çalışıyor, hangisi seni bekliyor, ne zamandır bekliyor. Biri izin istediğinde soru, tam komutuyla birlikte çentikten süzülür.',
  'agents.p1': "<b>İzin ver, Reddet ya da Hep izin ver</b>; Claude Code ve Codex CLI için, pencere değiştirmeden. Ya da <kbd>⌃⌥↩</kbd> ve <kbd>⌃⌥⌫</kbd>. Paneldekini dene.",
  'agents.p4': '<b>Sorularını yanıtla.</b> Claude Code senden seçenekler arasında seçim isteyince seçimi doğrudan çentikte yaparsın.',
  'agents.p2': '<b>Her şeyi canlandıran bir damla.</b> Ajan çalışırken zıplar, seni beklerken el sallar, iş bitince gülümser.',
  'agents.p3': '<b>Bağlam ve limitler.</b> Her oturumun bağlamı ne kadar dolu, beş saatlik ve haftalık kullanımın ne durumda; %80 ve %95’te uyarı.',
  'agents.slip': 'Kancalar yalnızca durumu kaydeder: aşama, araç adı, süre. İstemlerin, konuşmaların ve çıktıların asla okunmaz.',
  'files.title': 'Dosyaların için bir raf.',
  'files.body': 'Herhangi bir yerde bir dosyayı sürüklemeye başla, çentik bir bırakma alanına dönüşsün. Dosyaları orada beklet, Boşluk ile önizle, başka bir uygulamaya sürükle ya da AirDrop ile gönder. Yeni ekran görüntüleri rafa kendiliğinden düşer.',
  'files.p1': "<b>Dönüştür ve küçült.</b> Bir görseli PNG, JPEG ya da HEIC olarak kaydet, sıkıştır ya da raftaki PDF'leri tek dosyada birleştir.",
  'files.p2': "<b>Burada dene.</b> Mac'inden bu sayfaya bir dosya bırak. Tarayıcından dışarı çıkmaz.",
  'files.slip': 'Damla yalnızca dosyalarının nerede olduğunu hatırlar. Onları asla taşımaz ya da değiştirmez.',
  'sound.title': 'Ses, senin ayarınla.',
  'sound.body': "Çıkışı tek dokunuşla değiştir, AirPods'unun her kulaklığının ve kutusunun şarjını gör, her uygulamaya kendi ses seviyesini ver.",
  'sound.p1': "<b>Çentikte kaydır</b>, sesi değiştir ya da parçayı atla; sistemin yerine Damla'nın kendi ses ve parlaklık göstergelerini gör.",
  'sound.p2': '<b>Sesini kıs.</b> Tek hamlede her şeyi kısar; AirPods bağlandığı an şarjını gösterir.',
  'sound.slip': 'Uygulama başına ses, Sistem Sesi Kaydı iznini kullanır. Hiçbir şey kaydedilmez, hiçbir yere gönderilmez.',
  'book.title': 'Ve küçük şeyler.',
  'b.tour.t': 'Çentiğin içinde bir tanıtım', 'b.tour.d': 'İlk açılışta Damla’yı özellik özellik, tam yaşadığı yerde gezdirir; her izni yalnızca sırası gelince ister.',
  'b.mic.t': 'Mikrofon kullanımda mı?', 'b.mic.d': 'Görüşme sırasında çentik bunu gösterir; tek dokunuşla tüm uygulamalar için sessize alırsın.',
  'b.swipe.t': 'Sayfalar arasında kaydır', 'b.swipe.d': 'İzleme dörtgeninde iki parmak; sayfa parmağını takip eder. Kapatınca panel çentiğe geri çekilir.',
  'b.shortcuts.t': 'Kestirmeler', 'b.shortcuts.d': 'Kestirmeler uygulamasında yaptığın her şey, tek dokunuşluk bir düğme olarak.',
  'b.battery.t': 'Düşük pil uyarıları', 'b.battery.d': 'Fare, klavye, izleme dörtgeni ve AirPods için; cümlenin ortasında kapanmadan önce.',
  'b.servers.t': 'Yerel sunucular', 'b.servers.d': "Mac'inde çalışan her geliştirme sunucusu ve veritabanı; açmak ya da durdurmak tek tık.",
  'b.clip.t': 'Pano geçmişi', 'b.clip.d': 'Kopyaladıklarını ara ve sabitle. Sen açana kadar kapalı.',
  'b.focus.t': 'Kadran gibi çevrilen odak zamanlayıcı', 'b.focus.d': 'Halkayı çevir, bir sayı yaz ya da kaydır; istediğin süre. Geri sayım doğrudan çentikte.',
  'book.also': '<b>Ayrıca:</b> panelde hangi sayfaların görüneceğini sen seçersin · çentiği olmayan ekranlarda menü çubuğuna çizilen bir çentik · tam ekran uygulamalarda menü çubuğuyla birlikte gizlenir · temizlik modu, silebilmen için klavyeyi 60 saniye kilitler · müzik ve ajanlar çalışırken bile işlemciyi yormaz · İngilizce ve Türkçe.',
  'pv.l1': 'Hesap yok.', 'pv.l2': 'Sunucu yok.', 'pv.l3': 'Takip yok.',
  'pv.body': "Her şey Mac'inde kalır. Rafın, pano geçmişin ve zamanlayıcın <code>~/Library/Application Support/Damla/</code> içinde durur; şu an çalan bilgisi macOS'tan yerel olarak okunur.",
  'pv.net': "Ağa yalnızca iki şey dokunur: açarsan şarkı sözleri (şarkı adı, sanatçı, albüm ve süre lrclib.net'e gider) ve günlük güncelleme denetimi.",
  'pv.perms': 'Her izin isteğe bağlı',
  'pv.auto': 'Otomasyon', 'pv.auto.d': "Apple Music ve Spotify'ı arka planda yönetmek",
  'pv.ax': 'Erişilebilirlik', 'pv.ax.d': "Damla'nın kendi ses ve parlaklık göstergeleri, temizlik modu",
  'pv.audio': 'Sistem sesi kaydı', 'pv.audio.d': 'Uygulama başına ses. Hiçbir şey kaydedilmez',
  'pv.cal': 'Takvimler', 'pv.cal.d': 'Sıradaki toplantın, sen açınca',
  'pv.cam': 'Kamera', 'pv.cam.d': 'Ayna sayfası, yalnızca açıkken',
  'print.caption': 'Aşağı inerken taradığın desen.', 'print.alt': 'Mermer desenli bir ebru',
  'fin.title': 'Her kaydırma başka bir ebru yapar. Bu seninki.',
  'print.save': 'Ebrunu kaydet',
  'fin.signed': 'Apple tarafından imzalanmış ve onaylanmış; uyarı vermeden açılır ve kendini güncel tutar.',
  'keys.open': '<b>Aç</b><span>çentiğin üstüne gel, menü çubuğundaki damlaya tıkla ya da <kbd>⌃</kbd><kbd>⌥</kbd><kbd>Boşluk</kbd></span>',
  'keys.close': '<b>Kapat</b><span>uzaklaş, çentiğe tıkla ya da <kbd>Esc</kbd></span>',
  'keys.settings': '<b>Ayarlar</b><span>dişli, menü çubuğu simgesi ya da <kbd>⌘</kbd><kbd>,</kbd></span>',
  'foot.releases': 'Sürüm notları', 'foot.issues': 'Sorun bildir',
  'foot.note': 'Erkam Yiğit Aydın yaptı. Bu sayfadaki ebru tarayıcında canlı çiziliyor; hiçbir şey takip edilmiyor.',
};

// Strings the script writes itself, in both languages.
const DYN = {
  en: {
    title: 'Damla · your notch, finally doing something',
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
    camTry: 'Try it with your camera', camStop: 'Stop the camera', camDenied: 'No camera access, so the water poses instead.',
    printNote: 'Click to save', photos: n => `${n} ${n === 1 ? 'photo' : 'photos'}`,
    films: { nostalgia: 'Nostalgia', bw: 'Black & white', natural: 'Natural' },
  },
  tr: {
    title: 'Damla · çentik sonunda bir işe yarıyor',
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
    camTry: 'Kendi kameranla dene', camStop: 'Kamerayı kapat', camDenied: 'Kamera izni yok; o yüzden su poz veriyor.',
    printNote: 'Kaydetmek için tıkla', photos: n => `${n} fotoğraf`,
    films: { nostalgia: 'Nostalji', bw: 'Siyah beyaz', natural: 'Doğal' },
  },
};

const EN = {};
let lang = 'en';
function captureEnglish() {
  for (const el of $$('[data-i18n]')) EN[el.dataset.i18n] = el.textContent;
  for (const el of $$('[data-i18n-html]')) EN[el.dataset.i18nHtml] = el.innerHTML;
  for (const el of $$('[data-i18n-aria]')) EN[el.dataset.i18nAria] = el.getAttribute('aria-label');
}
function setLang(next) {
  lang = next === 'tr' ? 'tr' : 'en';
  const dict = lang === 'tr' ? TR : EN;
  document.documentElement.lang = lang;
  for (const el of $$('[data-i18n]')) { const v = dict[el.dataset.i18n] ?? EN[el.dataset.i18n]; if (v != null) el.textContent = v; }
  for (const el of $$('[data-i18n-html]')) { const v = dict[el.dataset.i18nHtml] ?? EN[el.dataset.i18nHtml]; if (v != null) el.innerHTML = v; }
  for (const el of $$('[data-i18n-aria]')) { const v = dict[el.dataset.i18nAria] ?? EN[el.dataset.i18nAria]; if (v != null) el.setAttribute('aria-label', v); }
  for (const b of $$('.lang button')) b.setAttribute('aria-pressed', String(b.dataset.lang === lang));
  document.title = DYN[lang].title;
  store.set('damla.lang', lang);
  agents.refresh(); shelf.refreshCount();
}
const t = () => DYN[lang];

/* ————————————————— the droplet ————————————————— */

const MASCOT = `<g class="m-body"><path class="m-drop" d="M50 2C102 50 96 98 50 98C4 98-2 50 50 2Z" stroke="rgba(255,255,255,.35)" stroke-width="2.5"/><path d="M50 2C102 50 96 98 50 98C4 98-2 50 50 2Z" fill="url(#m-shade)"/><ellipse cx="33" cy="52" rx="6.5" ry="10" transform="rotate(-25 33 52)" fill="rgba(255,255,255,.55)"/><g class="m-eyes"><ellipse class="m-eye" cx="37.5" cy="66" rx="5.5" ry="6.9"/><ellipse class="m-eye" cx="62.5" cy="66" rx="5.5" ry="6.9"/></g><path class="m-smile" d="M42 81Q50 87 58 81"/><ellipse class="m-o" cx="50" cy="83" rx="4" ry="5"/><g class="m-happy"><path d="M29 70Q36 59 43 70M57 70Q64 59 71 70"/><path d="M39 80Q50 93 61 80"/></g><path class="m-spark" d="M90 6l3.2 8.8 8.8 3.2-8.8 3.2L90 30l-3.2-8.8L78 18l8.8-3.2Z"/></g><g class="m-hand"><path d="M96 58c-5 0-8-4-8-9V35c0-2 3-2 3 0v8V26c0-2.4 3.4-2.4 3.4 0v15V23c0-2.4 3.4-2.4 3.4 0v18V26c0-2.4 3.4-2.4 3.4 0v17-5c0-2.2 3.2-2.2 3.2 0v8c0 7-4 12-8.4 12Z"/></g>`;
function drawMascots() {
  const defs = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  defs.setAttribute('width', '0'); defs.setAttribute('height', '0'); defs.setAttribute('aria-hidden', 'true');
  defs.style.position = 'absolute';
  defs.innerHTML = '<defs><linearGradient id="m-shade" x1="0" y1="0" x2="0" y2="1"><stop offset=".35" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".28"/></linearGradient></defs>';
  document.body.append(defs);
  for (const svg of $$('svg.mascot')) svg.innerHTML = MASCOT;
}

/* ————————————————— the tray ————————————————— */

const canvas = $('#tray');
const tray = new Tray(canvas, { ground: PIG.night });
window.__damla = { tray };
let trayLive = true;          // hero or stage on screen
let looping = false, last = 0;

function kick() {
  if (looping) return;
  looping = true; last = performance.now();
  requestAnimationFrame(frame);
}
function frame(now) {
  if (document.hidden) { looping = false; return; }
  const dt = Math.min(48, now - last); last = now;
  const moved = tray.step(dt);
  if (moved || tray.dirty) { tray.refine(); if (trayLive) tray.render(); }
  if (tray.busy || tray.dirty) requestAnimationFrame(frame);
  else looping = false;
}

// A drop falls out of the notch (or the panel) and blooms where it lands.
function drip(fromX, fromY, toX, toY, r, color, delay = 0) {
  if (reduced.matches) { tray.drop(toX, toY, r, color); kick(); return; }
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
    anim.onfinish = () => { el.remove(); tray.bloom(toX, toY, r, color, 700 + r * 4); kick(); };
  }, delay);
}

function seedGround() {
  const r = rng(7), { w, h } = tray;
  const tones = ['#1b2a40', PIG.deep, PIG.night, '#0f1622', '#223350', '#141d2c'];
  for (let i = 0; i < 24; i++) tray.drop(r() * w, r() * h, 30 + r() * Math.max(w, h) * 0.09, tones[i % tones.length]);
  // a few quiet ribbons, combed before you arrive
  tray.comb(1, 0, 90, 20, 30, 16, true);
  tray.wave(14, 260, 1.3);
}

function heroSequence() {
  const { w, h } = tray;
  const cx = w / 2, cy = h * (w < 720 ? 0.22 : 0.36), m = Math.min(w, h) * (w < 720 ? 0.85 : 1);
  const seq = [PIG.mint, PIG.bone, PIG.sea, PIG.coral, PIG.pale, PIG.teal, PIG.mint, PIG.bone];
  const r = rng(3);
  seq.forEach((c, i) => {
    const R = m * (0.13 - i * 0.008);
    drip(cx, 30, cx + (r() - 0.5) * m * 0.05, cy + (r() - 0.5) * m * 0.04, R, c, reduced.matches ? 0 : 500 + i * 360);
  });
  // then a needle is pulled down through the rings: the drop becomes a tulip
  const needleAt = reduced.matches ? 0 : 500 + seq.length * 360 + 1100;
  setTimeout(() => {
    const path = [];
    for (let i = 0; i <= 40; i++) path.push([cx, cy - m * 0.22 + (m * 0.52) * i / 40]);
    if (reduced.matches) { for (let i = 1; i < path.length; i++) tray.stylus(...path[i - 1], ...path[i], 18); tray.refine(); tray.render(); }
    else { tray.needle(path, 1500, 18); kick(); }
  }, needleAt);
}

// The water is yours: a click drops pigment where you click, a drag combs it (mouse and pen; touch scrolls).
const PALETTE = [PIG.mint, PIG.bone, PIG.coral, PIG.sea, PIG.pale, PIG.saffron];
let paletteAt = 0;
function stylusOnHero() {
  const zones = [$('.hero'), $('.stage-pin')];
  const skip = 'a, button, input, label, code, h1, h2, p, li, .brew, .panel-wrap, .chapter, .notch';
  for (const zone of zones) {
    let prev = null, start = null, moved = 0;
    zone.addEventListener('pointerdown', e => {
      if (e.button !== 0 || e.target.closest(skip)) return;
      start = prev = [e.clientX, e.clientY]; moved = 0;
      if (e.pointerType !== 'touch') { zone.setPointerCapture(e.pointerId); e.preventDefault(); }
    });
    zone.addEventListener('pointermove', e => {
      if (!prev || e.pointerType === 'touch') return;
      moved += Math.hypot(e.clientX - prev[0], e.clientY - prev[1]);
      if (moved > 6) { tray.stylus(prev[0], prev[1], e.clientX, e.clientY, 18); $('.hero').classList.add('combed'); kick(); }
      prev = [e.clientX, e.clientY];
    });
    zone.addEventListener('pointerup', e => {
      if (start && moved <= 6) {
        const m = Math.min(tray.w, tray.h);
        const color = PALETTE[paletteAt++ % PALETTE.length];
        if (reduced.matches) tray.drop(e.clientX, e.clientY, m * 0.05, color); else tray.bloom(e.clientX, e.clientY, m * 0.05, color, 700);
        $('.hero').classList.add('combed'); kick();
      }
      start = prev = null;
    });
    zone.addEventListener('pointercancel', () => { start = prev = null; });
  }
}

/* ————————————————— home: now playing ————————————————— */

const TRACKS = [
  { title: 'Golden Hour', by: 'Nova Lane', tint: PIG.coral, len: 214, at: 85,
    art: `<defs><linearGradient id="c0" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f58a6a"/><stop offset=".55" stop-color="#e24f8e"/><stop offset="1" stop-color="#7a3fa6"/></linearGradient></defs><rect width="100" height="100" fill="url(#c0)"/><circle cx="50" cy="40" r="20" fill="#fbd18a"/><g fill="#6a3596"><rect y="70" width="100" height="4"/><rect y="79" width="100" height="5"/><rect y="89" width="100" height="6"/></g>` },
  { title: 'Ferry at Dusk', by: 'Kıyı', tint: PIG.indigo, len: 242, at: 64,
    art: `<defs><linearGradient id="c1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b2250"/><stop offset=".6" stop-color="#4556c2"/><stop offset="1" stop-color="#9fb0ff"/></linearGradient></defs><rect width="100" height="100" fill="url(#c1)"/><circle cx="70" cy="30" r="10" fill="#ede7dc"/><path d="M18 62h40l-5 7H24Z" fill="#0e1330"/><rect x="30" y="54" width="18" height="8" fill="#0e1330"/><g stroke="#c9d3ff" stroke-opacity=".55" stroke-width="1.6"><path d="M0 76h100M10 83h80M22 90h56"/></g>` },
  { title: 'Mint Tea', by: 'Paper Lanterns', tint: '#8fd9c4', len: 178, at: 41,
    art: `<defs><linearGradient id="c2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#a9ead8"/><stop offset="1" stop-color="#2b7a72"/></linearGradient></defs><rect width="100" height="100" fill="url(#c2)"/><g fill="#1d4a4f"><ellipse cx="38" cy="44" rx="10" ry="24" transform="rotate(-32 38 44)"/><ellipse cx="62" cy="50" rx="9" ry="22" transform="rotate(28 62 50)"/><ellipse cx="50" cy="66" rx="8" ry="18"/></g><g stroke="#a9ead8" stroke-width="1.4" fill="none"><path d="M38 24v38M62 30v36M50 50v32"/></g>` },
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
    lines.forEach((li, j) => { li.style.setProperty('--line', k.toFixed(2)); li.classList.toggle('now', j === now); });
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

const agents = {
  page: $('.page-agents'), wait: 44, answered: null, asked: null, doneAt: 0, forceList: false,
  refresh() {
    const card = $('.session.waiting'), state = $('.s-state', card), mascot = $('.mascot', card);
    if (!this.answered) { state.textContent = t().waiting(this.wait); mascot.dataset.phase = 'waiting'; }
    else if (this.answered === 'deny') { state.textContent = t().denied; mascot.dataset.phase = 'idle'; }
    else { state.textContent = this.doneAt ? t().doneRun : t().working; mascot.dataset.phase = this.doneAt ? 'done' : 'working'; }
    card.classList.toggle('approved', !!this.answered);
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

/* ————————————————— sound ————————————————— */

function mixer() {
  for (const input of $$('.mixer input')) {
    const out = input.nextElementSibling;
    const sync = () => { input.style.setProperty('--v', `${input.value}%`); out.textContent = input.value; };
    input.addEventListener('input', sync); sync();
  }
  for (const li of $$('.outputs li')) li.addEventListener('click', () => {
    for (const o of $$('.outputs li')) o.classList.toggle('on', o === li);
    const check = $('.outputs .check'); li.append(check);
  });
}

/* ————————————————— mirror: the instant camera ————————————————— */

const FILMS = ['nostalgia', 'bw', 'natural'];
const mirror = {
  finder: $('.finder'), cv: $('.finder-cv'), video: $('.finder-video'), stream: null, running: false, shot: false, busy: false,
  film: 'nostalgia', countdown: true, prints: 0,
  enter() { this.shot = false; if (!this.running) { this.running = true; this.loop(); } },
  leave() { this.running = false; this.stop(); },
  loop() {
    if (!this.running || document.hidden) { this.running = false; return; }
    if (!this.stream) {
      // Nobody in front of the camera: the viewfinder looks at the water under the panel.
      const ctx = this.cv.getContext('2d'), [x, y] = stage.impact(), d = tray.dpr;
      const side = Math.min(420 * d, canvas.width, canvas.height);
      const sx = clamp(x * d - side / 2, 0, canvas.width - side), sy = clamp(y * d - side / 2, 0, canvas.height - side);
      ctx.drawImage(canvas, sx, sy, side, side, 0, 0, this.cv.width, this.cv.height);
    }
    requestAnimationFrame(() => this.loop());
  },
  source() { return this.stream ? this.video : this.cv; },
  autoShoot() { if (!this.shot && !this.busy) { this.shot = true; this.shoot(); } },
  async shoot() {
    if (this.busy) return;
    this.busy = true; this.shot = true;
    this.finder.classList.add('busy');
    const count = $('.count', this.finder);
    if (this.countdown && !reduced.matches) {
      for (const n of [3, 2, 1]) {
        count.textContent = n; count.classList.remove('tick'); void count.offsetWidth; count.classList.add('tick');
        await new Promise(r => setTimeout(r, 1000));
      }
    }
    const flash = $('.flash', this.finder); flash.classList.remove('go'); void flash.offsetWidth; flash.classList.add('go');
    setTimeout(() => this.print(), 350);
    setTimeout(() => { this.busy = false; this.finder.classList.remove('busy'); }, 1900);
  },
  print() {
    const card = document.createElement('figure');
    card.className = 'print';
    card.title = t().printNote;
    const c = document.createElement('canvas'); c.width = 400; c.height = 400;
    const ctx = c.getContext('2d');
    const filters = { nostalgia: 'sepia(.38) saturate(1.35) contrast(1.06) brightness(1.06) hue-rotate(-10deg)', bw: 'grayscale(1) contrast(1.25) brightness(1.05)', natural: 'none' };
    ctx.filter = filters[this.film];
    const src = this.source();
    if (this.stream) { ctx.translate(400, 0); ctx.scale(-1, 1); }
    const vw = src.videoWidth || src.width, vh = src.videoHeight || src.height, sc = Math.max(400 / vw, 400 / vh);
    ctx.drawImage(src, (400 - vw * sc) / 2, (400 - vh * sc) / 2, vw * sc, vh * sc);
    ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.filter = 'none';
    ctx.font = '600 26px "SF Mono", "JetBrains Mono", monospace'; ctx.textAlign = 'right';
    ctx.shadowColor = 'rgba(255,102,13,.9)'; ctx.shadowBlur = 5; ctx.fillStyle = '#ff8f29';
    ctx.fillText(stamp(new Date()), 384, 384);
    const note = document.createElement('small');
    note.textContent = new Date().toLocaleDateString(lang === 'tr' ? 'tr-TR' : 'en-US', { day: 'numeric', month: 'long', year: 'numeric' });
    card.append(c, note);
    const i = this.prints++;
    card.style.setProperty('--dx', `${(i % 3) * 3}px`);
    card.style.setProperty('--dy', `${(i % 3) * 5}px`);
    card.style.setProperty('--rot', `${[-4, 5, -1][i % 3]}deg`);
    const pile = $('#pile');
    while ($$('.print', pile).length >= 4) $('.print', pile).remove();
    pile.append(card); pile.classList.add('has-prints');
    $('.pile-count').textContent = t().photos(this.prints);
    requestAnimationFrame(() => requestAnimationFrame(() => card.classList.add('out', 'developed')));
    card.addEventListener('click', () => c.toBlob(b => {
      if (!b) return;
      const a = document.createElement('a'); a.href = URL.createObjectURL(b); a.download = `damla-ayna-${Date.now()}.png`;
      document.body.append(a); a.click(); a.remove();
    }, 'image/png'));
  },
  async camera() {
    const btn = $('.cam-try');
    if (this.stream) { this.stop(); return; }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 640 }, audio: false });
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
  init() {
    $('.f-stamp').textContent = stamp(new Date());
    $('.film-btn').addEventListener('click', () => {
      this.film = FILMS[(FILMS.indexOf(this.film) + 1) % FILMS.length];
      this.finder.dataset.film = this.film;
      $('.f-film').textContent = t().films[this.film];
    });
    $('.timer-btn').addEventListener('click', e => { this.countdown = !this.countdown; e.currentTarget.classList.toggle('on', this.countdown); });
    $('.f-stage').addEventListener('click', e => e.currentTarget.classList.toggle('on'));
    $('.shutter').addEventListener('click', () => this.shoot());
    $('.cam-try').addEventListener('click', () => this.camera());
    if (matchMedia('(hover: none)').matches) this.finder.classList.add('show');
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) this.stop();
      else if (stage.chapter === 'mirror') this.enter();
      if (!document.hidden) { tray.dirty = true; kick(); }
    });
  },
};
// "'26 9 28", the way film cameras printed the date.
function stamp(d) { return `’${String(d.getFullYear() % 100).padStart(2, '0')} ${d.getMonth() + 1} ${d.getDate()}`; }

/* ————————————————— the stage ————————————————— */

const CHAPTERS = [
  { id: 'music', from: 0.05, to: 0.27, tab: 'music' },
  { id: 'agents', from: 0.27, to: 0.5, tab: 'agents' },
  { id: 'files', from: 0.5, to: 0.66, tab: 'files' },
  { id: 'mirror', from: 0.66, to: 0.82, tab: 'mirror' },
  { id: 'sound', from: 0.82, to: 0.95, tab: 'music' },
];
const PANEL_H = 218, LYRICS_H = 330;
const stage = {
  el: $('#stage'), wrap: $('.panel-wrap'), panel: $('#panel'), notch: $('#notch'),
  chapter: null, t: 0, top: 0, height: 0, vh: innerHeight, ps: 1,
  measure() {
    const r = this.el.getBoundingClientRect();
    this.top = r.top + scrollY; this.height = this.el.offsetHeight; this.vh = innerHeight;
    const vw = document.documentElement.clientWidth;
    this.ps = Math.min(1.6, (vw - 24) / 384, (this.vh * (vw < 720 ? 0.36 : 0.5)) / (PANEL_H + 56));
    this.wrap.style.setProperty('--ps', this.ps.toFixed(3));
  },
  // Where the viewfinder looks: the water just under the panel.
  impact() {
    const bottom = (PANEL_H + 56) * this.ps;
    return [tray.w / 2, bottom + (this.vh - bottom) * 0.25];
  },
  update() {
    const span = this.height - this.vh;
    const t = span > 0 ? clamp((scrollY - this.top) / span) : 0;
    this.t = t;
    const inStage = scrollY >= this.top - this.vh * 0.2 && scrollY <= this.top + span + this.vh * 0.2;
    let open = t < 0.05 ? t / 0.05 : t > 0.95 ? (1 - t) / 0.05 : 1;
    if (scrollY < this.top) open = 0;
    open = reduced.matches ? (open > 0.01 ? 1 : 0) : 1 - Math.pow(1 - clamp(open), 3);
    const content = clamp((open - 0.55) / 0.45);
    const ch = CHAPTERS.find(c => t >= c.from && t < c.to) || (t >= 0.95 ? CHAPTERS[CHAPTERS.length - 1] : CHAPTERS[0]);
    const sub = clamp((t - ch.from) / (ch.to - ch.from));
    const active = inStage && open > 0.5 ? ch.id : null;

    // Golden Hour, then Mint Tea, then Ferry at Dusk, whose lyrics roll in the last stretch
    if (ch.id === 'music' && active && performance.now() - music.byHand > 2500) music.set(sub < 0.2 ? 0 : sub < 0.4 ? 2 : 1, true);
    const lyricsOn = ch.id === 'music' && music.lyricsOn(sub);
    this.panel.classList.toggle('lyrics-on', lyricsOn);
    $('.lyrics-btn').setAttribute('aria-pressed', String(lyricsOn));
    this.panel.style.setProperty('--open', open.toFixed(4));
    this.panel.style.setProperty('--content', content.toFixed(3));
    this.panel.style.setProperty('--page-h', `${lyricsOn ? LYRICS_H : PANEL_H}px`);
    this.wrap.style.setProperty('--content', content.toFixed(3));
    this.wrap.style.visibility = open > 0.001 ? 'visible' : 'hidden';

    if (active !== this.chapter) this.enter(active);
    for (const a of $$('.chapter')) a.classList.toggle('on', a.dataset.chapter === active);
    if (ch.id === 'music' && active) music.scrollLyrics(sub);
    if (ch.id === 'agents' && active && !agents.forceList) agents.page.dataset.view = sub < 0.34 ? 'list' : sub < 0.68 ? 'ask' : 'q';
    if (ch.id === 'files' && active) shelf.show(Math.floor((sub - 0.08) * 6));
    if (ch.id === 'mirror' && active && sub > 0.25) mirror.autoShoot();
    if (ch.id === 'sound' && active) $('.page-sound').dataset.view = sub < 0.5 ? 'outputs' : 'mixer';
    this.notch.dataset.mode = active || 'brand';
  },
  enter(id) {
    const prev = this.chapter;
    this.chapter = id;
    if (id) this.panel.dataset.page = id;
    const ch = CHAPTERS.find(c => c.id === id);
    for (const s of $$('.tabbar span[data-tab]')) s.classList.toggle('on', !!ch && s.dataset.tab === ch.tab);
    if (prev === 'agents' && id !== 'agents') agents.reset();
    if (prev === 'mirror' && id !== 'mirror') mirror.leave();
    if (id === 'mirror') mirror.enter();
    if (ch) document.documentElement.style.setProperty('--tint', ch.tint || TRACKS[music.i].tint);
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

let lastY = scrollY;
function onScroll() {
  const y = scrollY, dy = y - lastY; lastY = y;
  stage.update();
  stage.notchMascot();
  if (!trayLive || reduced.matches || !dy) return;
  if (y < innerHeight) tray.comb(0, -1, 74, 12, dy * 0.12, 11);          // the hero: tines pull the pigment up
  else tray.comb(1, 0, 64, 17, dy * 0.045, 10, true);                    // the stage: a slow gelgit, back and forth
  kick();
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
  for (const a of $$('.notch-menu a')) a.addEventListener('click', e => {
    const id = a.getAttribute('href').slice(1);
    set(false);
    if (id === 'stage' || id === 'agents') { e.preventDefault(); stage.scrollToChapter(id === 'agents' ? 'agents' : 'music'); }
  });
  for (const b of $$('.lang button')) b.addEventListener('click', () => setLang(b.dataset.lang));
}

/* ————————————————— pattern book ————————————————— */

function fitVignettes() {
  for (const v of $$('.vig')) {
    const sheet = v.parentElement, w = parseFloat(getComputedStyle(v).getPropertyValue('--w')) || 300;
    const vs = Math.min(1.55, (sheet.clientWidth * 0.8) / w, (sheet.clientHeight * 0.8) / (v.offsetHeight || 1));
    v.style.setProperty('--vs', vs.toFixed(3));
  }
}
function swatches() {
  const io = new IntersectionObserver(entries => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      io.unobserve(e.target);
      const li = e.target, c = li.dataset.colors.split(','), cv = $('canvas', li);
      const small = new Tray(cv, { ground: c[3], pixelBudget: 1.6e6, maxDpr: 2, maxDrops: 400, vertexBudget: 80000 });
      const k = Math.max(1, cv.clientWidth / 240);
      small.resize(cv.clientWidth / k, cv.clientHeight / k, k);
      patterns[li.dataset.pattern](small, c, rng(li.dataset.pattern.length * 97 + c[0].charCodeAt(2)));
      small.refine(); small.render();
    }
  }, { rootMargin: '200px' });
  for (const li of $$('.swatches li')) io.observe(li);
}

/* ————————————————— the print ————————————————— */

function print() {
  const out = $('#print'), ctx = out.getContext('2d');
  const W = out.width, H = out.height;
  const draw = () => {
    const sw = canvas.width, sh = canvas.height;
    const scale = Math.max(W / sw, H / sh);
    const w = W / scale, h = H / scale;
    ctx.drawImage(canvas, (sw - w) / 2, (sh - h) / 2 * 0.7, w, h, 0, 0, W, H);
    ctx.fillStyle = 'rgba(237,231,220,.72)';
    ctx.font = '800 22px "Nunito", sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText('damla · ebru', W - 28, H - 26);
  };
  const io = new IntersectionObserver(es => { if (es.some(e => e.isIntersecting)) draw(); }, { rootMargin: '300px 0px' });
  io.observe($('#sheet'));
  $('#save-print').addEventListener('click', () => {
    draw();
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
    const label = $('span', b), was = label.textContent;
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
    canvas.style.visibility = trayLive ? 'visible' : 'hidden';
    if (trayLive && !was) { tray.dirty = true; kick(); }
  });
  io.observe($('.hero')); io.observe(stage.el);
}

/* ————————————————— go ————————————————— */

captureEnglish();
drawMascots();
music.init();
agents.init();
mirror.init();
Object.assign(window.__damla, { stage, music, agents, mirror });
shelf.init();
mixer();
notchMenu();
copyButtons();
swatches();
fitVignettes();
print();
stylusOnHero();

tray.resize();
seedGround();
tray.refine(); tray.render();
stage.measure();
stage.update();
trayVisibility();

const saved = store.get('damla.lang');
setLang(saved || ((navigator.language || '').toLowerCase().startsWith('tr') ? 'tr' : 'en'));

addEventListener('scroll', onScroll, { passive: true });
let resizeTimer;
addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => { tray.resize(); stage.measure(); stage.update(); tray.refine(); tray.render(); fitVignettes(); }, 120);
});
(document.fonts?.ready || Promise.resolve()).then(() => heroSequence());
latestRelease();

let lastTick = performance.now();
setInterval(() => {
  const now = performance.now();
  if (stage.chapter === 'music') music.tick((now - lastTick) / 1000);
  lastTick = now;
}, 500);
