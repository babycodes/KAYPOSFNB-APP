import 'package:flutter/material.dart';
import '../../../core/helpers.dart';

class UnitSelectorDialog extends StatefulWidget {
  final dynamic product;
  final double availableStock;
  final Function(dynamic, String, num) onConfirm;
  const UnitSelectorDialog({super.key, required this.product, required this.availableStock, required this.onConfirm});
  @override
  State<UnitSelectorDialog> createState() => _UnitSelectorDialogState();
}

class _UnitSelectorDialogState extends State<UnitSelectorDialog> {
  late String selectedUnit;
  double quantity = 1;
  late TextEditingController _qtyCtrl;

  // Safe num parser
  static double _safeNum(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    final List units = (widget.product is Map && widget.product['units'] is List) ? widget.product['units'] : [];
    selectedUnit = units.isNotEmpty ? (units.first['unit_name']?.toString() ?? '') : '';
    _qtyCtrl = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get selectedUnitData {
    final List units = (widget.product is Map && widget.product['units'] is List) ? widget.product['units'] : [];
    try { return Map<String, dynamic>.from(units.firstWhere((u) => u['unit_name']?.toString() == selectedUnit)); } catch (_) { return null; }
  }

  double get pricePerOne => _safeNum(selectedUnitData?['price']);
  double get totalPrice => pricePerOne * quantity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final List units = (widget.product is Map && widget.product['units'] is List) ? widget.product['units'] : [];
    final String productName = (widget.product is Map ? widget.product['name'] : null)?.toString() ?? 'Produk';
    final String categoryIcon = (widget.product is Map ? widget.product['category_icon'] : null)?.toString() ?? '\u{1F4E6}';
    final String categoryName = (widget.product is Map ? widget.product['category_name'] : null)?.toString() ?? '';

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Padding(padding: const EdgeInsets.all(20), child: Row(children: [
          buildCategoryIcon(categoryIcon, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(productName, style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(categoryName, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
        ])),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
        Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pilih Satuan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.5,
            children: units.map<Widget>((u) {
              final String uName = u['unit_name']?.toString() ?? '';
              final selected = selectedUnit == uName;
              final mult = _safeNum(u['qty_per_unit'], 1);
              final String baseUnitName = (widget.product['base_unit']?.toString().isNotEmpty == true) ? widget.product['base_unit'].toString() : '';
              final double uPrice = _safeNum(u['price']);
              
              return InkWell(onTap: () => setState(() => selectedUnit = uName),
                borderRadius: BorderRadius.circular(12),
                child: Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5), width: selected ? 2 : 1),
                    color: selected ? cs.primaryContainer.withValues(alpha: 0.3) : cs.surfaceContainer),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(uName.isEmpty ? 'Satuan Default' : uName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
                    Text(fmtPrice(uPrice), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    if (mult > 1)
                      Text('(${mult == mult.roundToDouble() ? mult.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.') : mult.toString()} $baseUnitName)', style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600)),
                  ])));
            }).toList()),
          const SizedBox(height: 20),
          // Quantity
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Text('Jumlah', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(width: 8),
              InkWell(onTap: () {
                final qtyPerUnit = _safeNum(selectedUnitData?['qty_per_unit'], 1.0);
                final maxAllowed = widget.availableStock == double.infinity ? double.infinity : (widget.availableStock / qtyPerUnit);
                if (maxAllowed < double.infinity && maxAllowed > 0) {
                  setState(() {
                    quantity = maxAllowed;
                    _qtyCtrl.text = maxAllowed == maxAllowed.roundToDouble() ? '${maxAllowed.round()}' : maxAllowed.toStringAsFixed(2);
                  });
                  Navigator.pop(context);
                  widget.onConfirm(widget.product, selectedUnit, maxAllowed);
                }
              }, child: const Text('MAX', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue))),
            ]),
            Container(
              width: 180,
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                InkWell(onTap: () { 
                  if (quantity > 0.25) {
                    setState(() { 
                      quantity = (quantity - (quantity >= 1 ? 1 : 0.25)); 
                      _qtyCtrl.text = quantity == quantity.roundToDouble() ? '${quantity.round()}' : quantity.toStringAsFixed(2);
                    }); 
                  }
                },
                  child: Container(width: 44, height: 44, decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.remove, size: 18, color: cs.onSurface))),
                Expanded(child: TextField(
                  controller: _qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: cs.onSurface),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
                  onChanged: (v) {
                    final val = double.tryParse(v.replaceAll(',', '.'));
                    if (val != null && val >= 0) {
                      final qtyPerUnit = _safeNum(selectedUnitData?['qty_per_unit'], 1.0);
                      final maxAllowed = widget.availableStock == double.infinity ? double.infinity : (widget.availableStock / qtyPerUnit);
                      
                      if (val > maxAllowed) {
                        setState(() {
                          quantity = maxAllowed;
                          _qtyCtrl.text = maxAllowed == maxAllowed.roundToDouble() ? '${maxAllowed.round()}' : maxAllowed.toStringAsFixed(2);
                        });
                      } else {
                        setState(() => quantity = val);
                      }
                    }
                  },
                )),
                InkWell(onTap: () {
                  final qtyPerUnit = _safeNum(selectedUnitData?['qty_per_unit'], 1.0);
                  final maxAllowed = widget.availableStock == double.infinity ? double.infinity : (widget.availableStock / qtyPerUnit);
                  
                  if (quantity + 1 <= maxAllowed) {
                    setState(() { 
                      quantity += 1;
                      _qtyCtrl.text = quantity == quantity.roundToDouble() ? '${quantity.round()}' : quantity.toStringAsFixed(2);
                    });
                  } else if (quantity < maxAllowed) {
                    setState(() { 
                      quantity = maxAllowed;
                      _qtyCtrl.text = quantity == quantity.roundToDouble() ? '${quantity.round()}' : quantity.toStringAsFixed(2);
                    });
                  }
                },
                  child: Container(width: 44, height: 44, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.add, size: 18, color: cs.onPrimary))),
              ])),
          ]),
          const SizedBox(height: 16),
          // Total
          Container(width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.secondaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.secondary.withValues(alpha: 0.2))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
              Text(fmtPrice(totalPrice), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.secondary)),
            ])),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: SizedBox(height: 48, child: OutlinedButton(onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Batal')))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: SizedBox(height: 48, child: FilledButton.icon(
              onPressed: quantity > 0 ? () { Navigator.pop(context); widget.onConfirm(widget.product, selectedUnit, quantity); } : null,
              icon: const Icon(Icons.shopping_cart, size: 18),
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 1),
              label: const Text('Tambah ke Keranjang', style: TextStyle(fontWeight: FontWeight.bold))))),
          ]),
        ])),
      ])),
    );
  }
}
