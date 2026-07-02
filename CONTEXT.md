# KAYPOSFNB — Full Project Context

> **Tujuan dokumen ini:** Memberikan panduan lengkap bagi AI atau developer lain yang akan melanjutkan pengembangan proyek ini. Semua informasi arsitektur, alur kerja, CI/CD, dan struktur folder didokumentasikan di sini.

---

## 1. Gambaran Umum Aplikasi

**KayPOS FNB** adalah sistem Point of Sale (POS) untuk Food & Beverage yang dirancang dengan arsitektur **Offline-First**. Aplikasi ini berjalan sepenuhnya offline di perangkat lokal, menyimpan semua data di SQLite lokal, dan hanya membutuhkan koneksi server (opsional) untuk sinkronisasi antar perangkat.

### Arsitektur Utama

```
┌──────────────────────────────────────────────────────────┐
│                   PERANGKAT LOKAL                         │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐ │
│  │ Flutter App  │───▶│  api.dart    │───▶│  SQLite DB  │ │
│  │ (UI Layer)   │    │  (Embedded   │    │  kayposfnb  │ │
│  │              │    │   Router)    │    │   .db       │ │
│  └─────────────┘    └──────────────┘    └─────────────┘ │
│         │                                                │
│  ┌──────┴──────────────────────────────────┐            │
│  │  SyncService (Opsional, Manual Trigger) │            │
│  │  HTTP ↔ Fastify Server                  │            │
│  └─────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────┘
                         │ (LAN/Internet)
              ┌──────────┴──────────┐
              │  kayposfnbserver    │
              │  Fastify + Prisma   │
              │  SQLite (dev.db)    │
              └─────────────────────┘
```

### Poin Penting
- **TIDAK ADA REST API remote yang wajib.** File `api.dart` adalah **Embedded Local Router** — semua operasi CRUD dilakukan langsung ke SQLite lokal via query SQL. Bukan HTTP call.
- Server Fastify (`kayposfnbserver/`) hanya digunakan untuk **sinkronisasi data antar perangkat** (multi-device), bukan sebagai backend utama.
- Aplikasi bisa berjalan 100% offline tanpa server.

---

## 2. Repository & CI/CD

### 2.1 Dua Repository

| Repository | Visibility | Fungsi |
|---|---|---|
| `babycodes/KAYPOSFNB` | **Private** | Source code utama. Development dilakukan di sini. |
| `babycodes/KAYPOSFNB-APP` | **Public** | Repository distribusi. GitHub Actions berjalan di sini untuk build & release. |

### 2.2 Alur Deployment

```
Developer Push ke KAYPOSFNB (Private)
        │
        ├── git push origin master     ← Push ke private repo
        ├── git tag v1.x.x             ← Buat tag versi
        ├── git push origin v1.x.x     ← Push tag ke private
        │
        ├── git push public master --force  ← Sync code ke public repo
        └── git push public v1.x.x         ← Push tag ke public
                                                    │
                                           GitHub Actions TRIGGER
                                           (on push tags: "v*")
                                                    │
                                    ┌───────────────┼───────────────┐
                                    ▼               ▼               ▼
                              Build Android    Build Linux    Build Windows
                              (APK signed)    (DEB + RPM)    (EXE Installer)
                                    │               │               │
                                    └───────────────┼───────────────┘
                                                    ▼
                                          GitHub Release Created
                                          (KAYPOSFNB-APP repo)
```

### 2.3 GitHub Actions Workflow

File: `.github/workflows/manual_release.yml`

**Trigger:**
- Otomatis: Push tag `v*` ke repo public
- Manual: `workflow_dispatch` dengan input version tag

**Jobs:**
1. **build-android** — Build APK signed dengan keystore (secrets: `KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`)
2. **build-linux** — Build Flutter Linux → Package DEB & RPM via `fpm`
3. **build-windows** — Build Flutter Windows → Package EXE via Inno Setup

**PENTING — `[skip ci]`:**
- Tag `[skip ci]` dalam commit message hanya boleh digunakan pada commit yang TIDAK perlu men-trigger build di repo public.
- Karena code di-push dari private → public secara identik (termasuk commit message), `[skip ci]` pada commit message akan ikut terbawa dan **mencegah GitHub Actions di public repo berjalan**.
- **Solusi:** Jangan gunakan `[skip ci]` pada commit yang memiliki release tag.

