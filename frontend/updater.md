# Dokumentasi & Spesifikasi: Flutter Self-Hosted Updater (Proxy Architecture)

## 1. Arsitektur & Alur Kerja
1. **App Initialization:** Saat aplikasi berjalan, panggil fungsi `checkUpdate()`.
2. **Version Comparison:** 
   - Ambil versi aplikasi lokal menggunakan `package_info_plus`.
   - Lakukan HTTP GET ke Cloudflare Worker Proxy (`/api/latest-release`).
   - Bandingkan semantic versioning (Lokal vs Server).
3. **User Prompt:** Jika ada versi baru, tampilkan UI Dialog berisi `Release Notes` dan tombol "Update Sekarang".
4. **Download Process:** Jika *user* setuju, unduh *artifact* sesuai OS (platform detection) ke direktori sementara (*temporary directory*) menggunakan `dio` agar bisa melacak persentase unduhan (`onReceiveProgress`).
5. **Installation:** Eksekusi file yang telah diunduh menggunakan `open_filex` atau jalankan proses instalasi *native*.

## 2. API Endpoint & Alur Unduh (Via Proxy Cloudflare Worker)
- **URL Target Check:** `https://<URL_WORKER_KAMU>.workers.dev/api/latest-release`
- **Keamanan:** Tidak ada GitHub Token di kode Flutter. Lakukan HTTP GET standar ke URL Worker.
- **Data yang diterima dari Worker (JSON):**
  - `version` (Contoh: `1.2.0` -> gunakan untuk komparasi).
  - `release_notes` (Catatan rilis untuk ditampilkan ke *user*).
  - `download_urls` (Object berisi *link* unduh spesifik per OS).
- **Proses Unduhan Biner (Krusial):** 
  Link yang ada di `download_urls` akan mengarah kembali ke Worker (contoh: `https://<URL_WORKER_KAMU>.workers.dev/api/download?asset_id=12345`). 
  Worker akan melakukan otentikasi internal ke GitHub dan mengembalikan status `302 Redirect` ke URL Storage mentah. Flutter `dio` harus dikonfigurasi untuk secara otomatis mengikuti (follow) *redirects* ini untuk mengunduh file instalasi.

## 3. Package Dependencies
Pastikan menggunakan *packages* berikut dalam implementasi:
- `package_info_plus`: Untuk membaca versi lokal aplikasi.
- `dio`: Untuk HTTP *request* ke API dan mengunduh file besar. Set `followRedirects: true`.
- `path_provider`: Untuk mendapatkan lokasi penyimpanan aman (`getTemporaryDirectory()`).
- `permission_handler`: Khusus Android untuk meminta izin penyimpanan/instalasi (jika perlu).
- `open_filex`: Untuk mengeksekusi *installer* (.apk, .exe, .dmg, .deb) setelah unduhan selesai 100%.

## 4. Platform Specific Handling
Kode harus mendeteksi OS saat ini (`Platform.isAndroid`, `Platform.isWindows`, dll) dan menerapkan logika berikut:

- **Android:**
  - Tambahkan *permission* `REQUEST_INSTALL_PACKAGES` dan `INTERNET` di `AndroidManifest.xml`.
  - Eksekusi `.apk` dengan `open_filex` akan memicu *Package Installer* bawaan Android.
- **Windows:**
  - Unduh `.exe` ke *temp folder*.
  - Mengeksekusi file `.exe` harus memicu *installer* untuk berjalan.
- **macOS:**
  - Unduh `.dmg`. Eksekusi file akan me-*mount* DMG dan membuka *Finder*.
- **Linux:**
  - Unduh `.deb`. Eksekusi file akan membuka GUI *Package Manager* bawaan distro Linux.

## 5. UI/UX Requirements
- Tampilkan `LinearProgressIndicator` atau teks persentase (0% - 100%) selama proses pengunduhan.
- Berikan tombol "Batal" saat mengunduh, yang akan membatalkan *request* `dio` (gunakan `CancelToken`).
- Tampilkan *Snackbar* atau pesan kesalahan yang ramah pengguna jika terjadi kegagalan jaringan atau gagal mengekstrak file.