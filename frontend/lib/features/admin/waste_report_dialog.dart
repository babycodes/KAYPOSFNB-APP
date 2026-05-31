import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../../core/local_db.dart';

/// ─────────────────────────────────────────────────────────────
/// Lapor Bahan Terbuang (Waste Report Dialog)
/// ─────────────────────────────────────────────────────────────
/// Dual-tab dialog for reporting waste:
///   Tab A: "Produk Jadi" — report a finished product waste,
///          auto-deducts all BOM ingredients via resep.
///   Tab B: "Bahan Mentah" — report a raw material waste,
///          deducts directly from bahan_baku.
///
/// Both tabs insert WASTE rows into inventory_ledger and deduct
/// from bahan_baku.stock. Does NOT alter any existing tables.
/// ─────────────────────────────────────────────────────────────
class WasteReportDialog extends StatefulWidget {
  final VoidCallback? onSaved;
  const WasteReportDialog({super.key, this.onSaved});

  /// Show the dialog from anywhere in the app.
  static Future<void> show(BuildContext context, {VoidCallback? onSaved}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WasteReportDialog(onSaved: onSaved),
    );
  }

  @override
  State<WasteReportDialog> createState() => _WasteReportDialogState();
}

class _WasteReportDialogState extends State<WasteReportDialog> {
  // ── Shared State ──
  List<dynamic> _products = [];
  List<dynamic> _bahanBaku = [];
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Tab A: Produk Jadi ──
  int? _selectedProductId;
  final _prodQtyCtrl = TextEditingController(text: '1');
  String _prodReason = 'Tumpah';

  // ── Tab B: Bahan Mentah ──
  int? _selectedBahanId;
  final _bahanQtyCtrl = TextEditingController();
  String _bahanReason = 'Basi';
  String _selectedBahanInputUnit = '';

