import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/helpers.dart';

class CartItemWidget extends StatefulWidget {
  final Map<String, dynamic> item;
  final int maxAllowedQty;
  final VoidCallback onIncrement, onDecrement, onRemove;
  final ValueChanged<double>? onSetQuantity;
  const CartItemWidget({super.key, required this.item, this.maxAllowedQty = 9999, required this.onIncrement, required this.onDecrement, required this.onRemove, this.onSetQuantity});

  @override
  State<CartItemWidget> createState() => _CartItemWidgetState();
}

class _CartItemWidgetState extends State<CartItemWidget> {
  bool _editing = false;
  late TextEditingController _editCtrl;

  // Safe num parser
  static double _safeNum(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController();
  }

  @override
  void dispose() { _editCtrl.dispose(); super.dispose(); }

  void _startEdit() {
    final qty = _safeNum(widget.item['quantity']);
    _editCtrl.text = qty == qty.roundToDouble() ? '${qty.round()}' : qty.toString();
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _editCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _editCtrl.text.length));
  }

  void _commitEdit() {
    var val = double.tryParse(_editCtrl.text.replaceAll('.', '').replaceAll(',', '.'));
    if (val != null && val > 0 && widget.onSetQuantity != null) {
      // Clamp to maxAllowedQty
      if (val > widget.maxAllowedQty) val = widget.maxAllowedQty.toDouble();
      widget.onSetQuantity!(val);
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildBody(context);
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(6),
        color: Colors.red.shade100,
        child: Text('CartItem Error: $e', style: const TextStyle(fontSize: 8, color: Colors.red)),
      );
    }
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unitPrice = _safeNum(widget.item['unit_price']);
    final quantity = _safeNum(widget.item['quantity']);
    final int discountPercent = int.tryParse(widget.item['discount_percent']?.toString() ?? '0') ?? 0;
    
    final finalUnitPrice = unitPrice * (1 - discountPercent / 100);
    final subtotal = finalUnitPrice * quantity;
    final qtyStr = quantity == quantity.roundToDouble() ? '${quantity.round()}' : quantity.toStringAsFixed(1);

    final product = widget.item['product'];
    final productName = (product is Map ? product['name'] : null)?.toString() ?? 'Item';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4))),
      child: Row(children: [
        // Name + unit info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(productName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (widget.item['addon_summary'] != null && widget.item['addon_summary'].toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(widget.item['addon_summary'].toString(), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 1),
          if (discountPercent > 0) ...[
            Text('${fmtPrice(unitPrice)} × $qtyStr', style: TextStyle(fontSize: 10, decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant)),
            Text('${fmtPrice(finalUnitPrice)} × $qtyStr', style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
          ] else
            Text('${fmtPrice(unitPrice)} × $qtyStr', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 4),
        // Subtotal
        Text(fmtPrice(subtotal), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cs.primary)),
        const SizedBox(width: 6),
        // Compact qty controls with tappable number
        Container(
          height: 28,
          decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Minus/Delete button
            InkWell(
              onTap: quantity <= 1 ? widget.onRemove : widget.onDecrement,
              child: Container(width: 26, height: 28,
                decoration: BoxDecoration(color: quantity <= 1 ? cs.errorContainer.withValues(alpha: 0.4) : Colors.transparent, borderRadius: const BorderRadius.horizontal(left: Radius.circular(5))),
                child: Icon(quantity <= 1 ? Icons.delete_outline : Icons.remove, size: 12, color: quantity <= 1 ? cs.error : cs.onSurface)),
            ),
            // Tappable/editable quantity
            _editing
              ? Container(constraints: const BoxConstraints(minWidth: 36, maxWidth: 70), height: 28, child: TextField(
                  controller: _editCtrl, autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: cs.onSurface),
                  decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2), border: InputBorder.none, fillColor: cs.surfaceContainer, filled: true),
                  onSubmitted: (_) => _commitEdit(),
                  onTapOutside: (_) => _commitEdit(),
                ))
              : InkWell(onTap: _startEdit,
                  child: Container(constraints: const BoxConstraints(minWidth: 30, maxWidth: 70), padding: const EdgeInsets.symmetric(horizontal: 4), height: 28, alignment: Alignment.center,
                    child: Text(qtyStr, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis))),
            // Plus button
            InkWell(onTap: _safeNum(widget.item['quantity']).round() >= widget.maxAllowedQty ? null : widget.onIncrement,
              child: Container(width: 26, height: 28,
                decoration: BoxDecoration(
                  color: _safeNum(widget.item['quantity']).round() >= widget.maxAllowedQty ? cs.surfaceContainerHighest : cs.primary,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(5))),
                child: Icon(Icons.add, size: 12, color: _safeNum(widget.item['quantity']).round() >= widget.maxAllowedQty ? cs.onSurfaceVariant : cs.onPrimary))),
          ]),
        ),
      ]),
    );
  }
}
