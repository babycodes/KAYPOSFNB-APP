import 'package:sqlite3/sqlite3.dart';

void main() {
  final db = sqlite3.open('/home/papayu/Data/AI/Flutter/KAYPOS/KAYPOS_OFFLINE_APP/kaypos_offline.db');
  final result = db.select('PRAGMA table_info(products);');
  for (var row in result) {
    print(row);
  }
}
