import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  var db = await databaseFactory.openDatabase('/home/papayu/Data/AI/Flutter/KAYPOS/KAYPOS_OFFLINE_APP/kaypos_offline.db');
  var result = await db.rawQuery('PRAGMA table_info(products);');
  for (var row in result) {
    print(row);
  }
}
