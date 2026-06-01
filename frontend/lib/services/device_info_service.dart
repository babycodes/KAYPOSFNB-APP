import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceInfoService {
  static const _storage = FlutterSecureStorage();
  static const _uuidKey = 'device_uuid';
  static const _uuid = Uuid();

  /// Retrieve the existing Device UUID from secure storage, 
  /// or generate and save a new one if it doesn't exist.
  static Future<String> getDeviceUuid() async {
    final existingUuid = await _storage.read(key: _uuidKey);
    
    if (existingUuid != null && existingUuid.isNotEmpty) {
      return existingUuid;
    }

    final newUuid = _uuid.v4();
    await _storage.write(key: _uuidKey, value: newUuid);
    
    return newUuid;
  }
}
