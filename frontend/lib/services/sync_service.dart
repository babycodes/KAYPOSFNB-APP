import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';
import 'device_info_service.dart';

class SyncService {
  static final ValueNotifier<int> syncNotifier = ValueNotifier(0);
  /// Sync transactions to server. 
  /// Returns a message string for the UI.
  static Future<String> syncTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('server_url');
      if (baseUrl == null || baseUrl.isEmpty) {
        return 'Server URL tidak ditemukan. Silakan sambungkan perangkat terlebih dahulu.';
      }

      final uuid = await DeviceInfoService.getDeviceUuid();

      final db = await LocalDb.instance;
      
      final unsyncedRows = await db.query('transactions', where: 'is_synced = 0');
      
      List<Map<String, dynamic>> unsynced = [];
      for (var row in unsyncedRows) {
        final Map<String, dynamic> tx = Map.from(row);
        final details = await db.query('transaction_details', where: 'transaction_id = ?', whereArgs: [tx['id']]);
        tx['items'] = details;
        unsynced.add(tx);
      }

      final lastSyncStr = prefs.getString('last_sync_time') ?? '2000-01-01T00:00:00.000Z';

      // One-time bump for junction tables that didn't have updated_at before v1.0.94
      final hasForced = prefs.getBool('has_forced_sync_junctions') ?? false;
      if (!hasForced) {
        final now = DateTime.now().toIso8601String();
        await db.rawUpdate("UPDATE resep SET updated_at = ?", [now]);
        await db.rawUpdate("UPDATE paket_items SET updated_at = ?", [now]);
        await db.rawUpdate("UPDATE product_addon_categories SET updated_at = ?", [now]);
        await prefs.setBool('has_forced_sync_junctions', true);
      }

      // 1. Gather Master Data Changes
      final Map<String, List<Map<String, dynamic>>> changes = {};
      final masterTables = [
        'categories', 'kategori_bahan', 'users', 'addon_categories', 'discounts', 
        'products', 'bahan_baku', 'addons', 'resep', 'paket_items', 
        'product_addon_categories', 'inventory_ledger', 'restock_history'
      ];
      for (var table in masterTables) {
        String dateCol = 'updated_at';
        if (table == 'users') dateCol = 'created_at';
        if (table == 'inventory_ledger' || table == 'restock_history') dateCol = 'timestamp';
        
        final lastSyncLocalStr = DateTime.parse(lastSyncStr).toLocal().toIso8601String();
        final rows = await db.query(table, where: 'datetime($dateCol) > datetime(?)', whereArgs: [lastSyncLocalStr]);
        if (rows.isNotEmpty) changes[table] = rows;
      }

      final payload = {
        'uuid': uuid,
        'last_sync_time': lastSyncStr,
        'transactions': unsynced,
        'changes': changes,
      };

      final url = '$baseUrl/api/client/sync';
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final syncedCount = body['synced_count'] ?? 0;

        // PULL PROCESSING
        int masterSuccess = 0;
        final pulled = body['pull_transactions'] as List<dynamic>? ?? [];
        final pullChanges = body['pull_changes'] as List<dynamic>? ?? [];

        await db.transaction((txn) async {
          // 1. Mark as synced locally
          for (final t in unsynced) {
            await txn.update(
              'transactions', 
              {'is_synced': 1}, 
              where: 'id = ?', 
              whereArgs: [t['id']]
            );
          }

          // 2. Process Master Data changes strictly in hierarchical order
          if (pullChanges.isNotEmpty) {
            // Group by table
            final Map<String, List<Map<String, dynamic>>> groupedChanges = {};
            for (var change in pullChanges) {
              final table = change['table_name'] as String;
              if (masterTables.contains(table)) {
                groupedChanges.putIfAbsent(table, () => []);
                groupedChanges[table]!.add(jsonDecode(change['payload']));
              }
            }

            // Define strict hierarchical order to satisfy Foreign Key constraints
            final strictOrder = [
              // Level 1
              'kategori_bahan', 'categories', 'users', 'addon_categories', 'discounts',
              // Level 2
              'bahan_baku', 'products',
              // Level 3
              'addons',
              // Level 4
              'resep', 'paket_items', 'product_addon_categories',
              // Level 5
              'inventory_ledger', 'restock_history'
            ];

            for (final table in strictOrder) {
              if (groupedChanges.containsKey(table)) {
                for (final rowData in groupedChanges[table]!) {
                  try {
                    await txn.insert(table, rowData, conflictAlgorithm: ConflictAlgorithm.replace);
                    masterSuccess++;
                  } catch (e) {
                    // Ignore UNIQUE constraint violations (e.g. same category name)
                  }
                }
              }
            }
          }

          // 3. Process pulled transactions from server (Level 6 & 7)
          if (pulled.isNotEmpty) {
            for (var pt in pulled) {
              final txId = pt['id'];
              final exists = await txn.query('transactions', where: 'id = ?', whereArgs: [txId]);
              if (exists.isEmpty) {
                final Map<String, dynamic> header = Map.from(pt);
                final items = header.remove('items') as List<dynamic>? ?? [];
                header['is_synced'] = 1; // already synced from server
                
                try {
                  await txn.insert('transactions', header);
                  for (var item in items) {
                    await txn.insert('transaction_details', Map<String, dynamic>.from(item));
                  }
                } catch (e) {
                  // Ignore malformed transactions from server
                }
              }
            }
          }
        });

        await prefs.setString('last_sync_time', DateTime.now().toUtc().toIso8601String());
        syncNotifier.value++;

        return 'Sukses! $syncedCount tx dikirim, ${pulled.length} tx ditarik. $masterSuccess pembaruan master.';
      } else if (res.statusCode == 401) {
        // Device is revoked or PIN changed
        await prefs.remove('server_url');
        return 'SYNC_REVOKED';
      } else {
        final body = jsonDecode(res.body);
        return 'Gagal sinkronisasi: ${body['error'] ?? res.statusCode}';
      }
    } catch (e, stack) {
      return 'Koneksi gagal/Error: $e';
    }
  }
}
