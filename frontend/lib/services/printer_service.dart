import 'dart:async';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  PrinterManager? _printerManagerObj;
  PrinterManager get _printerManager {
    if (kIsWeb) throw Exception('Koneksi printer langsung tidak didukung di Web');
    _printerManagerObj ??= PrinterManager.instance;
    return _printerManagerObj!;
  }
  PrinterDevice? _selectedPrinter;
  bool _isConnected = false;

  PrinterDevice? get selectedPrinter => _selectedPrinter;
  bool get isConnected => _isConnected;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString('printer_mac');
    final savedName = prefs.getString('printer_name');
    final savedTypeStr = prefs.getString('printer_type'); // bluetooth or usb
    final savedVendorId = prefs.getString('printer_vendorId');
    final savedProductId = prefs.getString('printer_productId');

    if (savedMac != null && savedTypeStr != null) {
      final type = savedTypeStr == 'usb' ? PrinterType.usb : PrinterType.bluetooth;
      _selectedPrinter = PrinterDevice(
        name: savedName ?? 'Unknown', 
        address: savedMac, 
      );
      // Hack to set type, vendorId, productId since they are not in constructor properly in some versions
      _selectedPrinter!.vendorId = savedVendorId;
      _selectedPrinter!.productId = savedProductId;
      
      try {
        if (!kIsWeb) await connect(_selectedPrinter!, type);
      } catch (e) {
        debugPrint('Auto connect printer failed: $e');
      }
    }
  }

  Stream<PrinterDevice> scan(PrinterType type) async* {
    if (kIsWeb) return;
    if (!kIsWeb && Platform.isLinux && type == PrinterType.usb) {
      final file = File('/dev/usb/lp0');
      if (file.existsSync()) {
        yield PrinterDevice(name: 'Linux USB Printer (lp0)', address: '/dev/usb/lp0', vendorId: 'linux_lp0', productId: 'linux_lp0');
      }
      return;
    }
    yield* _printerManager.discovery(type: type);
  }

  Future<void> connect(PrinterDevice device, PrinterType type) async {
    if (kIsWeb) throw Exception('Koneksi printer langsung tidak didukung di Web');
    _selectedPrinter = device;
    if (!kIsWeb && Platform.isLinux && type == PrinterType.usb) {
      // Bypasses manager and just sets connected flag
      _isConnected = true;
    } else if (type == PrinterType.bluetooth) {
      await _printerManager.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          name: device.name,
          address: device.address!,
          isBle: false,
          autoConnect: false,
        ),
      );
    } else if (type == PrinterType.usb) {
      await _printerManager.connect(
        type: PrinterType.usb,
        model: UsbPrinterInput(
          name: device.name,
          productId: device.productId,
          vendorId: device.vendorId,
        ),
      );
    }
    
    // Strict Hardware Handshake: Send ESC @ (Init Printer)
    if (!kIsWeb && !(Platform.isLinux && type == PrinterType.usb)) {
      try {
        final dynamic result = await _printerManager.send(type: type, bytes: [27, 64]);
        if (result == false) throw Exception('Port menolak koneksi');
      } catch (e) {
        // Force disconnect if handshake fails
        await _printerManager.disconnect(type: type);
        throw Exception('Printer mati, sibuk, atau port tertutup: $e');
      }
    }

    _isConnected = true;
    
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('printer_mac', device.address ?? '');
    prefs.setString('printer_name', device.name ?? 'Unknown');
    prefs.setString('printer_type', type == PrinterType.usb ? 'usb' : 'bluetooth');
    if (device.vendorId != null) prefs.setString('printer_vendorId', device.vendorId!);
    if (device.productId != null) prefs.setString('printer_productId', device.productId!);
  }

  Future<void> disconnect(PrinterType type) async {
    if (kIsWeb) return;
    if (_selectedPrinter != null) {
      await _printerManager.disconnect(type: type);
      _isConnected = false;
    }
  }

  Future<void> printReceipt(List<int> bytes) async {
    if (kIsWeb) throw Exception("Fitur cetak otomatis tidak didukung di Web. Gunakan Cetak Web bawaan.");
    if (_selectedPrinter == null) throw Exception("Tidak ada printer yang terhubung");
    
    final prefs = await SharedPreferences.getInstance();
    final savedTypeStr = prefs.getString('printer_type') ?? 'bluetooth';
    final type = savedTypeStr == 'usb' ? PrinterType.usb : PrinterType.bluetooth;
    
    if (!_isConnected) await connect(_selectedPrinter!, type);
    
    if (!kIsWeb && Platform.isLinux && type == PrinterType.usb) {
      try {
        final file = File('/dev/usb/lp0');
        await file.writeAsBytes(bytes, mode: FileMode.append);
      } catch (e) {
        throw Exception("Gagal print ke /dev/usb/lp0. Pastikan user masuk group 'lp': $e");
      }
      return;
    }
    
    await _printerManager.send(type: type, bytes: bytes);
  }
}
