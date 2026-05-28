import 'package:flutter/material.dart';
import '../../../core/api.dart';
import '../../../core/helpers.dart';
import '../../../services/printer_service.dart';
import '../../../services/receipt_generator.dart';
class ReceiptModal extends StatefulWidget {
  final dynamic transaction;
  final List<Map<String, dynamic>> details;
  const ReceiptModal({super.key, required this.transaction, required this.details});
  @override
  State<ReceiptModal> createState() => _ReceiptModalState();
}

class _ReceiptModalState extends State<ReceiptModal> {
  bool _printing = false;
  String _printMsg = '';

  Future<void> _printReceipt() async {
    setState(() { _printing = true; _printMsg = ''; });
    try {
      if (!PrinterService().isConnected) {
        setState(() { _printMsg = '⚠️ Printer belum terhubung'; _printing = false; });
        return;
      }
      
      // Fetch settings
      final settingsRes = await Api.get('/settings');
      Map<String, dynamic> settings = {};
      if (settingsRes != null && settingsRes is Map<String, dynamic>) {
        settings = settingsRes;
      }
      
      // Generate receipt bytes locally using capability profile
      final bytes = await ReceiptGenerator.generate(
        transaction: widget.transaction,
        details: widget.details,
        settings: settings,
      );
      
      await PrinterService().printReceipt(bytes);
      setState(() => _printMsg = '✅ Nota berhasil dicetak!');
    } catch (e) {
      setState(() => _printMsg = '⚠️ ${e.toString().replaceFirst("Exception: ", "")}');
    }
    setState(() => _printing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Success Header
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF059669)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 36, color: Colors.white)),
              const SizedBox(height: 12),
              const Text('Transaksi Berhasil!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('#${widget.transaction['id']} — ${fmtDate(widget.transaction['created_at'] ?? '')}', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ]),
          ),
          // Items
          ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
              ...widget.details.map((d) {
                final qty = (d['quantity'] as num?)?.toDouble() ?? 0.0;
                final unitUsed = d['unit_used']?.toString() ?? 'pcs';
                final qtyStr = qty == qty.truncateToDouble() ? qty.truncate().toString() : qty.toStringAsFixed(2);
                final formattedUnit = '$qtyStr $unitUsed';
                final itemDiscount = (d['discount_amount'] as num?)?.toDouble() ?? 0.0;
                
                return Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d['product_name'] ?? '', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: cs.onSurface)),
                    Text('$formattedUnit × ${fmtPrice(d['sold_price'] ?? 0)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    if (itemDiscount > 0)
                      Text('  - Rp ${fmtPrice(itemDiscount)}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                    if (d['addon_summary'] != null && d['addon_summary'].toString().isNotEmpty && d['addon_summary'].toString() != '[]')
                      Text(d['addon_summary'].toString(), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  ])),
                  Text(fmtPrice(d['subtotal'] ?? 0), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
                ]));
              }),
              Divider(color: cs.outlineVariant),
              Builder(builder: (context) {
                final systemPromo = widget.details.fold<double>(0, (sum, item) => sum + ((item['discount_amount'] as num?)?.toDouble() ?? 0.0));
                final totalDiscount = (widget.transaction['discount_total'] as num?)?.toDouble() ?? 0.0;
                double cashierDiscount = totalDiscount - systemPromo;
                if (cashierDiscount < 0) cashierDiscount = 0; // fallback just in case
                
                return Column(
                  children: [
                    _row('Harga Awal', fmtPrice(widget.transaction['total_amount'] ?? 0), cs),
                    if (systemPromo > 0)
                      _row('Diskon Promo', fmtPrice(systemPromo), cs),
                    if (cashierDiscount > 0)
                      _row('Diskon Kasir', fmtPrice(cashierDiscount), cs),
                    Divider(color: cs.outlineVariant),
                    _row('Harga Akhir', fmtPrice((widget.transaction['total_amount'] ?? 0) - totalDiscount), cs, bold: true, size: 18),
                    Divider(color: cs.outlineVariant),
                  ],
                );
              }),
              _row('Bayar', fmtPrice(widget.transaction['paid_amount'] ?? 0), cs),
              _row('Kembali', fmtPrice(widget.transaction['change_amount'] ?? 0), cs),
            ])),
          // Print message
          if (_printMsg.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(width: double.infinity, padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: _printMsg.startsWith('✅') ? Colors.green.withValues(alpha: 0.1) : cs.errorContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
              child: Text(_printMsg, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _printMsg.startsWith('✅') ? Colors.green : cs.onSurfaceVariant), textAlign: TextAlign.center))),
          // Actions
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Row(children: [
            Expanded(child: SizedBox(height: 48, child: OutlinedButton(onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.w600))))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: SizedBox(height: 48, child: FilledButton.icon(
              onPressed: _printing ? null : _printReceipt, icon: _printing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.print, size: 18),
              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 1),
              label: Text(_printing ? 'Mencetak...' : 'Cetak Nota', style: const TextStyle(fontWeight: FontWeight.bold))))),
          ])),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, ColorScheme cs, {bool bold = false, Color? color, double size = 14}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        Text(value, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color ?? cs.onSurface)),
      ]));
  }
}
