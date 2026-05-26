// KAYPOS — Helpers
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';

String fmtPrice(num n) {
  if (n < 1 && n > 0) return 'Rp ${n.toStringAsFixed(2)}';
  final formatted = n.round().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return 'Rp $formatted';
}

String fmtDate(String d) {
  try {
    final dt = DateTime.parse(d);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return d;
  }
}

void showToast(BuildContext context, String msg) {
  final cs = Theme.of(context).colorScheme;
  final isError = msg.startsWith('❌') || msg.toLowerCase().contains('gagal') || msg.toLowerCase().contains('error');
  final bgColor = isError ? cs.error : cs.primary;
  final fgColor = isError ? cs.onError : cs.onPrimary;

  BotToast.showCustomText(
    duration: const Duration(seconds: 3),
    onlyOne: true,
    toastBuilder: (cancelFunc) {
      return Align(
        alignment: const Alignment(0, 0.85),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: bgColor.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  msg,
                  style: TextStyle(
                    color: fgColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void showAdminToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      backgroundColor: Colors.blue,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    )
  );
}

String formatStock(num baseStock, List<dynamic>? units, String? baseUnit) {
  final bUnit = (baseUnit == null || baseUnit.trim().isEmpty) ? 'pcs' : baseUnit.trim();
  if (baseStock <= 0) return '0 $bUnit';
  
  if (units != null && units.isNotEmpty) {
    final sortedUnits = List.from(units)..sort((a, b) => ((b['qty_per_unit'] as num?) ?? 1).compareTo((a['qty_per_unit'] as num?) ?? 1));
    
    for (final u in sortedUnits) {
      final qtyPerUnit = (u['qty_per_unit'] as num?)?.toDouble() ?? 1.0;
      if (qtyPerUnit > 1 && baseStock >= qtyPerUnit) {
        final majorQty = (baseStock / qtyPerUnit).floor();
        final remainder = baseStock - (majorQty * qtyPerUnit);
        
        final majorStr = majorQty.toString();
        if (remainder <= 0.001) {
          return '$majorStr ${u['unit_name']}';
        } else {
          final remStr = remainder == remainder.truncateToDouble() ? remainder.truncate().toString() : remainder.toStringAsFixed(2).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
          return '$majorStr ${u['unit_name']} $remStr $bUnit';
        }
      }
    }
  }
  final bStr = baseStock == baseStock.truncateToDouble() ? baseStock.truncate().toString() : baseStock.toStringAsFixed(2).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
  return '$bStr $bUnit';
}

String formatCartItemDisplay(double qty, dynamic currentUnitData, List<dynamic>? productUnits, String? baseUnit) {
  final bUnit = (baseUnit == null || baseUnit.trim().isEmpty) ? 'pcs' : baseUnit.trim();
  final currentMultiplier = (currentUnitData?['qty_per_unit'] as num?)?.toDouble() ?? 1.0;
  final currentUnitName = (currentUnitData?['unit_name'] as String?) ?? bUnit;
  final totalBase = qty * currentMultiplier;

  if (productUnits != null && productUnits.isNotEmpty) {
    final sortedUnits = List.from(productUnits)..sort((a, b) => ((b['qty_per_unit'] as num?) ?? 1).compareTo((a['qty_per_unit'] as num?) ?? 1));
    
    bool canUpgrade = sortedUnits.any((u) {
      final qpu = (u['qty_per_unit'] as num?)?.toDouble() ?? 1.0;
      return qpu > currentMultiplier && totalBase >= qpu;
    });

    if (canUpgrade) {
      return formatStock(totalBase, productUnits, baseUnit);
    }
  }

  final qtyStr = qty == qty.truncateToDouble() ? qty.truncate().toString() : qty.toStringAsFixed(2).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
  
  final lcUnitName = currentUnitName.toLowerCase();
  final isFractionalUnit = lcUnitName.contains('seperempat') || lcUnitName.contains('setengah');
  final isFractionalMultiplier = currentMultiplier == 250 || currentMultiplier == 500;
  
  if (qty > 1 && (isFractionalUnit || isFractionalMultiplier)) {
    final multStr = currentMultiplier == currentMultiplier.truncateToDouble() ? currentMultiplier.truncate().toString() : currentMultiplier.toStringAsFixed(2).replaceAll(RegExp(r'0*$'), '').replaceAll(RegExp(r'\.$'), '');
    return '${qtyStr}x$multStr$bUnit';
  }

  return '$qtyStr $currentUnitName';
}

String toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

const Map<String, IconData> categoryIcons = {
  '📦': Icons.inventory_2,
  '🍔': Icons.fastfood,
  '🥤': Icons.local_drink,
  '🛍️': Icons.shopping_bag,
  '🏷️': Icons.local_offer,
  '☕': Icons.local_cafe,
  '🍰': Icons.cake,
  '🍎': Icons.apple,
  '📱': Icons.smartphone,
  '💻': Icons.computer,
  '👕': Icons.checkroom,
  '💊': Icons.medical_services,
  '🛠️': Icons.build,
  '📚': Icons.menu_book,
  '⚽': Icons.sports_soccer,
  '🚗': Icons.directions_car,
  '🏠': Icons.home,
  '🎵': Icons.music_note,
  '🐾': Icons.pets,
  '🧩': Icons.extension,
};

Widget buildCategoryIcon(String iconKey, {double size = 24}) {
  final iconData = categoryIcons[iconKey];
  if (iconData != null) {
    return Icon(iconData, size: size);
  }
  return Text(iconKey, style: TextStyle(fontSize: size));
}
