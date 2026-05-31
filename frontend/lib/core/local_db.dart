import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import '../services/inventory_ledger_service.dart';

class LocalDb {
  static Database? _db;
  static String? _cachedDbDir;

  /// Public access to the cached DB directory path (set during _init)
  static String? get cachedDbDir => _cachedDbDir;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  /// Close the database and reset the singleton so it can be re-initialized
  static Future<void> closeAndReset() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  static Future<Database> _init() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    _cachedDbDir = dbPath;
    final path = join(dbPath, 'kayposfnb.db');

    // Check for pending restore (staged before app exit)
    await _applyPendingRestore(dbPath, path);

    return await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // Harus diaktifkan secara eksplisit di SQLite agar aksi ON DELETE CASCADE berjalan
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onOpen: (db) async {
        // Safety migrations for columns that may not exist on older databases
        try { await db.execute('ALTER TABLE transactions ADD COLUMN discount_total REAL DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE transactions ADD COLUMN discount_type TEXT DEFAULT "system"'); } catch (_) {}
        try { await db.execute('ALTER TABLE transactions ADD COLUMN discount_by TEXT DEFAULT "system"'); } catch (_) {}
        try { await db.execute('ALTER TABLE discounts ADD COLUMN target_categories TEXT DEFAULT "[]"'); } catch (_) {}
        try { await db.execute('ALTER TABLE discounts ADD COLUMN target_products TEXT DEFAULT "[]"'); } catch (_) {}
        try { await db.execute('ALTER TABLE transaction_details ADD COLUMN discount_percent REAL DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE transaction_details ADD COLUMN discount_amount REAL DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE transaction_details ADD COLUMN addon_summary TEXT DEFAULT "[]"'); } catch (_) {}
        try { await db.execute('ALTER TABLE bahan_baku ADD COLUMN kategori TEXT DEFAULT "Lainnya"'); } catch (_) {}
        // Module: kategori_bahan table
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS kategori_bahan (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE
            )
          ''');
          // Seed default categories if table is empty
          final countResult = await db.rawQuery('SELECT COUNT(*) as c FROM kategori_bahan');
          final count = (countResult.first['c'] as num?)?.toInt() ?? 0;
          if (count == 0) {
            for (final k in ['Daging/Protein', 'Sayur/Buah', 'Bumbu', 'Kemasan', 'Lainnya']) {
              await db.insert('kategori_bahan', {'name': k}, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        } catch (_) {}
        try { await db.execute('ALTER TABLE bahan_baku ADD COLUMN kategori_bahan_id INTEGER DEFAULT 0'); } catch (_) {}
        // Module: Combo Meals (Paket)
        try { await db.execute('ALTER TABLE products ADD COLUMN is_paket INTEGER DEFAULT 0'); } catch (_) {}
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS paket_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              paket_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
              product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
              qty INTEGER NOT NULL DEFAULT 1,
              UNIQUE(paket_id, product_id)
            )
          ''');
        } catch (_) {}
        // Migrate old string kategori to kategori_bahan_id
        try {
          final rows = await db.rawQuery("SELECT id, kategori FROM bahan_baku WHERE kategori_bahan_id = 0 AND kategori IS NOT NULL AND kategori != ''");
          for (final row in rows) {
            final kName = row['kategori']?.toString() ?? 'Lainnya';
            final kRows = await db.query('kategori_bahan', where: 'name = ?', whereArgs: [kName]);
            if (kRows.isNotEmpty) {
              await db.update('bahan_baku', {'kategori_bahan_id': kRows.first['id']}, where: 'id = ?', whereArgs: [row['id']]);
            }
          }
        } catch (_) {}
        // Module: Inventory Ledger (Stock Opname & Kartu Stok)
        try { await InventoryLedgerService.ensureTable(); } catch (_) {}
      },
      onCreate: (db, version) async {
        // ──────────────────────────────────────────────────
        // 1. Categories (Menu groupings: Makanan, Minuman, etc.)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            icon TEXT DEFAULT '📦',
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 2. Products (Menu Items — NO standalone stock column)
        //    Stock capacity is dynamically calculated from bahan_baku via resep.
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
            barcode TEXT UNIQUE,
            price REAL NOT NULL DEFAULT 0,
            image_url TEXT DEFAULT '',
            description TEXT DEFAULT '',
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now','localtime')),
            updated_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 3a. Kategori Bahan (Raw Material Categories)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS kategori_bahan (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )
        ''');
        for (final k in ['Daging/Protein', 'Sayur/Buah', 'Bumbu', 'Kemasan', 'Lainnya']) {
          await db.insert('kategori_bahan', {'name': k}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // ──────────────────────────────────────────────────
        // 3b. Bahan Baku (Raw Materials / Ingredients)
        //    Central stock is tracked here, NOT on products.
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS bahan_baku (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            unit TEXT NOT NULL DEFAULT 'gram',
            stock REAL NOT NULL DEFAULT 0,
            cost_price REAL NOT NULL DEFAULT 0,
            min_stock_alert REAL DEFAULT 0,
            kategori TEXT DEFAULT 'Lainnya',
            kategori_bahan_id INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime')),
            updated_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 4. Resep (Recipe / Bill of Materials Mapping)
        //    Links a menu product to the raw materials it consumes.
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS resep (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            bahan_baku_id INTEGER NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
            qty_needed REAL NOT NULL DEFAULT 0,
            UNIQUE(product_id, bahan_baku_id)
          )
        ''');

        // ──────────────────────────────────────────────────
        // 4b. Paket Items (Combo Meal child products)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS paket_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            paket_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            qty INTEGER NOT NULL DEFAULT 1,
            UNIQUE(paket_id, product_id)
          )
        ''');

        // ──────────────────────────────────────────────────
        // 5. Add-on Categories (Modifier groups: Topping, Level Pedas, etc.)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS addon_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            is_required INTEGER DEFAULT 0,
            max_choices INTEGER DEFAULT 1,
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 6. Addons (Individual modifiers within a category)
        //    Optionally linked to bahan_baku for raw-material deduction.
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS addons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category_id INTEGER NOT NULL REFERENCES addon_categories(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            additional_price REAL NOT NULL DEFAULT 0,
            bahan_baku_id INTEGER REFERENCES bahan_baku(id) ON DELETE SET NULL,
            qty_needed REAL DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 7. Product–Addon Category Link (which addon groups apply to which menu items)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_addon_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            addon_category_id INTEGER NOT NULL REFERENCES addon_categories(id) ON DELETE CASCADE,
            UNIQUE(product_id, addon_category_id)
          )
        ''');

        // ──────────────────────────────────────────────────
        // 8. Restock History (Raw Material restocking log)
        //    Tracks bahan_baku restocking, NOT product-level restocking.
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS restock_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bahan_baku_id INTEGER NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
            added_stock REAL NOT NULL,
            total_cost REAL NOT NULL,
            old_cost_price REAL NOT NULL,
            new_cost_price REAL NOT NULL,
            timestamp TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 9. Discounts
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS discounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            target_categories TEXT DEFAULT '[]',
            target_products TEXT DEFAULT '[]',
            discount_percent INTEGER NOT NULL,
            schedule_type TEXT NOT NULL,
            schedule_value TEXT,
            is_active INTEGER DEFAULT 1
          )
        ''');

        // ──────────────────────────────────────────────────
        // 10. Users
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            password TEXT NOT NULL,
            pin TEXT NOT NULL DEFAULT '000000',
            role TEXT NOT NULL DEFAULT 'kasir',
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 11. Transactions
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cashier_id INTEGER REFERENCES users(id),
            cashier_name TEXT,
            total_amount REAL NOT NULL,
            discount_total REAL DEFAULT 0,
            discount_type TEXT DEFAULT 'system',
            discount_by TEXT DEFAULT 'system',
            paid_amount REAL NOT NULL,
            change_amount REAL NOT NULL,
            payment_method TEXT DEFAULT 'cash',
            note TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 12. Transaction Details (includes addon_summary JSON)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS transaction_details (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            sold_price REAL NOT NULL,
            quantity REAL NOT NULL,
            subtotal REAL NOT NULL,
            addon_summary TEXT DEFAULT '[]',
            discount_percent REAL DEFAULT 0,
            discount_amount REAL DEFAULT 0
          )
        ''');

        // ──────────────────────────────────────────────────
        // 13. Held Carts (Offline Parked Transactions)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS held_carts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            label TEXT NOT NULL,
            cart_data TEXT NOT NULL,
            total REAL NOT NULL DEFAULT 0,
            created_by INTEGER REFERENCES users(id),
            created_by_name TEXT,
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 14. Settings
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        // ══════════════════════════════════════════════════
        // SEEDING DEFAULT DATA
        // ══════════════════════════════════════════════════

        // Default Admin User
        await db.insert('users', {
          'username': 'admin',
          'name': 'Administrator',
          'password': 'admin',
          'pin': '000000',
          'role': 'admin'
        });

        // Default Kasir User
        await db.insert('users', {
          'username': 'kasir1',
          'name': 'Kasir Utama',
          'password': 'pwkasir',
          'pin': '123456',
          'role': 'kasir'
        });

        // Default Settings
        final batch = db.batch();
        batch.insert('settings', {'key': 'store_name', 'value': 'KAYPOS FNB Store'}, conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.insert('settings', {'key': 'store_address', 'value': ''}, conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.insert('settings', {'key': 'store_phone', 'value': ''}, conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.insert('settings', {'key': 'printer_port', 'value': '/dev/usb/lp0'}, conflictAlgorithm: ConflictAlgorithm.ignore);
        await batch.commit();
      },
    );
  }

  /// Swap staged restore file into place BEFORE any DB connection opens.
  /// This is the ONLY safe way to replace a sqflite_common_ffi database.
  static Future<void> _applyPendingRestore(String dbDir, String dbPath) async {
    try {
      final staged = File(join(dbDir, 'kaypos_restore_pending.db'));
      if (!await staged.exists()) return; // No pending restore

      // Delete old DB and all journal files (ignore errors if locked)
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) {
          try { await f.delete(); } catch (_) {}
        }
      }

      // Overwrite the active DB with the staged file
      await staged.copy(dbPath);
      await staged.delete();

      debugPrint('[LocalDb] ✅ Pending restore applied successfully');
    } catch (e) {
      debugPrint('[LocalDb] ❌ Failed to apply pending restore: $e');
    }
  }

  /// Stage a backup file for restore-on-next-startup.
  /// Call this, then exit the app. On next launch, _init() will apply it.
  /// IMPORTANT: Uses cached path — NEVER calls getDatabasesPath() which deadlocks FFI.
  static Future<String> stageRestore(String backupFilePath) async {
    if (_cachedDbDir == null) throw Exception('Database belum diinisialisasi');
    final stagingPath = join(_cachedDbDir!, 'kaypos_restore_pending.db');
    // Run file copy in a separate isolate to avoid blocking UI
    await compute(_copyFileIsolate, {'source': backupFilePath, 'target': stagingPath});
    return stagingPath;
  }

  /// Pure file copy in a separate Dart isolate — zero FFI, zero UI blocking
  static void _copyFileIsolate(Map<String, String> args) {
    File(args['source']!).copySync(args['target']!);
  }
}