### 2.4 GitHub Secrets (di repo Public)

| Secret | Fungsi |
|---|---|
| `PRIVATE_REPO_PAT` | Personal Access Token untuk checkout dari repo private |
| `KEYSTORE_BASE64` | Android signing keystore (base64 encoded) |
| `STORE_PASSWORD` | Keystore store password |
| `KEY_PASSWORD` | Keystore key password |
| `KEY_ALIAS` | Keystore key alias |

### 2.5 Git Remotes (Lokal)

```
origin  → git@github.com:babycodes/KAYPOSFNB.git      (Private - source)
public  → git@github.com:babycodes/KAYPOSFNB-APP.git   (Public - distribution)
```

---

## 3. Struktur Folder Proyek

```
KAYPOSFNB/
├── .github/workflows/
│   └── manual_release.yml          # CI/CD workflow (berjalan di repo PUBLIC)
│
├── frontend/                        # Flutter Application
│   ├── lib/
│   │   ├── main.dart               # Entry point aplikasi
│   │   │
│   │   ├── core/                   # Core infrastructure
│   │   │   ├── api.dart            # ⭐ EMBEDDED LOCAL ROUTER (bukan HTTP client!)
│   │   │   │                       #    Semua endpoint REST di-route langsung ke SQLite
│   │   │   │                       #    ~1900 baris, menangani semua CRUD operations
│   │   │   ├── local_db.dart       # SQLite database schema, migrations, seeds
│   │   │   ├── router.dart         # GoRouter navigation configuration
│   │   │   ├── auth_provider.dart  # Authentication state (ChangeNotifier)
│   │   │   ├── theme.dart          # Light & Dark theme definitions
│   │   │   ├── theme_provider.dart # Theme mode toggle state
│   │   │   └── helpers.dart        # Utility functions (format harga, toast, dll)
│   │   │
│   │   ├── features/               # Feature modules (by screen)
│   │   │   ├── splash/
│   │   │   │   └── splash_screen.dart     # Loading + auto-login check
│   │   │   │
│   │   │   ├── auth/
│   │   │   │   ├── login_screen.dart      # Login page
│   │   │   │   └── lock_screen.dart       # PIN lock screen
│   │   │   │
│   │   │   ├── kasir/                     # ⭐ CASHIER (POS) MODULE
│   │   │   │   ├── kasir_screen.dart      # Main POS screen (~107KB, core business logic)
│   │   │   │   │                          #   - Product grid, cart, checkout
│   │   │   │   │                          #   - _hasRecipe() gatekeeper logic
│   │   │   │   │                          #   - Addon selection, discount application
│   │   │   │   │                          #   - Hold/recall cart, refund
│   │   │   │   ├── widgets/
│   │   │   │   │   ├── product_card.dart  # Product tile dalam grid
│   │   │   │   │   └── cart_item_widget.dart # Cart item row
│   │   │   │   └── dialogs/
│   │   │   │       ├── payment_dialog.dart       # Dialog pembayaran
│   │   │   │       ├── receipt_modal.dart         # Preview struk
│   │   │   │       ├── confirm_dialog.dart        # Konfirmasi umum
│   │   │   │       └── printer_settings_dialog.dart # Setting printer
│   │   │   │
│   │   │   └── admin/                     # ⭐ ADMIN PANEL MODULE
│   │   │       ├── admin_shell.dart       # Shell layout (sidebar + header + theme toggle)
│   │   │       ├── admin_dashboard.dart   # Dashboard utama (statistik, grafik)
│   │   │       ├── produk_page.dart       # CRUD produk + recipe management
│   │   │       ├── paket_page.dart        # CRUD paket/combo meals
│   │   │       ├── kategori_page.dart     # CRUD kategori produk
│   │   │       ├── bahan_baku_page.dart   # CRUD inventory/bahan baku + restock
│   │   │       ├── kategori_bahan_page.dart # CRUD kategori inventory
│   │   │       ├── diskon_page.dart       # CRUD diskon (schedule-based)
│   │   │       ├── cashflow_page.dart     # Arus kas (income/expense tracking)
│   │   │       ├── kartu_stok_page.dart   # Stock Opname (fisik vs sistem)
│   │   │       ├── laporan_page.dart      # Laporan penjualan
│   │   │       ├── karyawan_page.dart     # CRUD karyawan (users)
│   │   │       ├── settings_page.dart     # Pengaturan toko + server sync + backup/restore
│   │   │       ├── waste_report_dialog.dart # Laporan waste (produk jadi & bahan mentah)
│   │   │       └── widgets/
│   │   │           └── kay_confirm_dialog.dart # Reusable confirm dialog
│   │   │
│   │   ├── services/                # Business logic services
│   │   │   ├── sync_service.dart    # ⭐ Sinkronisasi antar device via server
│   │   │   │                        #   - pushTransactions()    (Kasir → Server)
│   │   │   │                        #   - pullReports()         (Server → Admin)
│   │   │   │                        #   - pushMasterData()      (Admin → Server)
│   │   │   │                        #   - pullMasterData()      (Server → Kasir)
│   │   │   ├── inventory_ledger_service.dart  # Deduction/restock logic
│   │   │   ├── printer_service.dart          # ESC/POS thermal printer
│   │   │   ├── receipt_generator.dart        # Format struk untuk print
│   │   │   ├── update_service.dart           # In-app update via GitHub Releases
│   │   │   └── device_info_service.dart      # UUID perangkat (untuk sync)
│   │   │
│   │   └── shared/widgets/          # Shared UI components
│   │       ├── bounce_button.dart   # Animated button with bounce effect
│   │       └── theme_toggle.dart    # Light/dark mode toggle widget
│   │
│   ├── assets/
│   │   └── icon-512.png             # App icon
│   │
│   ├── android/                     # Android platform files
│   ├── linux/                       # Linux platform files
│   ├── windows/                     # Windows platform files
│   ├── ios/                         # iOS platform files (tidak aktif digunakan)
│   ├── macos/                       # macOS platform files (tidak aktif digunakan)
│   ├── web/                         # Web platform files (tidak aktif digunakan)
│   │
│   ├── pubspec.yaml                 # Dependencies & version
│   └── analysis_options.yaml        # Lint rules
│
├── kayposfnbserver/                 # ⭐ SYNC SERVER (Opsional)
│   ├── src/
│   │   └── index.ts                 # Fastify server (semua routes dalam 1 file)
│   ├── prisma/
│   │   ├── schema.prisma            # Database schema (SQLite)
│   │   ├── dev.db                   # Server database file
│   │   └── migrations/              # Prisma migrations
│   ├── public/                      # Static files (admin web dashboard)
│   ├── package.json                 # Node.js dependencies
│   └── tsconfig.json                # TypeScript config
│
├── CONTEXT.md                       # 📖 File ini
├── MAINTENANCE_SOP.md               # SOP maintenance
├── project_context.md               # Context lama (superseded by CONTEXT.md)
└── keystore_base64.txt              # Android signing keystore (base64)
```

