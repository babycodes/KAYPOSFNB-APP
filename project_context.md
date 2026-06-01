# KAYPOS FNB - Project Context & Rules

Dokumen ini berisi konteks lengkap mengenai arsitektur, progress terakhir, aturan ketat (rules), dan mekanisme deployment repository KayPOS FNB. Gunakan ini sebagai referensi utama saat melanjutkan pengembangan dengan AI Agent (Antigravity).

## 1. Repository Structure

Project ini terbagi menjadi 3 repository utama:
1. **`KAYPOSFNB` (Private)**: Repository utama berisi source code Frontend (Flutter). Berada di lokal pada path `/home/papayu/Data/AI/Flutter/KAYPOSFNB/frontend`.
2. **`kayposfnbserver` (Private)**: Repository utama berisi source code Backend (Fastify/Node.js + Prisma). Berada di lokal pada path `/home/papayu/Data/AI/Flutter/KAYPOSFNB/kayposfnbserver`.
3. **`KAYPOSFNB-APP` (Public)**: Repository *mirror/proxy* yang dikhususkan HANYA untuk GitHub Actions CI/CD. Repo ini mem-build aplikasi (APK/Linux) dan menyediakan hosting aset Release agar aplikasi bisa melakukan in-app update tanpa mengekspos token repo private.

---

## 2. Current Progress (Status Terakhir)

### Frontend (Flutter - SQLite Offline First)
- **UUID Migration Selesai**: Seluruh struktur database lokal (SQLite) telah di-migrate dari `INTEGER AUTOINCREMENT` menjadi `TEXT` (UUID v4).
- **Sync Readiness**: Tabel utama telah memiliki kolom `updated_at` (TEXT ISO8601) dan `is_deleted` (INTEGER 0/1) untuk persiapan fitur sinkronisasi dengan backend.
- **Kasir & Inventory Logic**: 
  - Logika perhitungan porsi (bottleneck) bahan baku yang digunakan bersama (shared inventory) antar produk sudah sangat akurat.
  - Mendukung produk tipe "Paket/Combo" di mana pengecekan stok menembus sampai ke resep anak produknya.
  - Otomatisasi konversi satuan (misal: Resep pakai Gram, Stok Gudang pakai Kg).
- **Routing API Lokal**: Frontend tidak memanggil server online, melainkan memanggil `api.dart` yang bertindak sebagai "server lokal" dan langsung mengeksekusi query SQLite.

### Backend (kayposfnbserver)
- **Prisma Schema UUID**: Schema database server sudah disesuaikan agar menggunakan UUID, selaras dengan database offline di aplikasi Flutter.

### CI/CD & OTA Updates
- **Cloudflare Worker**: Terdapat proxy Cloudflare yang bertugas menjembatani aplikasi untuk mengecek pembaruan (updates) terbaru dari rilis GitHub secara aman.

---

## 3. Strict Rules (ATURAN KETAT - DILARANG DILANGGAR)

1. **NO INTEGER IDs**: 
   - Jangan pernah membuat tabel baru dengan primary key `INTEGER AUTOINCREMENT`. Selalu gunakan tipe `TEXT` dan generate ID menggunakan `LocalDb.generateId()` (UUID v4).
   - Jangan pernah menggunakan konversi `int.parse()` atau `int.tryParse()` untuk memanipulasi ID, baik di API layer maupun di UI state (gunakan tipe data `dynamic` atau `String`).
2. **OFFLINE-FIRST ARCHITECTURE**:
   - Fitur inti seperti Kasir, Manajemen Produk, dan Resep HARUS bisa berjalan 100% tanpa internet. 
   - Jangan pernah membuat fungsi kasir bergantung pada HTTP request ke Fastify server. Semua transaksi harus masuk ke SQLite via `api.dart` terlebih dahulu (konsep Sinkronisasi di background).
3. **DO NOT TOUCH INVENTORY MATH**:
   - Logika kalkulasi stok efektif (`_getEffectiveStock` dan `_computeCartMaterialUsage` di `kasir_screen.dart`) dan pemotongan stok otomatis di `/checkout` handler (`api.dart`) sudah sangat stabil. Jangan diubah kecuali ada instruksi perbaikan bug yang sangat spesifik.
4. **DATABASE MIGRATION**:
   - SQLite tidak mendukung `ALTER TABLE` secara penuh. Jika ada perubahan skema tabel di masa depan, gunakan metode **Rename-Copy-Drop** di fungsi `onCreate`/`onUpgrade` pada `local_db.dart`.
5. **JANGAN PUSH LANGSUNG KE REPO PUBLIC**:
   - Repo `KAYPOSFNB-APP` (Public) dilarang dimodifikasi manual. Repo ini hanya boleh diisi dari otomatisasi sinkronisasi GitHub Actions.

---

## 4. CI/CD & Push Mechanism (Cara Deploy)

### A. Deploy Frontend Aplikasi (APK/Linux App)
Sistem ini menggunakan mekanisme **Private-to-Public Sync**.
1. Lakukan perubahan kode di folder `frontend` pada repo private `KAYPOSFNB`.
2. Commit dan Push ke branch `main`.
   ```bash
   git add .
   git commit -m "feat: fitur baru"
   git push origin main
   ```
3. **Memicu Build Release**: Buat Git Tag versi baru lalu push tag tersebut.
   ```bash
   git tag v1.0.60
   git push origin v1.0.60
   ```
4. **Alur Otomatisasi**:
   - GitHub Actions di repo private akan menyalin kode (beserta tag) lalu melakukan push paksa ke repo public `KAYPOSFNB-APP`.
   - GitHub Actions di repo public akan mendeteksi tag baru, lalu mem-build `.apk` dan `.deb`, kemudian mempublikasikannya ke halaman Releases GitHub.

### B. Deploy Backend Server (kayposfnbserver)
1. Lakukan perubahan kode di folder `kayposfnbserver`.
2. Commit dan push ke repo private `kayposfnbserver`.
   ```bash
   git add .
   git commit -m "update schema"
   git push origin main
   ```
3. Deploy ke server VPS produksi dilakukan dengan melakukan `git pull` dari VPS dan menjalankan `npm run build && pm2 restart kaypos`. (Atau melalui pipeline CI/CD backend jika nantinya dikonfigurasi).
