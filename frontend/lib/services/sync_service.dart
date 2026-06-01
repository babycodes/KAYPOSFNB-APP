import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../core/local_db.dart';
import 'device_info_service.dart';

class SyncService {
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

      // 1. Gather Master Data Changes
      final Map<String, List<Map<String, dynamic>>> changes = {};
      final masterTables = ['categories', 'kategori_bahan', 'users', 'addon_categories', 'discounts', 'products', 'bahan_baku', 'addons'];
      for (var table in masterTables) {
        final rows = await db.query(table, where: 'updated_at > ?', whereArgs: [lastSyncStr]);
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

        // Mark as synced locally
        final batch = db.batch();
        for (final t in unsynced) {
          batch.update(
            'transactions', 
            {'is_synced': 1}, 
            where: 'id = ?', 
            whereArgs: [t['id']]
          );
        }
        await batch.commit(noResult: true);

        // Process pulled transactions from server
        final pulled = body['pull_transactions'] as List<dynamic>? ?? [];
        if (pulled.isNotEmpty) {
          final pullBatch = db.batch();
          for (var pt in pulled) {
            final txId = pt['id'];
            // Check if exists
            final exists = await db.query('transactions', where: 'id = ?', whereArgs: [txId]);
            if (exists.isEmpty) {
              final Map<String, dynamic> header = Map.from(pt);
              final items = header.remove('items') as List<dynamic>? ?? [];
              header['is_synced'] = 1; // already synced from server
              pullBatch.insert('transactions', header);
              for (var item in items) {
                pullBatch.insert('transaction_details', Map<String, dynamic>.from(item));
              }
            }
          }
          await pullBatch.commit(noResult: true);
        }

        // Process pulled Master Data changes from server
        final pullChanges = body['pull_changes'] as List<dynamic>? ?? [];
        if (pullChanges.isNotEmpty) {
          final masterBatch = db.batch();
          for (var change in pullChanges) {
            final table = change['table_name'];
            final Map<String, dynamic> rowData = jsonDecode(change['payload']);
            if (masterTables.contains(table)) {
               // INSERT OR REPLACE
               masterBatch.insert(table, rowData, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
          await masterBatch.commit(noResult: true);
        }

        await prefs.setString('last_sync_time', DateTime.now().toUtc().toIso8601String());

        return 'Sukses! $syncedCount tx dikirim, ${pulled.length} tx ditarik. ${pullChanges.length} pembaruan master.';
      } else if (res.statusCode == 401) {
        // Device is revoked or PIN changed
        await prefs.remove('server_url');
        return 'SYNC_REVOKED';
      } else {
        final body = jsonDecode(res.body);
        return 'Gagal sinkronisasi: ${body['error'] ?? res.statusCode}';
      }
    } catch (e) {
      return 'Koneksi ke server gagal. Server mungkin mati.';
    }
  }
}
