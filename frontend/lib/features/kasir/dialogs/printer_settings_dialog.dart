import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../../services/printer_service.dart';
import '../../../core/api.dart';
import '../../../core/helpers.dart';
import '../../../services/receipt_generator.dart';

class PrinterSettingsDialog extends StatefulWidget {
  const PrinterSettingsDialog({super.key});

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  PrinterType defaultPrinterType = PrinterType.bluetooth;
  final PrinterService _printerService = PrinterService();
  
  List<PrinterDevice> devices = [];
  bool isScanning = false;
  StreamSubscription<PrinterDevice>? _subscription;
  String? connectingDeviceAddress;
  String? failedDeviceAddress;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    setState(() {
      devices.clear();
      isScanning = true;
    });

    _subscription?.cancel();
    _subscription = _printerService.scan(defaultPrinterType).listen((device) {
      bool exists = devices.any((d) {
        if (defaultPrinterType == PrinterType.bluetooth) {
          return d.address == device.address && d.address != null && d.address!.isNotEmpty;
        } else {
          return d.name == device.name;
        }
      });
      if (!exists && device.name.isNotEmpty) {
        setState(() {
          devices.add(device);
        });
      }
    }, onDone: () {
      if (mounted) setState(() => isScanning = false);
    }, onError: (e) {
      if (mounted) setState(() => isScanning = false);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _connect(PrinterDevice device) async {
    final address = defaultPrinterType == PrinterType.bluetooth ? device.address : device.name;
    if (connectingDeviceAddress != null) return;
    
    setState(() {
      connectingDeviceAddress = address;
      failedDeviceAddress = null;
    });

    try {
      await _printerService.connect(device, defaultPrinterType);
      if (mounted) {
        showToast(context, '✅ Printer ${device.name} terhubung');
        setState(() {
          connectingDeviceAddress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '❌ Gagal: $e');
        setState(() {
          connectingDeviceAddress = null;
          failedDeviceAddress = address;
        });
      }
    }
  }

  Future<void> _testPrint() async {
    try {
      if (!_printerService.isConnected) {
        showToast(context, '⚠️ Printer belum terhubung');
        return;
      }
      
      final settingsRes = await Api.get('/settings');
      Map<String, dynamic> settings = {};
      if (settingsRes != null && settingsRes is Map<String, dynamic>) {
        settings = settingsRes;
      }

      final bytes = await ReceiptGenerator.generateTestPrint(settings: settings);
      await _printerService.printReceipt(bytes);
      
      if (mounted) showToast(context, '✅ Test print berhasil');
    } catch (e) {
      if (mounted) showToast(context, '❌ Gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = _printerService.selectedPrinter;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('🖨️ Pengaturan Printer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          
          // Type Selector
          Row(
            children: [
              Expanded(
                child: SegmentedButton<PrinterType>(
                  segments: [
                    const ButtonSegment(value: PrinterType.bluetooth, label: Text('Bluetooth'), icon: Icon(Icons.bluetooth)),
                    ButtonSegment(value: PrinterType.usb, label: Text(!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ? 'Sistem / USB' : 'USB'), icon: const Icon(Icons.usb)),
                  ],
                  selected: {defaultPrinterType},
                  onSelectionChanged: (Set<PrinterType> newSelection) {
                    setState(() {
                      defaultPrinterType = newSelection.first;
                    });
                    _startScan();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: isScanning ? null : _startScan,
                icon: isScanning ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                tooltip: 'Scan ulang',
              )
            ],
          ),
          const SizedBox(height: 16),
          
          // Device List
          Expanded(
            child: devices.isEmpty 
              ? Center(child: Text(isScanning ? 'Mencari printer...' : 'Tidak ada printer ditemukan'))
              : ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isSelected = selected != null && selected.address == device.address && _printerService.isConnected;
                    final address = defaultPrinterType == PrinterType.bluetooth ? device.address : device.name;
                    final isConnecting = connectingDeviceAddress == address;
                    final isFailed = failedDeviceAddress == address;
                    
                    Widget trailingWidget;
                    if (isConnecting) {
                       trailingWidget = const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
                    } else if (isSelected) {
                       trailingWidget = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                            child: Text('TERHUBUNG', style: TextStyle(color: cs.onPrimaryContainer, fontSize: 10, fontWeight: FontWeight.bold)),
                          );
                    } else {
                       trailingWidget = const SizedBox.shrink();
                    }

                    return ListTile(
                      title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(device.address ?? '', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          if (isConnecting)
                            Text('Menghubungkan...', style: TextStyle(fontSize: 12, color: cs.primary, fontStyle: FontStyle.italic)),
                          if (isFailed)
                            Text('Gagal Terhubung', style: TextStyle(color: cs.error, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      leading: Icon(
                        defaultPrinterType == PrinterType.bluetooth ? Icons.bluetooth : Icons.usb,
                        color: isSelected ? cs.primary : null,
                      ),
                      trailing: trailingWidget,
                      onTap: (isSelected || isConnecting) ? null : () => _connect(device),
                    );
                  },
                ),
          ),
          
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: selected == null ? null : _testPrint,
              icon: const Icon(Icons.print),
              label: const Text('Test Print'),
            ),
          )
        ],
      ),
    );

    if (isMobile) {
      return Dialog.fullscreen(child: content);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: content,
      ),
    );
  }
}
