import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

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
    final path = join(dbPath, 'kaypos_offline.db');

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
        // Safety migration for new columns added in v1.0.35 without bumping version
        try { await db.execute('ALTER TABLE products ADD COLUMN base_unit TEXT DEFAULT ""'); } catch (_) {}
        try { await db.execute('ALTER TABLE inventory ADD COLUMN stock_unit TEXT DEFAULT ""'); } catch (_) {}
        try { await db.execute('ALTER TABLE transactions ADD COLUMN discount_total REAL DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE transactions ADD COLUMN discount_type TEXT DEFAULT "system"'); } catch (_) {}
        try { await db.execute('ALTER TABLE transactions ADD COLUMN discount_by TEXT DEFAULT "system"'); } catch (_) {}
        try { await db.execute('ALTER TABLE discounts ADD COLUMN target_categories TEXT DEFAULT "[]"'); } catch (_) {}
        try { await db.execute('ALTER TABLE discounts ADD COLUMN target_products TEXT DEFAULT "[]"'); } catch (_) {}
        try { await db.execute('ALTER TABLE transaction_details ADD COLUMN discount_percent REAL DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE transaction_details ADD COLUMN discount_amount REAL DEFAULT 0'); } catch (_) {}
      },
      onCreate: (db, version) async {
        // 1. Categories
        await db.execute('''
          CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            icon TEXT DEFAULT '📦',
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // Discounts
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

        // 2. Category Units
        await db.execute('''
          CREATE TABLE IF NOT EXISTS category_units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
            unit_name TEXT NOT NULL,
            sort_order INTEGER DEFAULT 0,
            UNIQUE(category_id, unit_name)
          )
        ''');

        // 3. Products
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
            barcode TEXT UNIQUE,
            purchase_price REAL DEFAULT 0,
            purchase_unit TEXT DEFAULT '',
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT (datetime('now','localtime')),
            updated_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // 4. Product Units
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            unit_name TEXT NOT NULL,
            qty_per_unit REAL NOT NULL DEFAULT 1,
            price REAL NOT NULL,
            UNIQUE(product_id, unit_name)
          )
        ''');

        // 5. Inventory
        await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory (
            product_id INTEGER PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
            stock_quantity REAL NOT NULL DEFAULT 0,
            min_stock_alert REAL DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // 6. Restock History
        await db.execute('''
          CREATE TABLE IF NOT EXISTS restock_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            added_base_stock REAL NOT NULL,
            total_cost REAL NOT NULL,
            old_purchase_price REAL NOT NULL,
            new_purchase_price REAL NOT NULL,
            timestamp TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // 7. Users
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

        // 8. Transactions
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

        // 9. Transaction Details
        await db.execute('''
          CREATE TABLE IF NOT EXISTS transaction_details (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            sold_price REAL NOT NULL,
            purchase_price REAL DEFAULT 0,
            quantity REAL NOT NULL,
            unit_used TEXT NOT NULL,
            subtotal REAL NOT NULL,
            discount_percent REAL DEFAULT 0,
            discount_amount REAL DEFAULT 0
          )
        ''');

        // 10. Held Carts (Offline Parked Transactions)
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

        // 11. Settings
        await db.execute('''
          CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        // SEEDING DEFAULT DATA
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
        batch.insert('settings', {'key': 'store_name', 'value': 'KAYPOS Offline Store'}, conflictAlgorithm: ConflictAlgorithm.ignore);
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
