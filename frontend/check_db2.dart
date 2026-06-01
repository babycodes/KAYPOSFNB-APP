import 'package:sqflite_common_ffi/sqflite_ffi.dart';
void main() async {
  sqfliteFfiInit();
  var factory = databaseFactoryFfi;
  var db = await factory.openDatabase('/home/papayu/.dart_tool/sqflite_common_ffi/databases/kayposfnb.db');
  try {
    await db.execute('ALTER TABLE resep ADD COLUMN updated_at TEXT DEFAULT (datetime(\'now\',\'localtime\'))');
    print('SUCCESS');
  } catch (e) {
    print('ERROR: $e');
  }
}
