# UNIVERSAL FLUTTER MULTI-PLATFORM - MAINTENANCE & CI/CD SOP

Dokumen ini adalah Standard Operating Procedure (SOP) **Universal** yang dapat diterapkan pada aplikasi Flutter Multi-platform (Android, Windows, Linux, macOS) apa pun. Dokumen ini merangkum *best practices*, penanganan masalah sistem (*technical difficulties*), dan trik arsitektur yang terbukti stabil untuk menangani Auto-Update, Database Restore, dan CI/CD Deployment.

---

## 1. Arsitektur CI/CD & Deployment (Private to Public)

Pola ini sangat ideal jika kamu memiliki source code yang bersifat **Private**, namun ingin mendistribusikan file aplikasi (binaries) secara otomatis ke **Public Release** via GitHub Actions.

### 1.1 Konsep Dua Repositori
- **Repo Private (Development):** Tempat menulis code. Tidak ada GitHub Actions build release di sini.
- **Repo Public (Release):** Tempat GitHub Actions berjalan. Repo ini akan meng-clone source code dari Repo Private (menggunakan `PRIVATE_REPO_TOKEN`), mem-build-nya, dan meng-upload file `.apk`, `.exe`, `.deb`, `.rpm` ke tab "Releases". Fitur Auto-Update di dalam aplikasi (in-app update) akan menunjuk ke API GitHub repo public ini.

### 1.2 Alur Rilis Versi Baru
1. Update versi di `pubspec.yaml` (misal: `1.0.1+1`).
2. Commit dan push code di Repo Private beserta tag versinya (`git tag v1.0.1`).
3. Buat tag yang sama persis di Repo Public lalu push untuk memicu GitHub Actions.

---

## 2. Manajemen Android Keystore (Mencegah App Conflict)

**Masalah Universal:** Saat fitur *In-App Update* mengunduh APK baru dan mencoba menginstalnya, Android OS akan menolak ("App not installed as package conflicts") jika signature APK lama berbeda dengan APK baru. Ini terjadi jika CI/CD server menggunakan *Debug Key* acak.

### 2.1 Cara Membuat Release Keystore (`.jks`)
Lakukan ini **satu kali saja** di awal pembuatan proyek:
1. Buka terminal di laptop/PC kamu.
2. Jalankan perintah `keytool` bawaan Java:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias ALIAS_BEBAS
   ```
3. Masukkan password (misal: `rahasia123`) dan isi data identitas (Nama, Organisasi, dll).
4. Simpan file `upload-keystore.jks` yang terbuat di tempat aman. **Jangan sampai hilang**.

### 2.2 Cara Konversi Keystore untuk CI/CD (GitHub Actions)
File `.jks` adalah file binary yang tidak boleh di-commit ke Git secara mentah. Kita harus mengubahnya jadi teks (Base64) untuk disimpan di GitHub Secrets.

1. **Convert ke Base64 (Linux/Mac):**
   ```bash
   base64 -w0 upload-keystore.jks > keystore_base64.txt
   ```
2. **Masukkan ke GitHub Secrets Repo Public:**
   Masuk ke Settings -> Secrets and variables -> Actions, lalu buat 3 variabel:
   - `KEYSTORE_BASE64` (Paste seluruh isi file `keystore_base64.txt`)
   - `KEYSTORE_PASSWORD` (Password yang dibuat di step 2.1)
   - `KEY_ALIAS` (Alias yang dibuat di step 2.1)

3. Di script `.github/workflows`, buat *step* untuk merangkai kembali rahasia ini menjadi `.jks`:
   ```yaml
   - name: Setup Keystore for Signing
     working-directory: src/android
     run: |
       echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > app/upload-keystore.jks
       cat <<EOF > key.properties
       storePassword=${{ secrets.KEYSTORE_PASSWORD }}
       keyPassword=${{ secrets.KEYSTORE_PASSWORD }}
       keyAlias=${{ secrets.KEY_ALIAS }}
       storeFile=upload-keystore.jks
       EOF
   ```

---

## 3. In-App Soft Restart (Khusus untuk Restore Database)

**Masalah Universal:** Aplikasi yang berbasis SQLite lokal sering kali butuh proses *Restore Database* dari file cadangan (`.db`). Jika aplikasi di-kill paksa di level OS (`exit(0)`), transisinya kasar (force-close). Selain itu, *lock* pada file `.db` bisa tersangkut.

**SOP Soft Restart:**
Gunakan package **`flutter_phoenix`** untuk menghancurkan dan membangun ulang (*rebirth*) widget tree tanpa mematikan proses OS.

Alur kode yang benar:
```dart
// 1. Tutup koneksi DB lama (memutus file lock dari SQLite)
await LocalDb.closeConnection();

