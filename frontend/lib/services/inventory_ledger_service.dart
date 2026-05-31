/// ─────────────────────────────────────────────────────────────
/// Inventory Ledger Service
/// ─────────────────────────────────────────────────────────────
/// A purely ADDITIVE historical tracking layer for bahan_baku.
/// This does NOT alter the existing `bahan_baku` table or the
/// Cashier BOM deduction math in any way.
///
/// Three responsibilities:
///   1. ensureTable()         – CREATE TABLE IF NOT EXISTS
///   2. seedInventoryLedger() – Inject realistic dummy data
///   3. verifyLedgerMath()    – Audit SQL math via debugPrint
/// ─────────────────────────────────────────────────────────────
library;

import 'package:flutter/foundation.dart';
import '../core/local_db.dart';

class InventoryLedgerService {
  // ──────────────────────────────────────────────────
  // 1. TABLE CREATION
  //    Called once during DB initialization (onOpen).
  //    Safe to call multiple times — uses IF NOT EXISTS.
  // ──────────────────────────────────────────────────
  static Future<void> ensureTable() async {
    final db = await LocalDb.instance;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_ledger (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        bahan_baku_id     INTEGER NOT NULL REFERENCES bahan_baku(id) ON DELETE CASCADE,
        timestamp         TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
        transaction_type  TEXT    NOT NULL CHECK(transaction_type IN ('RESTOCK','SALE','WASTE','ADJUSTMENT')),
        qty_change        REAL    NOT NULL,
        financial_value   REAL    NOT NULL DEFAULT 0,
        notes             TEXT    DEFAULT ''
      )
    ''');

    // Index for fast filtered queries per material and date range
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ledger_bahan_ts
      ON inventory_ledger (bahan_baku_id, timestamp)
    ''');