---

## 4. Database Schema (SQLite Lokal)

File: `frontend/lib/core/local_db.dart`

### Tabel Utama

| Tabel | Fungsi | PK Type |
|---|---|---|
| `categories` | Kategori produk | TEXT (UUID) |
| `products` | Daftar produk (termasuk paket via `is_paket`) | TEXT (UUID) |
| `kategori_bahan` | Kategori bahan baku/inventory | TEXT (UUID) |
| `bahan_baku` | Bahan baku / inventory items | TEXT (UUID) |
| `resep` | Recipe/BOM — link product ↔ bahan_baku | TEXT (UUID) |
| `paket_items` | Isi paket/combo — link paket ↔ product | TEXT (UUID) |
| `addon_categories` | Kategori addon (mis: Level Pedas) | TEXT (UUID) |
| `addons` | Item addon (mis: Extra Pedas +Rp 2.000) | TEXT (UUID) |
| `product_addon_categories` | Junction: product ↔ addon_category | TEXT (UUID) |
| `discounts` | Diskon (schedule-based, per kategori/produk) | TEXT (UUID) |
| `users` | User (admin/kasir) dengan PIN | TEXT (UUID) |
| `transactions` | Transaksi penjualan | TEXT (UUID) |
| `transaction_details` | Detail item dalam transaksi | TEXT (UUID) |
| `inventory_ledger` | Log pergerakan stok (RESTOCK/SALE/WASTE/ADJUSTMENT/REFUND) | TEXT (UUID) |
| `held_carts` | Cart yang di-hold (sementara) | TEXT (UUID) |
| `settings` | Key-value settings (nama toko, dll) | TEXT (key) |
| `cashflow_categories` | Kategori arus kas | TEXT (UUID) |
| `cashflows` | Entri arus kas | TEXT (UUID) |

