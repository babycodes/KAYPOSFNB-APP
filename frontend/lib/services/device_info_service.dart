import 'dart:io' show Platform;
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

  /// Returns a human-readable platform name for the current device.
  /// e.g. "Android", "Linux", "Windows", "iOS", "macOS"
  static String getDevicePlatform() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }

  /// Returns a default device name combining platform + type.
  /// e.g. "KayPOS Android", "KayPOS Linux"
  static String getDefaultDeviceName() {
    return 'KayPOS ${getDevicePlatform()}';
  }
}
