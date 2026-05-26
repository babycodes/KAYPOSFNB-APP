import 'package:sqflite_common_ffi/sqflite_ffi.dart';
void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final path = await getDatabasesPath();
  print(path);
}
