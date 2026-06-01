import 'package:sqflite_common_ffi/sqflite_ffi.dart';
void main() async {
  sqfliteFfiInit();
  var factory = databaseFactoryFfi;
  var db = await factory.openDatabase('/home/papayu/.dart_tool/sqflite_common_ffi/databases/kayposfnb.db');
  var res = await db.rawQuery("PRAGMA table_info(resep)");
  print(res);
}
