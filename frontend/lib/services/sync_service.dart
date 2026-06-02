import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';
import '../core/api.dart';
import 'device_info_service.dart';

/// Manual Batch Sync Service — No background timers, no auto-sync.
/// All sync actions are triggered explicitly by the user.
class SyncService {
  /// Notifier for UI to react to sync state changes without full rebuilds.
  static final ValueNotifier<int> syncNotifier = ValueNotifier(0);

  /// Notifier specifically for pending report count (Kasir side badge).
  static final ValueNotifier<int> pendingReportNotifier = ValueNotifier(0);

  /// Notifier for unread incoming reports from cashiers (Admin side badge).
  static final ValueNotifier<int> newReportNotifier = ValueNotifier(0);

  /// Notifier for pending master data updates available to pull (Kasir side).
  static final ValueNotifier<bool> masterUpdateAvailableNotifier = ValueNotifier(false);

  // ═══════════════════════════════════════════════════════════
  // SHARED UTILITIES & POLLING
  // ═══════════════════════════════════════════════════════════

  static Timer? _pollingTimer;

  /// Starts a lightweight background timer to check for new reports/updates.
  /// This prevents the need to logout/login to see badges.
  static void startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkNewReports();
      checkMasterDataUpdate();
      getPendingReportCount();
    });
  }

  static void stopPolling() {
    _pollingTimer?.cancel();
  }


  static Future<String?> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('server_url');
    if (url == null || url.isEmpty) return null;
    return url;
  }

  static Future<String> _getUuid() => DeviceInfoService.getDeviceUuid();

  // ═══════════════════════════════════════════════════════════
  // REQ 1: KASIR → SERVER (Push Transactions / Laporan)
  // ═══════════════════════════════════════════════════════════

  /// Returns the count of transactions that have NOT been reported yet.
  static Future<int> getPendingReportCount() async {
    final db = await LocalDb.instance;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM transactions WHERE is_synced = 0');
    final resL = await db.rawQuery('SELECT COUNT(*) as c FROM inventory_ledger WHERE is_synced = 0');
    final count = ((res.first['c'] as num?)?.toInt() ?? 0) + ((resL.first['c'] as num?)?.toInt() ?? 0);
    pendingReportNotifier.value = count;
    return count;
  }

  /// Returns all un-reported transactions (with their details) for preview.
  static Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    final db = await LocalDb.instance;
    final rows = await db.query('transactions', where: 'is_synced = 0', orderBy: 'created_at DESC');
    final List<Map<String, dynamic>> result = [];
    for (final row in rows) {
      final tx = Map<String, dynamic>.from(row);
      final details = await db.query('transaction_details', where: 'transaction_id = ?', whereArgs: [tx['id']]);
      tx['items'] = details;
      result.add(tx);
    }
    return result;
  }

  /// KASIR manually pushes un-synced transactions to the server.
  /// Returns a result message for the UI.
  static Future<String> pushTransactions() async {
    final baseUrl = await _getBaseUrl();
    if (baseUrl == null) return 'Server belum tersambung. Sambungkan terlebih dahulu.';

    try {
      final uuid = await _getUuid();
      final unsyncedTxs = await getPendingTransactions();

      final db = await LocalDb.instance;
      final ledgers = await db.query('inventory_ledger', where: 'is_synced = 0');
      final fakeLedgerTxs = ledgers.map((l) => {
        'id': 'ledger_${l['id']}',
        'is_ledger': true,
        'receipt_number': 'INV_${l['transaction_type']}',
        'total_amount': l['financial_value'],
        'payment_method': 'none',
        'status': 'completed',
        'cashier_name': 'System',
        'ledger_data': l,
      }).toList();

      final payloadTxs = [...unsyncedTxs, ...fakeLedgerTxs];

      if (payloadTxs.isEmpty) return 'Tidak ada transaksi atau pembaruan stok baru untuk dilaporkan.';

      final res = await http.post(
        Uri.parse('$baseUrl/api/client/push-transactions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uuid': uuid, 'transactions': payloadTxs}),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final synced = body['synced_count'] ?? 0;

        // Mark all as synced locally — they can NEVER be re-reported
        await db.transaction((txn) async {
          for (final t in unsyncedTxs) {
            await txn.update('transactions', {'is_synced': 1}, where: 'id = ?', whereArgs: [t['id']]);
          }
          for (final l in ledgers) {
            await txn.update('inventory_ledger', {'is_synced': 1}, where: 'id = ?', whereArgs: [l['id']]);
          }
        });

        await getPendingReportCount(); // Refresh badge
        return 'Berhasil! $synced pembaruan berhasil dilaporkan ke server.';
      } else if (res.statusCode == 401) {
        return 'SYNC_REVOKED';
      } else {
        final body = jsonDecode(res.body);
        return 'Gagal: ${body['error'] ?? res.statusCode}';
      }
    } catch (e) {
      return 'Koneksi gagal: $e';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REQ 2: ADMIN ← SERVER (Pull Transaction Reports)
  // ═══════════════════════════════════════════════════════════

  /// Checks server for new transaction reports. Updates [newReportNotifier].
  static Future<void> checkNewReports() async {
    final baseUrl = await _getBaseUrl();
    if (baseUrl == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPull = prefs.getString('last_report_pull') ?? '1970-01-01T00:00:00.000Z';
      final uuid = await _getUuid();

      final res = await http.get(
        Uri.parse('$baseUrl/api/admin/reports/check?since=$lastPull&uuid=$uuid'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        newReportNotifier.value = (body['new_count'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  /// ADMIN manually pulls new transaction reports from the server.
  static Future<String> pullReports() async {
    final baseUrl = await _getBaseUrl();
    if (baseUrl == null) return 'Server belum tersambung.';

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPull = prefs.getString('last_report_pull') ?? '1970-01-01T00:00:00.000Z';
      final uuid = await _getUuid();

      final res = await http.get(
        Uri.parse('$baseUrl/api/admin/reports/pull?since=$lastPull&uuid=$uuid'),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final reports = body['transactions'] as List<dynamic>? ?? [];

        if (reports.isEmpty) {
          return 'Tidak ada laporan baru dari kasir.';
        }

        // Save pulled transactions to local DB
        final db = await LocalDb.instance;
        int saved = 0;
        await db.transaction((txn) async {
          for (final pt in reports) {
            final txId = pt['id']?.toString();
            if (txId == null) continue;
            
            if (pt['is_ledger'] == true) {
              final ledger = pt['ledger_data'];
              if (ledger == null) continue;
              final lId = ledger['id']?.toString();
              if (lId == null) continue;
              
              final exists = await txn.query('inventory_ledger', where: 'id = ?', whereArgs: [lId]);
              if (exists.isEmpty) {
                ledger['is_synced'] = 1;
                await txn.insert('inventory_ledger', Map<String, dynamic>.from(ledger));
                
                final qtyChange = (ledger['qty_change'] as num?)?.toDouble() ?? 0.0;
                final bbId = ledger['bahan_baku_id'];
                if (bbId != null && qtyChange != 0) {
                  await txn.rawUpdate('UPDATE bahan_baku SET stock = stock + ? WHERE id = ?', [qtyChange, bbId]);
                }
                saved++;
              }
            } else {
              final exists = await txn.query('transactions', where: 'id = ?', whereArgs: [txId]);
              if (exists.isEmpty) {
                final header = Map<String, dynamic>.from(pt);
                final items = header.remove('items') as List<dynamic>? ?? [];
                header['is_synced'] = 1;
                try {
                  await txn.insert('transactions', header);
                  for (final item in items) {
                    await txn.insert('transaction_details', Map<String, dynamic>.from(item));
                  }
                  saved++;
                } catch (_) {}
              }
            }
          }
        });

        await prefs.setString('last_report_pull', DateTime.now().toUtc().toIso8601String());
        newReportNotifier.value = 0;
        syncNotifier.value++;
        return 'Berhasil menerima $saved laporan transaksi baru.';
      } else {
        return 'Gagal menarik laporan: ${res.statusCode}';
      }
    } catch (e) {
      return 'Koneksi gagal: $e';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REQ 3: ADMIN → SERVER (Push Master Data Updates)
  // ═══════════════════════════════════════════════════════════

  static const List<String> _masterTables = [
    'categories', 'kategori_bahan', 'users', 'addon_categories', 'discounts',
    'products', 'bahan_baku', 'addons', 'resep', 'paket_items',
    'product_addon_categories',
  ];

  /// ADMIN manually pushes all master data to the server for Kasir to pick up.
  static Future<String> pushMasterData() async {
    final baseUrl = await _getBaseUrl();
    if (baseUrl == null) return 'Server belum tersambung.';

    try {
      final uuid = await _getUuid();
      final db = await LocalDb.instance;
      final prefs = await SharedPreferences.getInstance();
      final lastPush = prefs.getString('last_master_push') ?? '1970-01-01T00:00:00.000Z';
      final lastPushLocal = DateTime.parse(lastPush).toLocal().toIso8601String();

      final Map<String, List<Map<String, dynamic>>> changes = {};
      for (final table in _masterTables) {
        String dateCol = table == 'users' ? 'created_at' : 'updated_at';
        final rows = await db.query(table, where: 'datetime($dateCol) > datetime(?)', whereArgs: [lastPushLocal]);
        if (rows.isNotEmpty) changes[table] = rows;
      }

      if (changes.isEmpty) return 'Tidak ada perubahan master data untuk dikirim.';

      final res = await http.post(
        Uri.parse('$baseUrl/api/client/push-master'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'uuid': uuid, 'changes': changes}),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final count = body['saved_count'] ?? 0;
        await prefs.setString('last_master_push', DateTime.now().toUtc().toIso8601String());
        return 'Berhasil mengirim $count perubahan data master ke server.';
      } else if (res.statusCode == 401) {
        return 'SYNC_REVOKED';
      } else {
        final body = jsonDecode(res.body);
        return 'Gagal: ${body['error'] ?? res.statusCode}';
      }
    } catch (e) {
      return 'Koneksi gagal: $e';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // REQ 3b: KASIR ← SERVER (Pull Master Data Updates)
  // ═══════════════════════════════════════════════════════════

  /// Check if new master data is available from server. Updates [masterUpdateAvailableNotifier].
  static Future<void> checkMasterDataUpdate() async {
    final baseUrl = await _getBaseUrl();
    if (baseUrl == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPull = prefs.getString('last_master_pull') ?? '1970-01-01T00:00:00.000Z';

      final res = await http.get(
        Uri.parse('$baseUrl/api/client/master/check?since=$lastPull'),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        masterUpdateAvailableNotifier.value = (body['has_update'] as bool?) ?? false;
      }
    } catch (_) {}
  }

  /// KASIR manually pulls the latest master data from the server.
  /// Inserts in strict hierarchical order to prevent FK violations.
  static Future<String> pullMasterData() async {
    final baseUrl = await _getBaseUrl();
    if (baseUrl == null) return 'Server belum tersambung.';

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPull = prefs.getString('last_master_pull') ?? '1970-01-01T00:00:00.000Z';
      final db = await LocalDb.instance;

      // Self-healing: if products table is empty, force full sync
      final productCountRes = await db.rawQuery('SELECT COUNT(*) as c FROM products');
      final productCount = (productCountRes.first['c'] as num?)?.toInt() ?? 0;
      final since = productCount == 0 ? '1970-01-01T00:00:00.000Z' : lastPull;

      final res = await http.get(
        Uri.parse('$baseUrl/api/client/master/pull?since=$since'),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final pullChanges = body['changes'] as List<dynamic>? ?? [];

        if (pullChanges.isEmpty) {
          masterUpdateAvailableNotifier.value = false;
          return 'Data master sudah terbaru.';
        }

        // Group by table name
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final change in pullChanges) {
          final table = change['table_name'] as String;
          if (_masterTables.contains(table)) {
            grouped.putIfAbsent(table, () => []);
            grouped[table]!.add(jsonDecode(change['payload']));
          }
        }

        // Strict hierarchical insert order to satisfy FK constraints
        const strictOrder = [
          'kategori_bahan', 'categories', 'users', 'addon_categories', 'discounts',
          'bahan_baku', 'products',
          'addons',
          'resep', 'paket_items', 'product_addon_categories',
        ];

        int saved = 0;
        await db.transaction((txn) async {
          for (final table in strictOrder) {
            if (grouped.containsKey(table)) {
              for (final rowData in grouped[table]!) {
                try {
                  await txn.insert(table, rowData, conflictAlgorithm: ConflictAlgorithm.replace);
                  saved++;
                } catch (_) {}
              }
            }
          }
        });

        await prefs.setString('last_master_pull', DateTime.now().toUtc().toIso8601String());
        masterUpdateAvailableNotifier.value = false;
        syncNotifier.value++;
        return 'Berhasil memperbarui $saved item data master.';
      } else if (res.statusCode == 401) {
        return 'SYNC_REVOKED';
      } else {
        return 'Gagal: ${res.statusCode}';
      }
    } catch (e) {
      return 'Koneksi gagal: $e';
    }
  }
}
