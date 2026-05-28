import 'dart:io';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import '../core/helpers.dart';

class ReceiptGenerator {
  static String _formatReceiptPrice(dynamic val) {
    if (val == null) return 'Rp 0';
    double dVal = 0.0;
    if (val is num) {
      dVal = val.toDouble();
    } else {
      dVal = double.tryParse(val.toString()) ?? 0.0;
    }
    // Strictly format as absolute integer to remove any decimal truncation issues
    int intVal = dVal.round();
    final formatted = intVal.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
    return 'Rp $formatted';
  }

  static Future<List<int>> generate({
    required Map<String, dynamic> transaction,
    required List<Map<String, dynamic>> details,
    required Map<String, dynamic> settings,
    PaperSize paperSize = PaperSize.mm58,
    CapabilityProfile? profile,
  }) async {
    profile ??= await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    // Header
    final storeName = settings['store_name']?.toString() ?? 'KAYPOS Store';
    final storeSubName = settings['store_sub_name']?.toString() ?? '';
    final storeAddr = settings['store_address']?.toString() ?? '';
    final storePhone = settings['store_phone']?.toString() ?? '';
    final storePromo = settings['store_promo']?.toString() ?? '';
    final printLogo = (settings['print_logo'] ?? '1') == '1';
    final printStoreName = (settings['print_store_name'] ?? '1') == '1';
    final logoPath = settings['store_logo_path']?.toString() ?? '';

    // --- Logo ---
    if (printLogo && logoPath.isNotEmpty) {
      try {
        final logoFile = File(logoPath);
        if (logoFile.existsSync()) {
          final rawBytes = logoFile.readAsBytesSync();
          final decoded = img.decodeImage(rawBytes);
          if (decoded != null) {
            final targetWidth = paperSize == PaperSize.mm58 ? 384 : 576;
            final resized = img.copyResize(decoded, width: targetWidth);
            bytes += generator.imageRaster(resized, align: PosAlign.center);
            bytes += generator.feed(1);
          }
        }
      } catch (_) {}
    }

    // --- Store Name ---
    if (printStoreName) {
      bytes += generator.text(storeName,
          styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    }
    if (storeSubName.isNotEmpty) {
      bytes += generator.text(storeSubName, styles: const PosStyles(align: PosAlign.center));
    }
    if (storeAddr.isNotEmpty) {
      bytes += generator.text(storeAddr, styles: const PosStyles(align: PosAlign.center));
    }
    if (storePhone.isNotEmpty) {
      bytes += generator.text('Tel: $storePhone', styles: const PosStyles(align: PosAlign.center));
    }
    bytes += generator.feed(1);

    // Transaction info
    bytes += generator.hr(ch: '-');
    final dateStr = fmtDate(transaction['created_at'] ?? '');
    
    bytes += generator.row([
      PosColumn(text: '#${transaction['id']}', width: 6, styles: const PosStyles(align: PosAlign.left)),
      PosColumn(text: dateStr, width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    
    bytes += generator.row([
      PosColumn(text: 'Kasir:', width: 6, styles: const PosStyles(align: PosAlign.left)),
      PosColumn(text: transaction['cashier_name']?.toString() ?? '-', width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.hr(ch: '-');

    // Items
    dynamic lastProductId;
    for (var d in details) {
      final isPaket = (d['is_paket'] as num?)?.toInt() == 1;
      final qty = (d['quantity'] as num?)?.toDouble() ?? 0.0;
      final qtyStr = qty == qty.truncateToDouble() ? qty.truncate().toString() : qty.toStringAsFixed(2);
      int maxChars = paperSize == PaperSize.mm58 ? 32 : 48;

      if (isPaket) {
        final paketName = '${qtyStr}x ${d['product_name'] ?? ''}';
        final subtotalStr = _formatReceiptPrice(d['subtotal']);
        int combinedLen = paketName.length + subtotalStr.length;
        
        if (combinedLen < maxChars) {
          String space = ' ' * (maxChars - combinedLen);
          bytes += generator.text('$paketName$space$subtotalStr', styles: const PosStyles(bold: true));
        } else {
          bytes += generator.text(paketName, styles: const PosStyles(bold: true));
          bytes += generator.text(subtotalStr, styles: const PosStyles(align: PosAlign.right, bold: true));
        }
        
        final addonSummary = d['addon_summary']?.toString() ?? '';
        if (addonSummary.isNotEmpty && addonSummary != '[]') {
          for (final line in addonSummary.split('\n')) {
             String cleanedLine = line.replaceAll('  - ', '   ').replaceAll(' (Rp 0)', '');
             String rightText = 'Rp 0';
             int lineCombinedLen = cleanedLine.length + rightText.length;
             if (lineCombinedLen < maxChars) {
                String space = ' ' * (maxChars - lineCombinedLen);
                bytes += generator.text('$cleanedLine$space$rightText', styles: const PosStyles(align: PosAlign.left));
             } else {
                bytes += generator.text(cleanedLine, styles: const PosStyles(align: PosAlign.left));
                bytes += generator.text(rightText, styles: const PosStyles(align: PosAlign.right));
             }
          }
        }
        
        final itemDiscount = (d['discount_amount'] as num?)?.toDouble() ?? 0.0;
        if (itemDiscount > 0) {
          bytes += generator.text('  - Rp ${_formatReceiptPrice(itemDiscount)}', styles: const PosStyles(align: PosAlign.left));
        }
      } else {
        if (lastProductId != d['product_id'] || d['product_id'] == null) {
          bytes += generator.text(d['product_name']?.toString() ?? '', styles: const PosStyles(bold: true));
          lastProductId = d['product_id'];
        }
        
        final unitUsed = d['unit_used']?.toString() ?? 'pcs';
        final formattedUnit = '$qtyStr $unitUsed';
        
        final price = _formatReceiptPrice(d['sold_price']).replaceAll(' ', '');
        final subtotal = _formatReceiptPrice(d['subtotal']);
        
        final condensedUnit = formattedUnit.replaceAll(' ', '');
        final desc = '  $condensedUnit @$price';
        
        int combinedLen = desc.length + subtotal.length;
        
        if (combinedLen < maxChars) {
          String space = ' ' * (maxChars - combinedLen);
          bytes += generator.text('$desc$space$subtotal', styles: const PosStyles(align: PosAlign.left));
        } else {
          bytes += generator.text(desc, styles: const PosStyles(align: PosAlign.left));
          bytes += generator.text(subtotal, styles: const PosStyles(align: PosAlign.right));
        }

        final itemDiscount = (d['discount_amount'] as num?)?.toDouble() ?? 0.0;
        if (itemDiscount > 0) {
          bytes += generator.text('  - Rp ${_formatReceiptPrice(itemDiscount)}', styles: const PosStyles(align: PosAlign.left));
        }
        
        final addonSummary = d['addon_summary']?.toString() ?? '';
        if (addonSummary.isNotEmpty && addonSummary != '[]') {
          for (final line in addonSummary.split('\n')) {
            bytes += generator.text(line, styles: const PosStyles(align: PosAlign.left));
          }
        }
      }
    }

    bytes += generator.hr(ch: '-');

    // Totals
    final totalAmount = (transaction['total_amount'] as num?)?.toDouble() ?? 0.0;
    final totalDiscount = (transaction['discount_total'] as num?)?.toDouble() ?? 0.0;
    
    double systemPromo = 0.0;
    for (var d in details) {
      systemPromo += (d['discount_amount'] as num?)?.toDouble() ?? 0.0;
    }
    
    double cashierDiscount = totalDiscount - systemPromo;
    if (cashierDiscount < 0) cashierDiscount = 0; // fallback

    final hargaAkhir = totalAmount - totalDiscount;

    bytes += generator.row([
      PosColumn(text: 'Harga Awal', width: 6),
      PosColumn(text: fmtPrice(totalAmount), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    if (systemPromo > 0) {
      bytes += generator.row([
        PosColumn(text: 'Diskon Promo', width: 6),
        PosColumn(text: fmtPrice(systemPromo), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    
    if (cashierDiscount > 0) {
      bytes += generator.row([
        PosColumn(text: 'Diskon Kasir', width: 6),
        PosColumn(text: fmtPrice(cashierDiscount), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr(ch: '-');

    bytes += generator.row([
      PosColumn(text: 'Harga Akhir', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: fmtPrice(hargaAkhir), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);
    bytes += generator.hr(ch: '-');
    bytes += generator.row([
      PosColumn(text: 'Bayar', width: 6),
      PosColumn(text: fmtPrice(transaction['paid_amount'] ?? 0), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Kembali', width: 6),
      PosColumn(text: fmtPrice(transaction['change_amount'] ?? 0), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    bytes += generator.hr(ch: '-');

    // Footer
    bytes += generator.feed(1);
    bytes += generator.text('Terima Kasih', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Barang yang sudah dibeli', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('tidak dapat dikembalikan', styles: const PosStyles(align: PosAlign.center));
    
    // Promo / campaign text
    if (storePromo.isNotEmpty) {
      bytes += generator.feed(1);
      bytes += generator.hr(ch: '-');
      for (final line in storePromo.split('\n')) {
        bytes += generator.text(line.trim(), styles: const PosStyles(align: PosAlign.center));
      }
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  static Future<List<int>> generateTestPrint({
    required Map<String, dynamic> settings,
    PaperSize paperSize = PaperSize.mm58,
    CapabilityProfile? profile,
  }) async {
    profile ??= await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    // Header
    final storeName = settings['store_name']?.toString() ?? 'KAYPOS Store';

    bytes += generator.text(storeName,
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    
    bytes += generator.text('Test Print OK!', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr(ch: '-');
    bytes += generator.text(fmtDate(DateTime.now().toIso8601String()), styles: const PosStyles(align: PosAlign.center));
    
    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }
}
