import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
      
      // Fetch unsynced transactions
      final unsynced = await db.query('transactions', where: 'is_synced = 0');
      if (unsynced.isEmpty) {
        return 'Semua data sudah tersinkronisasi.';
      }

      final payload = {
        'uuid': uuid,
        'transactions': unsynced,
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

        return 'Sukses! $syncedCount transaksi disinkronisasi ke server.';
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