### Relasi Penting

```
products ──< resep >── bahan_baku          (Recipe: product butuh bahan_baku berapa)
products ──< paket_items >── products      (Paket: paket berisi produk apa saja)
products ──< product_addon_categories >── addon_categories ──< addons
transactions ──< transaction_details
bahan_baku ──< inventory_ledger            (Riwayat pergerakan stok)
```

---

## 5. Alur Kerja Aplikasi

### 5.1 Login & Routing

```
SplashScreen → cek auth tersimpan
  ├── Ada auth + admin role  → /admin (AdminDashboard)
  ├── Ada auth + kasir role  → /kasir (KasirScreen)
  └── Tidak ada auth         → /login (LoginScreen)
```

- Login menggunakan username + password yang disimpan di tabel `users` lokal
- Auth state dikelola oleh `AuthProvider` (ChangeNotifier)
- Fitur **Lock Screen**: kasir bisa mengunci layar (PIN 6 digit)

### 5.2 Alur Kasir (POS)

```
1. Kasir login → KasirScreen
2. Produk ditampilkan dalam grid (difilter oleh _hasRecipe):
   - Produk biasa: harus punya ≥1 resep (entry di tabel resep)
   - Produk paket: SEMUA child products harus punya ≥1 resep
   - Produk tanpa inventory/resep TIDAK ditampilkan
3. Kasir tap produk → masuk ke cart
   - Jika produk punya addon → tampil addon picker
4. Kasir bisa: adjust qty, add note, apply discount
5. Checkout → PaymentDialog (input nominal bayar)
6. Transaksi disimpan ke `transactions` + `transaction_details`
7. Inventory otomatis dikurangi via InventoryLedgerService
8. Struk bisa di-print via thermal printer (ESC/POS)
```

### 5.3 Alur Admin

Admin panel menggunakan `AdminShell` (sidebar navigation):

- **Dashboard**: Statistik penjualan, grafik, ringkasan
- **Produk**: CRUD produk, atur resep/inventory, badge "INVENTORY KOSONG"
- **Paket**: CRUD combo meals, badge "PAKET KOSONG" / "PRODUK INVENTORY KOSONG"
- **Kategori Produk**: CRUD kategori
- **Inventory (Bahan Baku)**: CRUD bahan baku, restock, stock alerts
- **Kategori Inventory**: CRUD kategori bahan
- **Diskon**: CRUD diskon berbasis jadwal
- **Cashflow**: Tracking pemasukan/pengeluaran manual
- **Stok Opname**: Rekonsiliasi stok fisik vs sistem
- **Laporan**: Laporan penjualan dengan filter tanggal
- **Karyawan**: CRUD user (admin/kasir)
- **Pengaturan**: Setting toko, koneksi server, backup/restore DB

### 5.4 Validasi Inventory (Business Rules)

Produk **TIDAK akan ditampilkan** di kasir jika:
- Produk biasa: belum memiliki resep/inventory (`resep` table kosong untuk produk tersebut)
- Produk paket: salah satu atau lebih child product belum memiliki resep

Di admin panel, produk/paket yang belum valid ditandai dengan badge peringatan:
- 🔴 "INVENTORY KOSONG" pada produk
- 🟡 "PAKET KOSONG" pada paket tanpa isi
- 🟠 "PRODUK INVENTORY KOSONG" pada paket yang berisi produk tanpa inventory

---

## 6. Sinkronisasi Multi-Device

### 6.1 Arsitektur Sync

Server (`kayposfnbserver/`) berfungsi sebagai **relay/hub** untuk sinkronisasi data antar perangkat. Alur sync **SELALU manual** (user trigger), tidak ada auto-sync.

```
┌──────────────┐            ┌──────────────┐           ┌──────────────┐
│   ADMIN      │            │   SERVER     │           │   KASIR      │
│   Device     │            │  (Fastify)   │           │   Device     │
│              │            │              │           │              │
│  pushMaster ─┼──────────▶│  SyncRecord  │◀──────────┼─ pullMaster  │
│  Data()      │            │  (tabel)     │           │  Data()      │
│              │            │              │           │              │
│  pullReports─┼──◀─────────┼─ SyncedTx   │◀──────────┼─ pushTx()   │
│  ()          │            │  (tabel)     │           │              │
└──────────────┘            └──────────────┘           └──────────────┘
```

