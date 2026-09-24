# MediaRemoteAdapter (vendored)

Kaynak: https://github.com/ungive/mediaremote-adapter — commit 73f14ab (4 Eylül 2026), BSD 3-Clause (bkz. LICENSE).

`MediaRemoteAdapter.framework` ve `MediaRemoteAdapterTestClient`, `src/` ve `include/` içindeki kaynaktan
`build-adapter.sh` ile derlenmiştir (clang, arm64). Uygulama bunları `Contents/Resources/MediaRemoteAdapter/`
altına kopyalar ve `/usr/bin/perl mediaremote-adapter.pl <framework> stream` ile çalıştırır; çerçeveye
bağlanılmaz, yalnızca perl içine yüklenir. Yeniden derlemek için:

```sh
zsh Vendor/MediaRemoteAdapter/build-adapter.sh
```

## Yerel yamalar

- `src/utility/helpers.m`: JSON'a çevrilemeyen sayılar (canlı yayınların sonsuz `duration` değeri, NaN) atlanmak yerine
  `null` olarak yazılır. Böylece fark (`diff`) akışında eski parçanın süresi temizlenir ve her güncellemede hata çıktısına
  "Invalid JSON value type" uyarısı düşmez. Yama derlenmiş çerçeveye ancak `build-adapter.sh` yeniden çalıştırılınca girer.
