import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class LocalDb {
  static Database? _db;
  static String? _cachedDbDir;
  static const _uuid = Uuid();

  /// Generate a new UUID v4 for database records
  static String generateId() => _uuid.v4();

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
      version: 2,
      onConfigure: (db) async {
        // Harus diaktifkan secara eksplisit di SQLite agar aksi ON DELETE CASCADE berjalan
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateIntToUuid(db);
        }
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
        try { await db.execute('ALTER TABLE transactions ADD COLUMN is_synced INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE bahan_baku ADD COLUMN kategori TEXT DEFAULT "Lainnya"'); } catch (_) {}
        
        // Add updated_at to junction tables for sync support
        try { await db.execute('ALTER TABLE resep ADD COLUMN updated_at TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE paket_items ADD COLUMN updated_at TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE product_addon_categories ADD COLUMN updated_at TEXT'); } catch (_) {}
        // Backfill NULL updated_at so pushMasterData() can find these rows
        try { await db.execute("UPDATE resep SET updated_at = datetime('now','localtime') WHERE updated_at IS NULL"); } catch (_) {}
        try { await db.execute("UPDATE paket_items SET updated_at = datetime('now','localtime') WHERE updated_at IS NULL"); } catch (_) {}
        try { await db.execute("UPDATE product_addon_categories SET updated_at = datetime('now','localtime') WHERE updated_at IS NULL"); } catch (_) {}
        
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
        await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory_ledger (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            bahan_baku_id     INTEGER NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
            timestamp         TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
            transaction_type  TEXT    NOT NULL CHECK(transaction_type IN ('RESTOCK','SALE','WASTE','ADJUSTMENT','REFUND')),
            qty_change        REAL    NOT NULL,
            financial_value   REAL    NOT NULL DEFAULT 0,
            notes             TEXT    DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_ledger_bahan_ts
          ON inventory_ledger (bahan_baku_id, timestamp)
        ''');

        // Migrate CHECK constraint to include REFUND for existing DBs
        try {
          final res = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name='inventory_ledger'");
          if (res.isNotEmpty) {
            final sql = res.first['sql']?.toString() ?? '';
            if (!sql.contains("'REFUND'")) {
              await db.execute('ALTER TABLE inventory_ledger RENAME TO _old_inventory_ledger');
              await db.execute('''
                CREATE TABLE inventory_ledger (
                  id                TEXT PRIMARY KEY,
                  bahan_baku_id     TEXT NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
                  timestamp         TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
                  transaction_type  TEXT    NOT NULL CHECK(transaction_type IN ('RESTOCK','SALE','WASTE','ADJUSTMENT','REFUND')),
                  qty_change        REAL    NOT NULL,
                  financial_value   REAL    NOT NULL DEFAULT 0,
                  notes             TEXT    DEFAULT '',
                  is_synced         INTEGER DEFAULT 0
                )
              ''');
              await db.execute('''
                INSERT INTO inventory_ledger (id, bahan_baku_id, timestamp, transaction_type, qty_change, financial_value, notes)
                SELECT id, bahan_baku_id, timestamp, transaction_type, qty_change, financial_value, notes
                FROM _old_inventory_ledger
              ''');
              await db.execute('DROP TABLE _old_inventory_ledger');
              await db.execute('''
                CREATE INDEX IF NOT EXISTS idx_ledger_bahan_ts
                ON inventory_ledger (bahan_baku_id, timestamp)
              ''');
            }
            
            // Add is_synced if missing
            if (!sql.contains("is_synced")) {
              try { await db.execute('ALTER TABLE inventory_ledger ADD COLUMN is_synced INTEGER DEFAULT 0'); } catch (_) {}
            }
          }
        } catch (e) {
          debugPrint('Inventory ledger migration error: $e');
        }
        // Module: Partial Refund support columns
        try { await db.execute("ALTER TABLE transactions ADD COLUMN status TEXT DEFAULT 'completed'"); } catch (_) {}
        try { await db.execute('ALTER TABLE transaction_details ADD COLUMN refunded_qty REAL DEFAULT 0'); } catch (_) {}
      },
      onCreate: (db, version) async {
        // ──────────────────────────────────────────────────
        // 1. Categories
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            icon TEXT DEFAULT '📦',
            sort_order INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime')),
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 2. Products
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
            barcode TEXT UNIQUE,
            price REAL NOT NULL DEFAULT 0,
            image_url TEXT DEFAULT '',
            description TEXT DEFAULT '',
            is_active INTEGER DEFAULT 1,
            is_paket INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime')),
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 3a. Kategori Bahan (Raw Material Categories)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS kategori_bahan (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');
        for (final k in ['Daging/Protein', 'Sayur/Buah', 'Bumbu', 'Kemasan', 'Lainnya']) {
          await db.insert('kategori_bahan', {'id': generateId(), 'name': k}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }

        // ──────────────────────────────────────────────────
        // 3b. Bahan Baku (Raw Materials / Ingredients)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS bahan_baku (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            unit TEXT NOT NULL DEFAULT 'gram',
            stock REAL NOT NULL DEFAULT 0,
            cost_price REAL NOT NULL DEFAULT 0,
            min_stock_alert REAL DEFAULT 0,
            kategori TEXT DEFAULT 'Lainnya',
            kategori_bahan_id TEXT DEFAULT '',
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime')),
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 4. Resep (Recipe / Bill of Materials)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS resep (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            bahan_baku_id TEXT NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
            qty_needed REAL NOT NULL DEFAULT 0,
            UNIQUE(product_id, bahan_baku_id)
          )
        ''');

        // ──────────────────────────────────────────────────
        // 4b. Paket Items (Combo Meal child products)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS paket_items (
            id TEXT PRIMARY KEY,
            paket_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            qty INTEGER NOT NULL DEFAULT 1,
            UNIQUE(paket_id, product_id)
          )
        ''');

        // ──────────────────────────────────────────────────
        // 5. Add-on Categories
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS addon_categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            is_required INTEGER DEFAULT 0,
            max_choices INTEGER DEFAULT 1,
            sort_order INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime')),
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 6. Addons
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS addons (
            id TEXT PRIMARY KEY,
            category_id TEXT NOT NULL REFERENCES addon_categories(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            additional_price REAL NOT NULL DEFAULT 0,
            bahan_baku_id TEXT REFERENCES bahan_baku(id) ON DELETE SET NULL,
            qty_needed REAL DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime')),
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 7. Product–Addon Category Link
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_addon_categories (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
            addon_category_id TEXT NOT NULL REFERENCES addon_categories(id) ON DELETE CASCADE,
            UNIQUE(product_id, addon_category_id)
          )
        ''');

        // ──────────────────────────────────────────────────
        // 8. Restock History
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS restock_history (
            id TEXT PRIMARY KEY,
            bahan_baku_id TEXT NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
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
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            target_categories TEXT DEFAULT '[]',
            target_products TEXT DEFAULT '[]',
            discount_percent INTEGER NOT NULL,
            schedule_type TEXT NOT NULL,
            schedule_value TEXT,
            is_active INTEGER DEFAULT 1,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 10. Users
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
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
            id TEXT PRIMARY KEY,
            cashier_id TEXT REFERENCES users(id),
            cashier_name TEXT,
            total_amount REAL NOT NULL,
            discount_total REAL DEFAULT 0,
            discount_type TEXT DEFAULT 'system',
            discount_by TEXT DEFAULT 'system',
            paid_amount REAL NOT NULL,
            change_amount REAL NOT NULL,
            payment_method TEXT DEFAULT 'cash',
            note TEXT,
            status TEXT DEFAULT 'completed',
            is_synced INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            updated_at TEXT DEFAULT (datetime('now','localtime')),
            created_at TEXT DEFAULT (datetime('now','localtime'))
          )
        ''');

        // ──────────────────────────────────────────────────
        // 12. Transaction Details
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS transaction_details (
            id TEXT PRIMARY KEY,
            transaction_id TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
            product_id TEXT NOT NULL,
            product_name TEXT NOT NULL,
            sold_price REAL NOT NULL,
            quantity REAL NOT NULL,
            subtotal REAL NOT NULL,
            addon_summary TEXT DEFAULT '[]',
            discount_percent REAL DEFAULT 0,
            discount_amount REAL DEFAULT 0,
            refunded_qty REAL DEFAULT 0
          )
        ''');

        // ──────────────────────────────────────────────────
        // 13. Held Carts (Local-only, temp data)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS held_carts (
            id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            cart_data TEXT NOT NULL,
            total REAL NOT NULL DEFAULT 0,
            created_by TEXT REFERENCES users(id),
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

        // ──────────────────────────────────────────────────
        // 15. Inventory Ledger (Stock Opname & Kartu Stok)
        // ──────────────────────────────────────────────────
        await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory_ledger (
            id                TEXT PRIMARY KEY,
            bahan_baku_id     TEXT NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
            timestamp         TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
            transaction_type  TEXT    NOT NULL CHECK(transaction_type IN ('RESTOCK','SALE','WASTE','ADJUSTMENT','REFUND')),
            qty_change        REAL    NOT NULL,
            financial_value   REAL    NOT NULL DEFAULT 0,
            notes             TEXT    DEFAULT '',
            is_synced         INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_ledger_bahan_ts
          ON inventory_ledger (bahan_baku_id, timestamp)
        ''');

        // ══════════════════════════════════════════════════
        // SEEDING DEFAULT DATA
        // ══════════════════════════════════════════════════

        // Default Admin User
        await db.insert('users', {
          'id': generateId(),
          'username': 'admin',
          'name': 'Administrator',
          'password': 'admin',
          'pin': '000000',
          'role': 'admin'
        });

        // Default Kasir User
        await db.insert('users', {
          'id': generateId(),
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

  /// Migrate all tables from INTEGER AUTOINCREMENT PKs to TEXT UUID PKs.
  /// Uses rename-copy-drop pattern with UUID mapping tables.
  static Future<void> _migrateIntToUuid(Database db) async {
    debugPrint('[LocalDb] 🔄 Starting UUID migration (v1 → v2)...');
    await db.execute('PRAGMA foreign_keys = OFF');

    // Tables that need PK migration (order: parents first, children last)
    final migrationTables = [
      'categories', 'kategori_bahan', 'users', 'addon_categories', 'discounts',
      'products', 'bahan_baku',
      'resep', 'paket_items', 'addons', 'product_addon_categories',
      'restock_history', 'transactions',
      'transaction_details', 'held_carts', 'inventory_ledger',
    ];

    // Step 1: Create mapping tables + populate UUIDs
    for (final t in migrationTables) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS _map_$t (old_id INTEGER PRIMARY KEY, new_id TEXT NOT NULL)');
        final rows = await db.query(t, columns: ['id']);
        for (final r in rows) {
          await db.insert('_map_$t', {'old_id': r['id'], 'new_id': _uuid.v4()});
        }
      } catch (e) {
        debugPrint('[LocalDb] Skip mapping $t: $e');
      }
    }

    // Helper to get mapped UUID
    Future<String?> mapped(String table, dynamic oldId) async {
      if (oldId == null) return null;
      final r = await db.query('_map_$table', where: 'old_id = ?', whereArgs: [oldId]);
      return r.isNotEmpty ? r.first['new_id'] as String : null;
    }

    // Step 2: Migrate each table
    try {
      // --- categories ---
      await _remakeTable(db, 'categories',
        'id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, icon TEXT, sort_order INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, updated_at TEXT, created_at TEXT',
        (row) async => {'id': await mapped('categories', row['id']), 'name': row['name'], 'icon': row['icon'] ?? '📦', 'sort_order': row['sort_order'] ?? 0, 'is_deleted': 0, 'updated_at': row['created_at'], 'created_at': row['created_at']});

      // --- kategori_bahan ---
      await _remakeTable(db, 'kategori_bahan',
        'id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, is_deleted INTEGER DEFAULT 0, updated_at TEXT',
        (row) async => {'id': await mapped('kategori_bahan', row['id']), 'name': row['name'], 'is_deleted': 0, 'updated_at': DateTime.now().toIso8601String()});

      // --- users ---
      await _remakeTable(db, 'users',
        'id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, name TEXT NOT NULL, password TEXT NOT NULL, pin TEXT NOT NULL DEFAULT "000000", role TEXT NOT NULL DEFAULT "kasir", is_active INTEGER DEFAULT 1, created_at TEXT',
        (row) async => {'id': await mapped('users', row['id']), 'username': row['username'], 'name': row['name'], 'password': row['password'], 'pin': row['pin'] ?? '000000', 'role': row['role'] ?? 'kasir', 'is_active': row['is_active'] ?? 1, 'created_at': row['created_at']});

      // --- addon_categories ---
      await _remakeTable(db, 'addon_categories',
        'id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, is_required INTEGER DEFAULT 0, max_choices INTEGER DEFAULT 1, sort_order INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, updated_at TEXT, created_at TEXT',
        (row) async => {'id': await mapped('addon_categories', row['id']), 'name': row['name'], 'is_required': row['is_required'] ?? 0, 'max_choices': row['max_choices'] ?? 1, 'sort_order': row['sort_order'] ?? 0, 'is_deleted': 0, 'updated_at': row['created_at'], 'created_at': row['created_at']});

      // --- discounts ---
      await _remakeTable(db, 'discounts',
        'id TEXT PRIMARY KEY, name TEXT NOT NULL, target_categories TEXT, target_products TEXT, discount_percent INTEGER NOT NULL, schedule_type TEXT NOT NULL, schedule_value TEXT, is_active INTEGER DEFAULT 1, is_deleted INTEGER DEFAULT 0, updated_at TEXT',
        (row) async => {'id': await mapped('discounts', row['id']), 'name': row['name'], 'target_categories': row['target_categories'] ?? '[]', 'target_products': row['target_products'] ?? '[]', 'discount_percent': row['discount_percent'], 'schedule_type': row['schedule_type'], 'schedule_value': row['schedule_value'], 'is_active': row['is_active'] ?? 1, 'is_deleted': 0, 'updated_at': DateTime.now().toIso8601String()});

      // --- products ---
      await _remakeTable(db, 'products',
        'id TEXT PRIMARY KEY, name TEXT NOT NULL, category_id TEXT, barcode TEXT UNIQUE, price REAL NOT NULL DEFAULT 0, image_url TEXT, description TEXT, is_active INTEGER DEFAULT 1, is_paket INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, updated_at TEXT, created_at TEXT',
        (row) async => {'id': await mapped('products', row['id']), 'name': row['name'], 'category_id': await mapped('categories', row['category_id']), 'barcode': row['barcode'], 'price': row['price'], 'image_url': row['image_url'], 'description': row['description'], 'is_active': row['is_active'] ?? 1, 'is_paket': row['is_paket'] ?? 0, 'is_deleted': 0, 'updated_at': row['updated_at'] ?? row['created_at'], 'created_at': row['created_at']});

      // --- bahan_baku ---
      await _remakeTable(db, 'bahan_baku',
        'id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, unit TEXT NOT NULL DEFAULT "gram", stock REAL NOT NULL DEFAULT 0, cost_price REAL NOT NULL DEFAULT 0, min_stock_alert REAL DEFAULT 0, kategori TEXT, kategori_bahan_id TEXT DEFAULT "", is_deleted INTEGER DEFAULT 0, updated_at TEXT, created_at TEXT',
        (row) async => {'id': await mapped('bahan_baku', row['id']), 'name': row['name'], 'unit': row['unit'], 'stock': row['stock'], 'cost_price': row['cost_price'], 'min_stock_alert': row['min_stock_alert'], 'kategori': row['kategori'], 'kategori_bahan_id': (await mapped('kategori_bahan', row['kategori_bahan_id'])) ?? '', 'is_deleted': 0, 'updated_at': row['updated_at'] ?? row['created_at'], 'created_at': row['created_at']});

      // --- resep ---
      await _remakeTable(db, 'resep',
        'id TEXT PRIMARY KEY, product_id TEXT NOT NULL, bahan_baku_id TEXT NOT NULL, qty_needed REAL NOT NULL DEFAULT 0, updated_at TEXT, UNIQUE(product_id, bahan_baku_id)',
        (row) async => {'id': await mapped('resep', row['id']), 'product_id': await mapped('products', row['product_id']), 'bahan_baku_id': await mapped('bahan_baku', row['bahan_baku_id']), 'qty_needed': row['qty_needed'], 'updated_at': row['updated_at']});

      // --- paket_items ---
      await _remakeTable(db, 'paket_items',
        'id TEXT PRIMARY KEY, paket_id TEXT NOT NULL, product_id TEXT NOT NULL, qty INTEGER NOT NULL DEFAULT 1, updated_at TEXT, UNIQUE(paket_id, product_id)',
        (row) async => {'id': await mapped('paket_items', row['id']), 'paket_id': await mapped('products', row['paket_id']), 'product_id': await mapped('products', row['product_id']), 'qty': row['qty'], 'updated_at': row['updated_at']});

      // --- addons ---
      await _remakeTable(db, 'addons',
        'id TEXT PRIMARY KEY, category_id TEXT NOT NULL, name TEXT NOT NULL, additional_price REAL NOT NULL DEFAULT 0, bahan_baku_id TEXT, qty_needed REAL DEFAULT 0, is_active INTEGER DEFAULT 1, is_deleted INTEGER DEFAULT 0, updated_at TEXT, created_at TEXT',
        (row) async => {'id': await mapped('addons', row['id']), 'category_id': await mapped('addon_categories', row['category_id']), 'name': row['name'], 'additional_price': row['additional_price'], 'bahan_baku_id': await mapped('bahan_baku', row['bahan_baku_id']), 'qty_needed': row['qty_needed'], 'is_active': row['is_active'] ?? 1, 'is_deleted': 0, 'updated_at': row['created_at'], 'created_at': row['created_at']});

      // --- product_addon_categories ---
      await _remakeTable(db, 'product_addon_categories',
        'id TEXT PRIMARY KEY, product_id TEXT NOT NULL, addon_category_id TEXT NOT NULL, updated_at TEXT, UNIQUE(product_id, addon_category_id)',
        (row) async => {'id': await mapped('product_addon_categories', row['id']), 'product_id': await mapped('products', row['product_id']), 'addon_category_id': await mapped('addon_categories', row['addon_category_id']), 'updated_at': row['updated_at']});

      // --- restock_history ---
      await _remakeTable(db, 'restock_history',
        'id TEXT PRIMARY KEY, bahan_baku_id TEXT NOT NULL, added_stock REAL NOT NULL, total_cost REAL NOT NULL, old_cost_price REAL NOT NULL, new_cost_price REAL NOT NULL, timestamp TEXT',
        (row) async => {'id': await mapped('restock_history', row['id']), 'bahan_baku_id': await mapped('bahan_baku', row['bahan_baku_id']), 'added_stock': row['added_stock'], 'total_cost': row['total_cost'], 'old_cost_price': row['old_cost_price'], 'new_cost_price': row['new_cost_price'], 'timestamp': row['timestamp']});

      // --- transactions ---
      await _remakeTable(db, 'transactions',
        'id TEXT PRIMARY KEY, cashier_id TEXT, cashier_name TEXT, total_amount REAL NOT NULL, discount_total REAL DEFAULT 0, discount_type TEXT, discount_by TEXT, paid_amount REAL NOT NULL, change_amount REAL NOT NULL, payment_method TEXT, note TEXT, status TEXT DEFAULT "completed", is_synced INTEGER DEFAULT 0, is_deleted INTEGER DEFAULT 0, updated_at TEXT, created_at TEXT',
        (row) async => {'id': await mapped('transactions', row['id']), 'cashier_id': await mapped('users', row['cashier_id']), 'cashier_name': row['cashier_name'], 'total_amount': row['total_amount'], 'discount_total': row['discount_total'] ?? 0, 'discount_type': row['discount_type'], 'discount_by': row['discount_by'], 'paid_amount': row['paid_amount'], 'change_amount': row['change_amount'], 'payment_method': row['payment_method'], 'note': row['note'], 'status': row['status'] ?? 'completed', 'is_synced': row['is_synced'] ?? 0, 'is_deleted': 0, 'updated_at': row['created_at'], 'created_at': row['created_at']});

      // --- transaction_details ---
      await _remakeTable(db, 'transaction_details',
        'id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, product_name TEXT NOT NULL, sold_price REAL NOT NULL, quantity REAL NOT NULL, subtotal REAL NOT NULL, addon_summary TEXT, discount_percent REAL DEFAULT 0, discount_amount REAL DEFAULT 0, refunded_qty REAL DEFAULT 0',
        (row) async => {'id': await mapped('transaction_details', row['id']), 'transaction_id': await mapped('transactions', row['transaction_id']), 'product_id': await mapped('products', row['product_id']) ?? row['product_id']?.toString() ?? '', 'product_name': row['product_name'], 'sold_price': row['sold_price'], 'quantity': row['quantity'], 'subtotal': row['subtotal'], 'addon_summary': row['addon_summary'] ?? '[]', 'discount_percent': row['discount_percent'] ?? 0, 'discount_amount': row['discount_amount'] ?? 0, 'refunded_qty': row['refunded_qty'] ?? 0});

      // --- held_carts ---
      await _remakeTable(db, 'held_carts',
        'id TEXT PRIMARY KEY, label TEXT NOT NULL, cart_data TEXT NOT NULL, total REAL NOT NULL DEFAULT 0, created_by TEXT, created_by_name TEXT, created_at TEXT',
        (row) async => {'id': await mapped('held_carts', row['id']), 'label': row['label'], 'cart_data': row['cart_data'], 'total': row['total'], 'created_by': await mapped('users', row['created_by']), 'created_by_name': row['created_by_name'], 'created_at': row['created_at']});

      // --- inventory_ledger ---
      await _remakeTable(db, 'inventory_ledger',
        'id TEXT PRIMARY KEY, bahan_baku_id TEXT NOT NULL, timestamp TEXT NOT NULL, transaction_type TEXT NOT NULL, qty_change REAL NOT NULL, financial_value REAL NOT NULL DEFAULT 0, notes TEXT',
        (row) async => {'id': await mapped('inventory_ledger', row['id']), 'bahan_baku_id': await mapped('bahan_baku', row['bahan_baku_id']), 'timestamp': row['timestamp'], 'transaction_type': row['transaction_type'], 'qty_change': row['qty_change'], 'financial_value': row['financial_value'], 'notes': row['notes']});

    } catch (e) {
      debugPrint('[LocalDb] ❌ Migration error: $e');
      rethrow;
    }

    // Step 3: Drop mapping tables
    for (final t in migrationTables) {
      try { await db.execute('DROP TABLE IF EXISTS _map_$t'); } catch (_) {}
    }

    // Re-create index
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_bahan_ts ON inventory_ledger (bahan_baku_id, timestamp)');

    await db.execute('PRAGMA foreign_keys = ON');
    debugPrint('[LocalDb] ✅ UUID migration complete!');
  }

  /// Generic helper: rename old table, create new one, copy rows via transform, drop old.
  static Future<void> _remakeTable(Database db, String name, String newSchema, Future<Map<String, dynamic>> Function(Map<String, dynamic> oldRow) transform) async {
    try {
      final oldRows = await db.query(name);
      await db.execute('DROP TABLE IF EXISTS _old_$name');
      await db.execute('ALTER TABLE $name RENAME TO _old_$name');
      await db.execute('CREATE TABLE $name ($newSchema)');
      for (final row in oldRows) {
        try {
          final mapped = await transform(row);
          // Remove null-valued keys to let defaults work
          mapped.removeWhere((k, v) => v == null);
          if (mapped.containsKey('id') && mapped['id'] != null) {
            await db.insert(name, mapped, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        } catch (e) {
          debugPrint('[LocalDb] Skip row in $name: $e');
        }
      }
      await db.execute('DROP TABLE IF EXISTS _old_$name');
    } catch (e) {
      debugPrint('[LocalDb] Error remaking $name: $e');
    }
  }
}