    debugPrint('[InventoryLedger] ✅ Table ensured');
  }

  // ──────────────────────────────────────────────────
  // 2. SEEDER — Dummy data for ONE material (Ayam)
  //    Assumes a bahan_baku named "Ayam" with master unit Kg exists.
  //    If it doesn't exist, creates one for testing purposes.
  //
  //    Scenario modelled:
  //      Day 1: Initial Restock → +5 Kg   (Rp 175.000)
  //      Day 2: Sale deduction  → −0.3 Kg (Auto-deduct by Cashier)
  //      Day 3: Sale deduction  → −0.5 Kg (Auto-deduct by Cashier)
  //      Day 4: Waste           → −0.2 Kg (Jatuh dari meja)
  //      Day 5: Second Restock  → +3 Kg   (Rp 108.000)
  //
  //    Expected final qty_change SUM = +5 -0.3 -0.5 -0.2 +3 = +7.0 Kg
  // ──────────────────────────────────────────────────
  static Future<void> seedInventoryLedger() async {
    final db = await LocalDb.instance;

    // Find or create a test material "Ayam"
    int bahanBakuId;
    final existing = await db.rawQuery(
      "SELECT id FROM bahan_baku WHERE name = 'Ayam' LIMIT 1",
    );
    if (existing.isNotEmpty) {
      bahanBakuId = (existing.first['id'] as num).toInt();
    } else {
      bahanBakuId = await db.insert('bahan_baku', {
        'name': 'Ayam',
        'unit': 'Kg',
        'stock': 7.0, // matches our expected final stock
        'cost_price': 35000,
        'min_stock_alert': 1.0,
        'kategori': 'Daging/Protein',
        'kategori_bahan_id': 0,
      });
      debugPrint('[Seeder] Created test material "Ayam" with id=$bahanBakuId');
    }

    // Clear any previous seeded ledger rows for this material
    await db.delete(
      'inventory_ledger',
      where: 'bahan_baku_id = ?',
      whereArgs: [bahanBakuId],
    );

    // Insert 5 hardcoded ledger entries using ISO8601 timestamps
    final entries = <Map<String, dynamic>>[
      {
        'bahan_baku_id': bahanBakuId,
        'timestamp': '2026-06-01 08:00:00',
        'transaction_type': 'RESTOCK',
        'qty_change': 5.0, // +5 Kg
        'financial_value': 175000, // Rp 175.000 (Rp 35.000/Kg × 5 Kg)
        'notes': 'Pembelian awal dari Supplier A',
      },
      {
        'bahan_baku_id': bahanBakuId,
        'timestamp': '2026-06-02 12:15:00',
        'transaction_type': 'SALE',
        'qty_change': -0.3, // −0.3 Kg
        'financial_value': 0, // Revenue tracked elsewhere
        'notes': 'Auto-deduct by Cashier — Ayam Goreng ×2',
      },
      {
        'bahan_baku_id': bahanBakuId,
        'timestamp': '2026-06-03 13:30:00',
        'transaction_type': 'SALE',
        'qty_change': -0.5, // −0.5 Kg
        'financial_value': 0,
        'notes': 'Auto-deduct by Cashier — Nasi Ayam Special ×1',
      },
      {
        'bahan_baku_id': bahanBakuId,
        'timestamp': '2026-06-04 09:00:00',
        'transaction_type': 'WASTE',
        'qty_change': -0.2, // −0.2 Kg
        'financial_value': 7000, // Loss: 0.2 Kg × Rp 35.000/Kg
        'notes': 'Jatuh dari meja',
      },
      {
        'bahan_baku_id': bahanBakuId,
        'timestamp': '2026-06-05 07:45:00',
        'transaction_type': 'RESTOCK',
        'qty_change': 3.0, // +3 Kg
        'financial_value': 108000, // Rp 108.000 (Rp 36.000/Kg × 3 Kg)
        'notes': 'Restock ke-2 dari Supplier B (harga naik)',
      },
    ];

    final batch = db.batch();
    for (final e in entries) {
      batch.insert('inventory_ledger', e);
    }
    await batch.commit(noResult: true);

    debugPrint('[Seeder] ✅ Injected ${entries.length} ledger entries for '
        'bahan_baku_id=$bahanBakuId (Ayam)');
    debugPrint('[Seeder] Date range: 2026-06-01 → 2026-06-05');
    debugPrint('[Seeder] Expected SUM(qty_change) = 7.0 Kg');
  }

  // ──────────────────────────────────────────────────
  // 3. MATH VERIFICATION (Audit)
  //    Queries the inventory_ledger for a specific material
  //    within a date range and prints a detailed report.
  //
  //    Metrics calculated:
  //      • Total In    (RESTOCK + positive ADJUSTMENT)
  //      • Total Sales (SALE deductions)
  //      • Total Waste (WASTE deductions)
  //      • Theoretical Final Stock = SUM(qty_change)
  //      • Total Financial Value per type
  // ──────────────────────────────────────────────────
  static Future<void> verifyLedgerMath(
    int bahanBakuId,
    String startDate,
    String endDate,
  ) async {
    final db = await LocalDb.instance;

    // Fetch material info
    final matRows = await db.query(
      'bahan_baku',
      where: 'id = ?',
      whereArgs: [bahanBakuId],
    );
    if (matRows.isEmpty) {
      debugPrint('[LedgerAudit] ❌ bahan_baku_id=$bahanBakuId not found');
      return;
    }
    final matName = matRows.first['name']?.toString() ?? '?';
    final matUnit = matRows.first['unit']?.toString() ?? '?';
    final currentDbStock = (matRows.first['stock'] as num?)?.toDouble() ?? 0;

    // Query aggregated ledger data within date range
    final aggregated = await db.rawQuery('''
      SELECT
        transaction_type,
        COUNT(*)               AS entry_count,
        SUM(qty_change)        AS total_qty,
        SUM(financial_value)   AS total_value
      FROM inventory_ledger
      WHERE bahan_baku_id = ?
        AND timestamp >= ?
        AND timestamp <= ?
      GROUP BY transaction_type
      ORDER BY transaction_type
    ''', [bahanBakuId, '$startDate 00:00:00', '$endDate 23:59:59']);

    // Calculate theoretical stock from SUM(qty_change)
    final sumResult = await db.rawQuery('''
      SELECT COALESCE(SUM(qty_change), 0) AS theoretical_stock
      FROM inventory_ledger
      WHERE bahan_baku_id = ?
        AND timestamp >= ?
        AND timestamp <= ?
    ''', [bahanBakuId, '$startDate 00:00:00', '$endDate 23:59:59']);

    final theoreticalStock =
        (sumResult.first['theoretical_stock'] as num?)?.toDouble() ?? 0;

    // Fetch all individual rows for the detail section
    final detailRows = await db.rawQuery('''
      SELECT id, timestamp, transaction_type, qty_change, financial_value, notes
      FROM inventory_ledger
      WHERE bahan_baku_id = ?
        AND timestamp >= ?
        AND timestamp <= ?
      ORDER BY timestamp ASC
    ''', [bahanBakuId, '$startDate 00:00:00', '$endDate 23:59:59']);

    // ── Build the report ──
    final buf = StringBuffer();
    buf.writeln('');
    buf.writeln('╔══════════════════════════════════════════════════════════╗');
    buf.writeln('║          📋 INVENTORY LEDGER AUDIT REPORT               ║');
    buf.writeln('╠══════════════════════════════════════════════════════════╣');
    buf.writeln('║  Material     : $matName');
    buf.writeln('║  Master Unit  : $matUnit');
    buf.writeln('║  Period       : $startDate → $endDate');
    buf.writeln('║  DB Stock Now : ${_fmt(currentDbStock)} $matUnit');
    buf.writeln('╠══════════════════════════════════════════════════════════╣');
    buf.writeln('║                   SUMMARY BY TYPE                       ║');
    buf.writeln('╠══════════════════════════════════════════════════════════╣');

    double totalIn = 0;
    double totalSaleOut = 0;
    double totalWasteOut = 0;
    double totalAdjustment = 0;
    double totalFinancial = 0;

    for (final row in aggregated) {
      final type = row['transaction_type']?.toString() ?? '?';
      final count = (row['entry_count'] as num?)?.toInt() ?? 0;
      final qty = (row['total_qty'] as num?)?.toDouble() ?? 0;
      final value = (row['total_value'] as num?)?.toDouble() ?? 0;

      final sign = qty >= 0 ? '+' : '';
      buf.writeln(
          '║  ${type.padRight(10)}│ ${count}x │ $sign${_fmt(qty)} $matUnit │ Rp ${_fmtMoney(value)}');

      if (type == 'RESTOCK') totalIn += qty;
      if (type == 'SALE') totalSaleOut += qty.abs();
      if (type == 'WASTE') totalWasteOut += qty.abs();
      if (type == 'ADJUSTMENT') totalAdjustment += qty;
      totalFinancial += value;
    }

    buf.writeln('╠══════════════════════════════════════════════════════════╣');
    buf.writeln('║                    CALCULATED TOTALS                     ║');
    buf.writeln('╠══════════════════════════════════════════════════════════╣');
    buf.writeln('║  📦 Total In (Restock)     : +${_fmt(totalIn)} $matUnit');
    buf.writeln('║  🛒 Total Out (Sales)      : -${_fmt(totalSaleOut)} $matUnit');
    buf.writeln('║  🗑️ Total Waste            : -${_fmt(totalWasteOut)} $matUnit');
    if (totalAdjustment != 0) {
      buf.writeln('║  🔧 Total Adjustment       : ${totalAdjustment >= 0 ? '+' : ''}${_fmt(totalAdjustment)} $matUnit');
    }
    buf.writeln('║  ────────────────────────────────────────────────────');
    buf.writeln('║  📊 Theoretical Final Stock : ${_fmt(theoreticalStock)} $matUnit');
    buf.writeln('║  💰 Total Financial Value   : Rp ${_fmtMoney(totalFinancial)}');
    buf.writeln('╠══════════════════════════════════════════════════════════╣');

    // Cross-check: compare theoretical vs actual DB stock
    final delta = (currentDbStock - theoreticalStock).abs();
    if (delta < 0.001) {
      buf.writeln('║  ✅ MATCH: Theoretical stock matches current DB stock');
    } else {
      buf.writeln('║  ⚠️  MISMATCH: DB stock (${_fmt(currentDbStock)}) ≠ Ledger (${_fmt(theoreticalStock)})');
      buf.writeln('║     Delta = ${_fmt(delta)} $matUnit');
      buf.writeln('║     (This is expected if the ledger does not cover the');
      buf.writeln('║      full history from stock=0 to present)');
    }

    buf.writeln('╠══════════════════════════════════════════════════════════╣');
    buf.writeln('║                   DETAIL ENTRIES                         ║');
    buf.writeln('╠══════════════════════════════════════════════════════════╣');

    for (final d in detailRows) {
      final ts = d['timestamp']?.toString() ?? '';
      final type = d['transaction_type']?.toString() ?? '';
      final qty = (d['qty_change'] as num?)?.toDouble() ?? 0;
      final sign = qty >= 0 ? '+' : '';
      final notes = d['notes']?.toString() ?? '';
      buf.writeln(
          '║  $ts │ ${type.padRight(10)} │ $sign${_fmt(qty).padLeft(8)} $matUnit │ $notes');
    }

    buf.writeln('╚══════════════════════════════════════════════════════════╝');
    buf.writeln('');

    debugPrint(buf.toString());
  }

  // ── Formatting helpers ──

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  static String _fmtMoney(double v) {
    if (v == 0) return '0';
    final str = v.round().toString();
    // Add thousand separators
    final buf = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buf.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0 && str[i] != '-') buf.write('.');
    }
    return buf.toString().split('').reversed.join();
  }

  // ──────────────────────────────────────────────────
  // CONVENIENCE: Run full demo (Seed + Verify)
  // Call this from a debug button or main.dart to test.
  // ──────────────────────────────────────────────────
  static Future<void> runFullDemo() async {
    debugPrint('\n🚀 Starting Inventory Ledger Demo...\n');

    // Step 1: Ensure table exists
    await ensureTable();

    // Step 2: Seed dummy data
    await seedInventoryLedger();

    // Step 3: Find the Ayam material ID for verification
    final db = await LocalDb.instance;
    final rows = await db.rawQuery(
      "SELECT id FROM bahan_baku WHERE name = 'Ayam' LIMIT 1",
    );
    if (rows.isEmpty) {
      debugPrint('[Demo] ❌ Could not find "Ayam" material after seeding');
      return;
    }
    final ayamId = (rows.first['id'] as num).toInt();

    // Step 4: Run the audit
    await verifyLedgerMath(ayamId, '2026-06-01', '2026-06-05');

    debugPrint('🏁 Inventory Ledger Demo Complete.\n');
  }
}
