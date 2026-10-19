# TokuplayIOS

Reimplementasi SwiftUI (iOS 17+) berdasarkan analisis statis `tokuplay_v3.2.7.apk`. Bukan hasil konversi APK.
Kode belum pernah dikompilasi: Windows tidak bisa build iOS, jadi build pertama harus dilakukan di Mac.

## Build (Mac, Xcode 15+)

```
brew install xcodegen
xcodegen generate        # membaca project.yml -> TokuplayIOS.xcodeproj
open TokuplayIOS.xcodeproj
```

1. Ganti `PRODUCT_BUNDLE_IDENTIFIER` di `project.yml` dan pilih signing team.
2. Tambahkan gambar ikon 1024x1024 ke `Resources/Assets.xcassets/AppIcon.appiconset`.
3. Jalankan, lalu isi alamat blog sumber konten di tab Pengaturan
   (atau isi `TokuplayBaseURL` di `Info.plist`).

## Yang sudah ada

- Home (grid poster, pull to refresh), Cari (debounce, `?q=`), Koleksi (bookmark), Detail, Pengaturan.
- `ApiService`: decoder feed Blogger (`$t`, `openSearch$totalResults`, `media$thumbnail`, label, tanggal), paging 150 item.
- `StreamRepository`: port logika ekstraksi APK (fallback video, urutan kualitas, regex subtitle).
- `PlayerView`: AVPlayer dengan header referer dan pilihan kualitas.
- Bookmark dan riwayat disimpan lokal (pengganti Room di APK).

## Temuan dari APK (rantai konfigurasi)

1. String `app_key` di APK dienkripsi `Opener` (lihat `tools/decrypt_plugin.js`, password = nama paket; folder `tools/` ada di `.gitignore`).
2. Hasil dekripsi = blog konfigurasi. Halaman `feeds/pages/default/<id>?alt=json` berisi JSON terenkripsi (indeks).
3. Indeks menunjuk blog kedua; halaman `/p/db.html` (`.post-body`) berisi JSON konfigurasi:
   kategori beranda, label, daftar channel TV, dan URL plugin terenkripsi.
4. Ekstraksi stream asli dijalankan oleh plugin yang diunduh saat runtime dan dijaga cek tanda tangan APK.

## Plugin Tokuplay (hasil analisis plugin runtime)

`Data/TokuplayPlugins.swift` memuat dua loader milik Tokuplay sendiri:

- `StoragePlugin` (`@storage:<id>[|res,res][?lang,lang]`) -> `blob.tokuplay.xyz/f/<token>/<file>[.<res>.mp4]`.
  Token = AES-256-CBC(path, key = SHA-256("context"), IV nol), base64 URL-safe tanpa padding.
- `DashPlugin` (`mpd:<id>` atau `mpd:<id>@...`) -> `dash.tokuplay.xyz/video|stream/...`.
  AVPlayer tidak bisa memutar DASH (`.mpd`), jadi hanya bentuk `@` yang bisa diputar.

Loader pihak ketiga di plugin sengaja tidak diport.

## Batasan yang masih ada

- **Alamat blog konten tidak diisi.** Ia ada di konfigurasi/plugin runtime yang tidak dibuka di port ini.
  Aplikasi bekerja dengan blog Blogger mana pun yang Anda tentukan sendiri.
- **Plugin host video tidak ada.** Hanya link langsung (`.m3u8`, `.mp4`, dst.) yang diputar. Parsing episode dari
  isi post bersifat perkiraan (`ApiService.parseEpisodes`) dan perlu disesuaikan dengan format blog Anda.
- Subtitle eksternal (`.srt/.vtt/.ass`) digambar sendiri di atas video (`Features/Player/Subtitles.swift`),
  karena AVPlayer tidak memuat file subtitle terpisah. Format ASS hanya teksnya, tanpa gaya.
- Belum ada: push notification (Firebase), analytics, cek update, layar laporan, PiP, Chromecast.