// 2. Timpa file .db yang aktif dengan file backup baru
File(backupPath).copySync(activeDbPath);

// 3. Inisialisasi ulang koneksi DB
await LocalDb.init();

// 4. (Opsional) Reset route agar kembali ke Splash/Login
GoRouter.of(context).go('/');

// 5. Eksekusi Soft Restart (membersihkan seluruh Provider/State memory)
Phoenix.rebirth(context);
```

---

## 4. In-App Update Download & Install (MIME & Cache)

**Masalah Universal:** Fitur auto-update Android gagal membuka APK setelah di-download, atau bentrok dengan file cache sisa gagal update sebelumnya.

**SOP:**
1. **Clear Cache Downloader:** Selalu lakukan pengecekan dan penghapusan (delete) file tujuan `getTemporaryDirectory() + "/update.apk"` *sebelum* memulai download baru.
2. **Explicit MIME (package `open_filex`):**
   Jangan gunakan buka file biasa. Wajib menggunakan explicit MIME agar Android me-trigger package installer:
   ```dart
   OpenFilex.open(filePath, type: 'application/vnd.android.package-archive');
   ```

---

## 5. Linux OS Awareness (Deteksi Distribusi Linux)

**Masalah Universal:** Saat mengecek versi terbaru dari GitHub Releases, pengguna Fedora butuh file `.rpm`, dan pengguna Ubuntu butuh `.deb`.

**SOP Deteksi Distribusi Linux di Dart:**
Membaca file `/etc/os-release` adalah cara paling valid di Linux OS mana pun.
```dart
if (Platform.isLinux) {
  final result = await Process.run('cat', ['/etc/os-release']);
  final output = result.stdout.toString().toLowerCase();
  
  if (output.contains('fedora') || output.contains('rhel') || output.contains('centos')) {
    return '.rpm';
  } else {
    return '.deb'; // Default untuk keluarga debian/ubuntu
  }
}
```

---

## 6. Responsivitas Universal (Desktop Compact / Tablet)

**Masalah Universal:** Aplikasi desktop sering tidak selalu berada di "Full Screen". Saat di-resize kecil, elemen yang *fixed-width* (seperti Sidebar atau Numpad POS) akan menabrak elemen utama.

**SOP Layout:**
1. **SingleChildScrollView + Expanded:** Bagian tengah konten yang rentan terdorong *harus* dibungkus Scroll View.
2. **Auto-Collapse Sidebar:** Terapkan deteksi lebar layar (`MediaQuery.sizeOf(context).width`). Jika di bawah nilai aman (misal `1100px`), paksa *Sidebar* berubah menjadi mode *Icon-Only* (Compact).
3. **Tooltip Wajib:** Saat Sidebar berstatus *Icon-Only*, tambahkan widget `Tooltip` pada icon agar UX tetap jelas.

---

## 7. Printer Thermal Text Truncation

**Masalah Universal:** Saat menggunakan library printer ESC/POS, text string panjang akan terpotong secara mentah di ujung kertas, yang memotong huruf di tengah kata.

**SOP:**
1. Buat algoritma pemecah karakter (*word wrapper*) manual sebelum text dilempar ke `generator.text()`. Limit standar untuk kertas **58mm adalah 32 karakter per baris**.
2. **Selalu berikan `generator.feed(1)`** di akhir baris cetakan agar mesin pemotong (tear bar) tidak memotong huruf paling bawah saat kertas ditarik pengguna.
