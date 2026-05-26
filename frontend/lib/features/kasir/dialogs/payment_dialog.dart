import 'package:flutter/material.dart';
import '../../../core/helpers.dart';

String _fmtInput(String digits) {
  if (digits.isEmpty) return '';
  return digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}

class PaymentDialog extends StatefulWidget {
  final double subtotal;
  final double systemDiscount;
  final Function(double paidAmount, double discountTotal, String discountType, String discountBy) onConfirm;
  const PaymentDialog({super.key, required this.subtotal, required this.systemDiscount, required this.onConfirm});
  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  double paidAmount = 0;
  double manualDiscountValue = 0;
  bool isDiscountPercent = true;
  final _customCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  
  double get totalDiscountAmount {
    double manualDiscountAmount = 0;
    if (manualDiscountValue > 0) {
      if (isDiscountPercent) {
        manualDiscountAmount = widget.subtotal * (manualDiscountValue / 100);
      } else {
        manualDiscountAmount = manualDiscountValue;
      }
    }
    return widget.systemDiscount + manualDiscountAmount;
  }
  
  double get finalTotal => widget.subtotal - totalDiscountAmount;

  final shortcuts = [
    {'label': 'Uang Pas', 'value': 'exact'},
    {'label': '10rb', 'value': 10000},
    {'label': '20rb', 'value': 20000},
    {'label': '50rb', 'value': 50000},
    {'label': '100rb', 'value': 100000},
    {'label': '200rb', 'value': 200000},
    {'label': '500rb', 'value': 500000},
    {'label': '1 Juta', 'value': 1000000},
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final change = paidAmount - finalTotal;
    final isValid = paidAmount >= finalTotal && finalTotal >= 0;

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    
    // Validation Text Logic based on ORIGINAL Subtotal
    final maxPercent = 5.0;
    final maxAllowedAmount = widget.subtotal * 0.05;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9, maxWidth: 500),
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('Pembayaran', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 16),
        // Total
        Container(
          width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.primary.withValues(alpha: 0.2))),
          child: Column(children: [
            if (widget.systemDiscount > 0 || manualDiscountValue > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  Text(fmtPrice(widget.subtotal), style: TextStyle(fontSize: 12, decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Diskon Sistem & Kasir', style: TextStyle(fontSize: 12, color: Colors.green)),
                  Text('-${fmtPrice(totalDiscountAmount)}', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 12),
            ],
            Text('TOTAL TAGIHAN', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(fmtPrice(finalTotal), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: cs.primary)),
          ]),
        ),
        const SizedBox(height: 16),
        // Manual Discount
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Diskon Tambahan Kasir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '0',
                        prefixText: isDiscountPercent ? null : 'Rp ',
                        suffixText: isDiscountPercent ? '%' : null,
                        isDense: true,
                        filled: true,
                        fillColor: cs.surface,
                      ),
                      onChanged: (v) {
                        final val = double.tryParse(v.replaceAll(RegExp('[^0-9]'), '')) ?? 0;
                        double finalVal = val;
                        
                        // Strict Validation: Manual <= System (or < 50 if no system)
                        if (isDiscountPercent) {
                          if (val > maxPercent) finalVal = maxPercent;
                        } else {
                          if (val > maxAllowedAmount) finalVal = maxAllowedAmount;
                        }

                        if (finalVal != val) {
                          _discountCtrl.text = finalVal.toStringAsFixed(0);
                          _discountCtrl.selection = TextSelection.collapsed(offset: _discountCtrl.text.length);
                        }
                        
                        setState(() => manualDiscountValue = finalVal);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToggleButtons(
                    isSelected: [isDiscountPercent, !isDiscountPercent],
                    onPressed: (index) {
                      setState(() {
                        isDiscountPercent = index == 0;
                        _discountCtrl.clear();
                        manualDiscountValue = 0;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                    children: const [
                      Text('%', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Rp', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Maksimal: ${maxPercent.toStringAsFixed(0)}% (Rp ${fmtPrice(maxAllowedAmount).replaceAll('Rp ', '')})', 
                  style: TextStyle(fontSize: 10, color: cs.error)
                ),
              )
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Shortcuts
        GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.2,
          children: shortcuts.map((s) {
            final val = s['value'] == 'exact' ? finalTotal : (s['value'] as num).toDouble();
            final selected = paidAmount == val;
            return InkWell(
              onTap: () => setState(() { paidAmount = val; _customCtrl.text = _fmtInput('${val.round()}'); }),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1)),
                child: Center(child: Text(s['label'] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface))),
              ),
            );
          }).toList()),
        const SizedBox(height: 16),
        // Custom input
        Text('ATAU MASUKKAN NOMINAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant, letterSpacing: 1)),
        const SizedBox(height: 8),
        TextField(
          controller: _customCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.right,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface),
          decoration: InputDecoration(prefixText: 'Rp ', filled: true, fillColor: cs.surfaceContainer),
          onChanged: (v) {
            final digits = v.replaceAll(RegExp('[^0-9]'), '');
            final parsed = double.tryParse(digits) ?? 0;
            final formatted = _fmtInput(digits);
            if (_customCtrl.text != formatted) {
              _customCtrl.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
            }
            setState(() => paidAmount = parsed);
          },
        ),
        const SizedBox(height: 16),
        // Change
        if (paidAmount > 0) Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: change >= 0 ? cs.secondaryContainer.withValues(alpha: 0.3) : cs.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12), border: Border.all(color: change >= 0 ? cs.secondary.withValues(alpha: 0.2) : cs.error.withValues(alpha: 0.2))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(change >= 0 ? 'Kembalian' : 'Kurang', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: change >= 0 ? cs.secondary : cs.error)),
            Text(fmtPrice(change.abs()), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: change >= 0 ? cs.secondary : cs.error)),
          ]),
        ),
        const SizedBox(height: 20),
        // Buttons
        Row(children: [
          Expanded(child: SizedBox(height: 56, child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
          ))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: SizedBox(height: 56, child: FilledButton(
            onPressed: isValid ? () { 
              Navigator.pop(context);
              String dType = 'system';
              String dBy = 'system';
              if (widget.systemDiscount > 0 && manualDiscountValue > 0) {
                dType = 'stacked';
                dBy = 'system_and_cashier';
              } else if (manualDiscountValue > 0) {
                dType = 'manual';
                dBy = 'cashier';
              }
              widget.onConfirm(paidAmount, totalDiscountAmount, dType, dBy);
            } : null,
            style: FilledButton.styleFrom(backgroundColor: cs.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 1),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check, size: 20), SizedBox(width: 8), Text('Konfirmasi & Cetak', style: TextStyle(fontWeight: FontWeight.bold))]),
          ))),
        ]),
      ])),
    );
  }
}