### 6.2 Alur Sync Detail

| Aksi | Dari | Ke | Method | Data |
|---|---|---|---|---|
| **Kirim Update** | Admin | Server | `pushMasterData()` | Produk, kategori, bahan baku, resep, diskon, settings, dll |
| **Tarik Update** | Server | Kasir | `pullMasterData()` | Sama seperti di atas |
| **Kirim Laporan** | Kasir | Server | `pushTransactions()` | Transaksi + inventory ledger (SALE/WASTE/REFUND) |
| **Terima Laporan** | Server | Admin | `pullReports()` | Sama seperti di atas |

### 6.3 Server Schema (Prisma)

| Model | Fungsi |
|---|---|
| `AdminUser` | Login admin web dashboard server |
| `DeviceWhitelist` | Daftar perangkat terdaftar (UUID-based) |
| `ServerConfig` | Konfigurasi server (PIN pairing) |
| `SyncedTransaction` | Transaksi yang di-push oleh kasir |
| `SyncRecord` | Master data yang di-push oleh admin |

### 6.4 Pairing Device

1. Server generate PIN 6 digit
2. Client (app) masukkan IP server + PIN
3. Server verify PIN → whitelist device UUID
4. Device terdaftar bisa sync

### 6.5 Penanganan Error Sync

Semua error koneksi ditampilkan sebagai pesan user-friendly:
- `"Server tidak tersambung. Periksa koneksi."` (bukan raw exception)
- Detail error di-log ke `debugPrint()` untuk debugging

---

## 7. In-App Update System

File: `frontend/lib/services/update_service.dart`

Aplikasi mengecek update dari GitHub Releases di repo **public** (`KAYPOSFNB-APP`):

```
1. Cek GitHub API: /repos/babycodes/KAYPOSFNB-APP/releases/latest
2. Bandingkan versi: local vs remote (semver comparison)
3. Jika ada update baru:
   - Download binary sesuai platform (.apk/.deb/.rpm/.exe)
   - Install otomatis (atau buka file manager)
```

Platform detection:
- Android → `.apk`
- Linux (Fedora/RHEL) → `.rpm`
- Linux (Ubuntu/Debian) → `.deb`
- Windows → `.exe`

---

## 8. Tema & UI

### 8.1 Dual Theme

File: `frontend/lib/core/theme.dart`

| Theme | Nama | Warna Utama | Surface |
|---|---|---|---|
| Light | "Fresh Green" | `#2E7D32` (green) | Sage tinted surfaces |
| Dark | "Night Kitchen" | `#FFB74D` (amber) | Coffee brown surfaces |

### 8.2 Sidebar

- **Light mode**: Green sidebar (`#1B5E20` gradient)
- **Dark mode**: Coffee sidebar (dari `surfaceBright`)
- Collapsible (label/icon-only mode)
- Badge notifikasi pada Inventory (stok rendah/habis)

### 8.3 Theme Toggle

Tersedia di:
- Admin Dashboard header (pojok kanan atas) — `IconButton` sun/moon
- Login screen
- Kasir screen

State dikelola oleh `ThemeProvider` (persisted via `SharedPreferences`).

---

## 9. Key Dependencies

| Package | Fungsi |
|---|---|
| `sqflite` / `sqflite_common_ffi` | SQLite database (mobile + desktop) |
| `provider` | State management |
| `go_router` | Navigation / routing |
| `shared_preferences` | Persistent key-value storage |
| `http` | HTTP client (hanya untuk sync + update check) |
| `flutter_pos_printer_platform_image_3` | Thermal printer (ESC/POS) |
| `esc_pos_utils_plus` | Generate ESC/POS commands |
| `bot_toast` | Toast notifications |
| `flutter_phoenix` | App restart (setelah restore DB) |
| `uuid` | Generate UUID v4 untuk primary keys |
| `package_info_plus` | Baca versi aplikasi |
| `open_filex` | Buka file installer (update) |
| `image` | Image processing (untuk printer) |

---

## 10. Konvensi Pengembangan

### 10.1 Versioning

