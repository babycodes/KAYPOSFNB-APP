import 'package:sqflite_common_ffi/sqflite_ffi.dart';
void main() async {
  sqfliteFfiInit();
  var factory = databaseFactoryFfi;
  var db = await factory.openDatabase(inMemoryDatabasePath);
  await db.execute('CREATE TABLE resep(id TEXT)');
  try {
    await db.execute('ALTER TABLE resep ADD COLUMN updated_at TEXT DEFAULT (datetime(\'now\',\'localtime\'))');
    print('SUCCESS');
  } catch (e) {
    print('ERROR: $e');
  }
}