  static const _prodReasons = ['Tumpah', 'Salah Bikin', 'Basi', 'Lainnya'];
  static const _bahanReasons = ['Basi', 'Jatuh', 'Rusak', 'Lainnya'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _prodQtyCtrl.dispose();
    _bahanQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        Api.get('/products'),
        Api.get('/bahan-baku'),
      ]);
      if (mounted) {
        setState(() {
          _products = (results[0] as List).where((p) => (p['is_paket'] as num?)?.toInt() != 1).toList();
          _bahanBaku = results[1] as List;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAdminToast(context, 'Error: $e');
      }
    }
  }

  // ──────────────────────────────────────────────────
  // TAB A LOGIC: Produk Jadi (Finished Product Waste)
  // ──────────────────────────────────────────────────
  Future<void> _submitProductWaste() async {
    if (_selectedProductId == null) return;
    final qty = double.tryParse(_prodQtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (qty <= 0) return;

    setState(() => _isSaving = true);

    try {
      final db = await LocalDb.instance;
      final productName = _products
          .firstWhere((p) => p['id'] == _selectedProductId,
              orElse: () => {'name': 'Unknown'})['name']
          ?.toString() ?? 'Unknown';

      // Query resep (BOM) for this product
      final resepRows = await db.query('resep',
          where: 'product_id = ?', whereArgs: [_selectedProductId]);

      if (resepRows.isEmpty) {
        if (mounted) showAdminToast(context, '⚠️ Produk ini belum punya resep (BOM).');
        setState(() => _isSaving = false);
        return;
      }

      await db.transaction((txn) async {
        for (final r in resepRows) {
          final bbId = (r['bahan_baku_id'] as num).toInt();
          final qtyNeeded = (r['qty_needed'] as num).toDouble();

          // Get bahan_baku master unit
          final bbRow = await txn.query('bahan_baku',
              columns: ['unit', 'cost_price', 'stock'],
              where: 'id = ?',
              whereArgs: [bbId]);
          if (bbRow.isEmpty) continue;

          final bbUnit = bbRow.first['unit']?.toString().toLowerCase() ?? '';
          final costPrice = (bbRow.first['cost_price'] as num?)?.toDouble() ?? 0;

          // Convert recipe qty → master unit (same logic as Cashier)
          final rawDeduction = qtyNeeded * qty;
          final deduction = (bbUnit == 'kg' || bbUnit == 'liter' || bbUnit == 'l')
              ? rawDeduction / 1000
              : rawDeduction;

          // Financial loss = deducted qty × cost per master unit
          final financialLoss = deduction * costPrice;

          // Deduct from bahan_baku
          await txn.rawUpdate(
              'UPDATE bahan_baku SET stock = MAX(0, stock - ?) WHERE id = ?',
              [deduction, bbId]);

          // Insert WASTE ledger row
          await txn.insert('inventory_ledger', {
            'bahan_baku_id': bbId,
            'transaction_type': 'WASTE',
            'qty_change': -deduction,
            'financial_value': financialLoss,
            'notes': 'Produk Gagal: $productName - $_prodReason',
          });
        }
      });

      if (mounted) {
        showAdminToast(context, '✅ Waste dicatat untuk $productName (×${qty.round()})');
        widget.onSaved?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showAdminToast(context, '❌ Error: $e');
      }
    }
  }

  // ──────────────────────────────────────────────────
  // TAB B LOGIC: Bahan Mentah (Raw Material Waste)
  // ──────────────────────────────────────────────────
  Future<void> _submitRawWaste() async {
    if (_selectedBahanId == null) return;
    final inputQty = double.tryParse(_bahanQtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (inputQty <= 0) return;

    setState(() => _isSaving = true);

    try {
      final db = await LocalDb.instance;
      final bahan = _bahanBaku.firstWhere(
          (b) => b['id'] == _selectedBahanId,
          orElse: () => null);
      if (bahan == null) throw Exception('Bahan tidak ditemukan');

      final masterUnit = bahan['unit']?.toString() ?? '';
      final costPrice = (bahan['cost_price'] as num?)?.toDouble() ?? 0;
      final bahanName = bahan['name']?.toString() ?? '';

      // Convert input unit → master unit
      final multiplier = _getUnitMultiplier(_selectedBahanInputUnit, masterUnit);
      final deductionInMasterUnit = inputQty * multiplier;

      // Financial loss
      final financialLoss = deductionInMasterUnit * costPrice;

      await db.transaction((txn) async {
        // Deduct from bahan_baku
        await txn.rawUpdate(
            'UPDATE bahan_baku SET stock = MAX(0, stock - ?) WHERE id = ?',
            [deductionInMasterUnit, _selectedBahanId]);

        // Insert WASTE ledger row
        await txn.insert('inventory_ledger', {
          'bahan_baku_id': _selectedBahanId,
          'transaction_type': 'WASTE',
          'qty_change': -deductionInMasterUnit,
          'financial_value': financialLoss,
          'notes': 'Bahan Rusak: $bahanName - $_bahanReason',
        });
      });

      if (mounted) {
        showAdminToast(context, '✅ Waste dicatat: $bahanName ($inputQty $_selectedBahanInputUnit)');
        widget.onSaved?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showAdminToast(context, '❌ Error: $e');
      }
    }
  }

  // ── Unit conversion helpers (same logic as bahan_baku_page) ──

  List<String> _getUnitOptions(String baseUnit) {
    final lower = baseUnit.toLowerCase();
    if (lower == 'gram' || lower == 'gr' || lower == 'g') return ['gram', 'Kg'];
    if (lower == 'kg') return ['Kg', 'gram'];
    if (lower == 'ml') return ['ml', 'Liter'];
    if (lower == 'liter' || lower == 'l') return ['Liter', 'ml'];
    return [baseUnit];
  }

  double _getUnitMultiplier(String inputUnit, String baseUnit) {
    final from = inputUnit.toLowerCase();
    final to = baseUnit.toLowerCase();
    if (from == 'kg' && (to == 'gram' || to == 'gr' || to == 'g')) return 1000;
    if ((from == 'gram' || from == 'gr' || from == 'g') && to == 'kg') return 0.001;
    if ((from == 'liter' || from == 'l') && to == 'ml') return 1000;
    if (from == 'ml' && (to == 'liter' || to == 'l')) return 0.001;
    return 1.0;
  }

  // ──────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      insetPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        height: 520,
        padding: const EdgeInsets.only(top: 20, left: 24, right: 24, bottom: 16),
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.delete_sweep, color: Colors.orange.shade700, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Lapor Bahan Terbuang',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Catat waste/produk gagal',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Tab Bar ──
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  labelColor: cs.onPrimary,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  indicator: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  padding: const EdgeInsets.all(3),
                  tabs: const [
                    Tab(text: '🍽️  Produk Jadi'),
                    Tab(text: '🥩  Bahan Mentah'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Tab Content ──
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildProductTab(cs),
                          _buildRawMaterialTab(cs),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────
  // TAB A UI: Produk Jadi
  // ──────────────────────────────────────────────────
  Widget _buildProductTab(ColorScheme cs) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pilih produk jadi yang gagal. Sistem akan otomatis mengurangi semua bahan baku sesuai resep (BOM).',
                    style: TextStyle(fontSize: 11, color: Colors.blue.shade900, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Product selector
          DropdownButtonFormField<int>(
            value: _selectedProductId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Pilih Produk',
              isDense: true,
              prefixIcon: const Icon(Icons.restaurant_menu, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _products.map((p) {
              return DropdownMenuItem<int>(
                value: (p['id'] as num).toInt(),
                child: Text(p['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedProductId = v),
          ),

          const SizedBox(height: 14),

          // Qty input
          TextField(
            controller: _prodQtyCtrl,
            decoration: InputDecoration(
              labelText: 'Jumlah (porsi)',
              isDense: true,
              prefixIcon: const Icon(Icons.pin, size: 20),
              suffixText: 'pcs',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
          ),

          const SizedBox(height: 14),

          // Reason
          DropdownButtonFormField<String>(
            value: _prodReason,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Alasan',
              isDense: true,
              prefixIcon: const Icon(Icons.report_problem_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _prodReasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _prodReason = v);
            },
          ),

          const SizedBox(height: 20),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSaving || _selectedProductId == null
                  ? null
                  : _submitProductWaste,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_sweep),
              label: const Text('Catat Waste Produk',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────
  // TAB B UI: Bahan Mentah
  // ──────────────────────────────────────────────────
  Widget _buildRawMaterialTab(ColorScheme cs) {
    // Resolve selected bahan info
    final selectedBahan = _selectedBahanId != null
        ? _bahanBaku.cast<Map<String, dynamic>?>().firstWhere(
            (b) => b != null && b['id'] == _selectedBahanId,
            orElse: () => null)
        : null;
    final baseUnit = selectedBahan?['unit']?.toString() ?? '';
    final stock = (selectedBahan?['stock'] as num?)?.toDouble() ?? 0;
    final costPrice = (selectedBahan?['cost_price'] as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pilih bahan baku mentah yang terbuang. Stok akan dikurangi langsung dan kerugian akan dihitung otomatis.',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade900, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Bahan selector
          DropdownButtonFormField<int>(
            value: _selectedBahanId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Pilih Bahan Baku',
              isDense: true,
              prefixIcon: const Icon(Icons.science_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _bahanBaku.map((b) {
              final name = b['name']?.toString() ?? '';
              final unit = b['unit']?.toString() ?? '';
              return DropdownMenuItem<int>(
                value: (b['id'] as num).toInt(),
                child: Text('$name ($unit)', overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) {
                final bahan = _bahanBaku.firstWhere((b) => b['id'] == v);
                final unit = bahan['unit']?.toString() ?? '';
                final options = _getUnitOptions(unit);
                setState(() {
                  _selectedBahanId = v;
                  _selectedBahanInputUnit = options.first;
                });
              }
            },
          ),

          // Current stock info chip
          if (selectedBahan != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Stok saat ini: ${_fmtNum(stock)} $baseUnit • HPP: ${fmtPrice(costPrice)}/$baseUnit',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Qty + unit input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _bahanQtyCtrl,
                  decoration: InputDecoration(
                    labelText: 'Jumlah Terbuang',
                    isDense: true,
                    prefixIcon: const Icon(Icons.pin, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: DropdownButtonFormField<String>(
                  value: _selectedBahanInputUnit.isEmpty ? null : _selectedBahanInputUnit,
                  decoration: InputDecoration(
                    labelText: 'Satuan',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: (baseUnit.isNotEmpty ? _getUnitOptions(baseUnit) : <String>[])
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedBahanInputUnit = v);
                  },
                ),
              ),
            ],
          ),

          // Live loss estimate
          if (selectedBahan != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ListenableBuilder(
                listenable: _bahanQtyCtrl,
                builder: (_, __) {
                  final inputQty = double.tryParse(_bahanQtyCtrl.text.replaceAll(',', '.')) ?? 0;
                  final multiplier = _getUnitMultiplier(_selectedBahanInputUnit, baseUnit);
                  final wasteInMaster = inputQty * multiplier;
                  final loss = wasteInMaster * costPrice;
                  if (inputQty <= 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.trending_down, size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Estimasi kerugian: ${fmtPrice(loss)}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 14),

          // Reason
          DropdownButtonFormField<String>(
            value: _bahanReason,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Alasan',
              isDense: true,
              prefixIcon: const Icon(Icons.report_problem_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _bahanReasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _bahanReason = v);
            },
          ),

          const SizedBox(height: 20),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSaving || _selectedBahanId == null
                  ? null
                  : _submitRawWaste,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_sweep),
              label: const Text('Catat Waste Bahan',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(2);
  }
}