Format: `MAJOR.MINOR.PATCH+BUILD_NUMBER`
- Contoh: `1.3.12+312`
- Build number = versi tanpa titik (1.3.12 → 312)
- Tag git: `v1.3.12`

### 10.2 Commit Messages

```
feat: ...      → Fitur baru
fix: ...       → Bug fix
release: ...   → Bump versi (JANGAN pakai [skip ci] jika perlu trigger build)
```

### 10.3 Release Checklist

1. Edit code
2. `flutter analyze` — pastikan tidak ada error baru
3. Bump versi di `pubspec.yaml`
4. `git add -A && git commit -m "release: vX.Y.Z - deskripsi"`
5. `git tag vX.Y.Z`
6. `git push origin master && git push origin vX.Y.Z`
7. `git push public master --force && git push public vX.Y.Z`
8. Verifikasi GitHub Actions berjalan di repo public

### 10.4 Hal yang Perlu Diperhatikan

1. **`api.dart` bukan HTTP client** — Ini embedded router. Semua `Api.get('/path')` dan `Api.post('/path')` langsung query SQLite. Jangan bingung dengan arsitektur API tradisional.

2. **Jangan tambah `[skip ci]` pada release commit** — Commit message disalin identik ke repo public. `[skip ci]` akan mencegah build.

3. **`_hasRecipe()` di `kasir_screen.dart`** — Ini gatekeeper utama. Produk/paket tanpa inventory TIDAK akan muncul di POS. Jangan bypass logic ini.

4. **Migrasi database dilakukan di `onOpen`** — Bukan di `onUpgrade`. Semua migrasi menggunakan `try-catch` agar aman dijalankan berulang kali (idempotent). Pattern: `ALTER TABLE ... ADD COLUMN ...` yang di-catch jika kolom sudah ada.

5. **Sync cursor (timestamp)** — `last_report_pull`, `last_master_push`, `last_master_pull` di SharedPreferences mengontrol data mana yang sudah di-sync. Jangan reset sembarangan.

6. **UUID sebagai Primary Key** — Semua tabel menggunakan UUID v4 (TEXT) sebagai PK. Ini memungkinkan data dari multiple device tidak konflik saat sync.

---

## 11. Menjalankan Aplikasi

### Flutter App (Frontend)

```bash
cd frontend
flutter pub get
flutter run -d linux    # atau -d android, -d windows
```

### Sync Server (Opsional)

```bash
cd kayposfnbserver
npm install
npx prisma generate
npx prisma migrate deploy
npm run dev             # Development (auto-reload)
# atau
npm start               # Production
```

Server berjalan di `http://0.0.0.0:8080`

### Build Release

```bash
cd frontend
flutter build apk --release          # Android
flutter build linux --release         # Linux
flutter build windows --release       # Windows
```

---

## 12. FAQ untuk AI/Developer Baru

**Q: Kenapa `api.dart` sangat besar (83KB)?**
A: Karena ini bukan HTTP client biasa. Ini adalah embedded router yang menangani SEMUA operasi database. Setiap endpoint REST (GET/POST/PUT/DELETE) di-implementasikan sebagai fungsi yang langsung query SQLite. Ini inti dari arsitektur offline-first.

**Q: Dimana backend/server API-nya?**
A: Tidak ada backend API untuk operasi utama. Semua CRUD berjalan lokal. `kayposfnbserver/` hanya untuk sinkronisasi multi-device dan admin web dashboard server.

**Q: Kenapa ada 2 repo?**
A: Repo private (`KAYPOSFNB`) menyimpan source code + keystore. Repo public (`KAYPOSFNB-APP`) digunakan untuk GitHub Actions build karena menyediakan runner gratis, dan untuk hosting GitHub Releases agar user bisa download update.

**Q: Bagaimana cara kerja printer?**
A: Menggunakan ESC/POS protocol via USB (`/dev/usb/lp0` di Linux). File: `printer_service.dart` (koneksi) dan `receipt_generator.dart` (format struk).

**Q: Apa bedanya `bahan_baku` dan `resep`?**
A: `bahan_baku` = item inventory (mis: Ayam, Beras, Minyak). `resep` = junction table yang menghubungkan produk dengan bahan_baku (berapa qty bahan_baku yang dibutuhkan per produk). Saat transaksi, stok `bahan_baku` otomatis dikurangi sesuai `resep`.
