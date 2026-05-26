import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';

class StokPage extends StatefulWidget {
  const StokPage({super.key});
  @override
  State<StokPage> createState() => _StokPageState();
}

class _StokPageState extends State<StokPage> {
  List<dynamic> inventory = [];
  String filter = 'all';
  String searchQuery = '';
  
  int? editId;
  final TextEditingController _stockCtrl = TextEditingController();
  final TextEditingController _minAlertCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final res = await Api.get('/inventory');
      if (mounted) setState(() => inventory = res as List);
    } catch (_) {}
  }

  List<dynamic> get filtered {
    var items = inventory;
    if (filter == 'low') {
      items = items.where((i) {
        final alert = (i['min_stock_alert'] as num?)?.toDouble() ?? 0;
        final qty = (i['stock_quantity'] as num?)?.toDouble() ?? 0;
        return alert > 0 && qty <= alert && qty > 0;
      }).toList();
    } else if (filter == 'empty') {
      items = items.where((i) => ((i['stock_quantity'] as num?)?.toDouble() ?? 0) <= 0).toList();
    }
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      items = items.where((i) => (i['name'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    return items;
  }

  Future<void> _openRestock(dynamic item) async {
    try {
      final fullProduct = await Api.get('/products/${item['product_id']}');
      if (mounted) {
        showDialog(
          context: context, 
          builder: (_) => RestockDialog(
            product: fullProduct,
            onSave: _loadData,
          )
        );
      }
    } catch (e) {
      if (mounted) showToast(context, 'Gagal mengambil data produk: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final items = filtered;

    final lowCount = inventory.where((i) {
      final alert = (i['min_stock_alert'] as num?)?.toDouble() ?? 0;
      final qty = (i['stock_quantity'] as num?)?.toDouble() ?? 0;
      return alert > 0 && qty <= alert && qty > 0;
    }).length;
    
    final emptyCount = inventory.where((i) => ((i['stock_quantity'] as num?)?.toDouble() ?? 0) <= 0).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Top actions
      Wrap(spacing: 8, runSpacing: 8, children: [
        _FilterChip(label: 'Semua (${inventory.length})', active: filter == 'all', onTap: () => setState(() => filter = 'all')),
        _FilterChip(label: '⚠️ Rendah ($lowCount)', active: filter == 'low', onTap: () => setState(() => filter = 'low')),
        _FilterChip(label: '🚫 Habis ($emptyCount)', active: filter == 'empty', onTap: () => setState(() => filter = 'empty')),
      ]),
      const SizedBox(height: 16),
      
      // Search
      SizedBox(width: 400, child: TextField(
        decoration: InputDecoration(
          hintText: 'Cari produk...', prefixIcon: const Icon(Icons.search, size: 20),
          filled: true, fillColor: cs.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: (v) => setState(() => searchQuery = v),
      )),
      const SizedBox(height: 16),

      // List
      Expanded(child: items.isEmpty
        ? Center(child: Text(filter == 'low' ? 'Semua stok aman 👍' : filter == 'empty' ? 'Tidak ada stok habis 👍' : 'Tidak ada data', style: TextStyle(color: cs.onSurfaceVariant)))
        : isMobile ? _buildMobileList(cs, items) : _buildDesktopTable(cs, items)),
    ]);
  }

  Widget _FilterChip({required String label, required bool active, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: active ? cs.primary : cs.surfaceContainer, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? cs.onPrimary : cs.onSurfaceVariant))));
  }

  Widget _buildMobileList(ColorScheme cs, List<dynamic> items) {
    return ListView.builder(itemCount: items.length, itemBuilder: (ctx, i) {
      final item = items[i];
      final alert = (item['min_stock_alert'] is num) ? (item['min_stock_alert'] as num).toDouble() : 0.0;
      final qty = (item['stock_quantity'] is num) ? (item['stock_quantity'] as num).toDouble() : 0.0;
      final isLow = alert > 0 && qty <= alert;
      final units = (item['units'] is List) ? item['units'] as List : [];
      final baseUnit = item['base_unit']?.toString();

      return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isLow ? cs.error.withValues(alpha: 0.3) : cs.outlineVariant)),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('${item['category_name'] ?? '-'}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatStock(qty, units, baseUnit), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isLow ? cs.error : cs.onSurface)),
              if (alert > 0) Text('min: ${formatStock(alert, units, baseUnit)}', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _openRestock(item),
              icon: const Icon(Icons.add_shopping_cart, size: 16),
              label: const Text('Restock', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
            )
          ]),
        ]));
    });
  }

  Widget _editField(String label, TextEditingController ctrl) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
      const SizedBox(height: 4),
      SizedBox(height: 36, child: TextField(controller: ctrl, keyboardType: TextInputType.number, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        decoration: InputDecoration(contentPadding: EdgeInsets.zero, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: cs.surfaceContainer))),
    ]);
  }

  Widget _buildDesktopTable(ColorScheme cs, List<dynamic> items) {
    return Container(decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: ListView(children: [
        DataTable(
          headingRowColor: WidgetStatePropertyAll(cs.surfaceContainer),
          dataRowMinHeight: 56, dataRowMaxHeight: 56,
          columns: const [
            DataColumn(label: Text('Produk', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Kategori')),
            DataColumn(label: Text('Stok')),
            DataColumn(label: Text('Satuan')),
            DataColumn(label: Text('Min. Alert')),
            DataColumn(label: Text('')),
          ],
          rows: items.map((item) {
            final alert = (item['min_stock_alert'] as num?)?.toDouble() ?? 0;
            final qty = (item['stock_quantity'] as num?)?.toDouble() ?? 0;
            final isLow = alert > 0 && qty <= alert;
            final units = item['units'] as List? ?? [];
            final baseUnit = item['base_unit'] as String?;

            return DataRow(
              color: isLow ? WidgetStatePropertyAll(cs.errorContainer.withValues(alpha: 0.2)) : null,
              cells: [
                DataCell(Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text(item['category_name'] ?? '-')),
                DataCell(Text(formatStock(qty, units, baseUnit), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isLow ? cs.error : cs.onSurface))),
                DataCell(Text(baseUnit ?? '-')),
                DataCell(Text(formatStock(alert, units, baseUnit), style: TextStyle(color: cs.onSurfaceVariant))),
                DataCell(Align(alignment: Alignment.centerRight, child: FilledButton.icon(
                  onPressed: () => _openRestock(item),
                  icon: const Icon(Icons.add_shopping_cart, size: 16),
                  label: const Text('Restock'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                ))),
              ]
            );
          }).toList(),
        )
      ])));
  }
}

class RestockDialog extends StatefulWidget {
  final dynamic product;
  final VoidCallback onSave;
  const RestockDialog({super.key, required this.product, required this.onSave});

  @override
  State<RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<RestockDialog> {
  final _qtyCtrl = TextEditingController();
  final _totalCostCtrl = TextEditingController();
  String? _selectedUnit;
  List<dynamic> _units = [];
  final Map<String, TextEditingController> _sellingPriceCtrls = {};
  bool _isSaving = false;

  static double _safeNum(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  @override
  void initState() {
    super.initState();
    _units = (widget.product['units'] is List) ? widget.product['units'] as List : [];
    
    final baseUnit = widget.product['base_unit'] ?? 'pcs';
    _selectedUnit = baseUnit;
    if (_units.isNotEmpty) {
      if (widget.product['purchase_unit'] != null && widget.product['purchase_unit'].toString().isNotEmpty) {
        _selectedUnit = widget.product['purchase_unit'];
      }
    }

    for (var u in _units) {
      final priceVal = _safeNum(u['price']);
      // Display Rupiah as integer — no decimals
      _sellingPriceCtrls[u['unit_name']?.toString() ?? 'pcs'] = TextEditingController(text: priceVal == priceVal.roundToDouble() ? '${priceVal.round()}' : priceVal.toString());
    }
  }

  void _save() async {
    double qtyIn = double.tryParse(_qtyCtrl.text) ?? 0;
    double totalCost = double.tryParse(_totalCostCtrl.text) ?? 0;

    if (qtyIn <= 0) {
      showToast(context, 'Jumlah masuk harus > 0');
      return;
    }

    setState(() => _isSaving = true);

    try {
      double multiplier = 1.0;
      Map<String, dynamic>? unitData;
      try { unitData = Map<String, dynamic>.from(_units.firstWhere((u) => u['unit_name']?.toString() == _selectedUnit)); } catch (_) {}
      if (unitData != null) {
        multiplier = _safeNum(unitData['qty_per_unit'], 1.0);
      }
      double addedBaseStock = qtyIn * multiplier;

      final updatedUnitPrices = _units.map((u) {
        final uName = u['unit_name']?.toString() ?? 'pcs';
        final ctrl = _sellingPriceCtrls[uName];
        double newPrice = ctrl != null ? (double.tryParse(ctrl.text) ?? 0) : _safeNum(u['price']);
        return {
          'unit_name': u['unit_name'],
          'qty_per_unit': u['qty_per_unit'],
          'price': newPrice,
        };
      }).toList();

      final postPayload = {
        'added_qty': addedBaseStock,
        'total_cost': totalCost,
        'purchase_unit': _selectedUnit,
        'updated_selling_prices': updatedUnitPrices,
      };

      final updatedProduct = await Api.post('/products/${widget.product['id']}/restock', body: postPayload);

      if (!mounted) return;
      
      final newAvco = _safeNum(updatedProduct['purchase_price']);
      showToast(context, 'Restock berhasil disimpan (AVCO: ${fmtPrice(newAvco)} / base)');
      widget.onSave();
      Navigator.pop(context);

    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showToast(context, 'Gagal restock: $e');
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _totalCostCtrl.dispose();
    for (var c in _sellingPriceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.product;
    final oldStock = _safeNum(p['stock_quantity']);
    final oldCost = _safeNum(p['purchase_price']);
    final baseUnit = p['base_unit'] ?? 'pcs';
    
    final List<String> unitOpts = [baseUnit];
    for (var u in _units) {
      if (!unitOpts.contains(u['unit_name'])) unitOpts.add(u['unit_name']);
    }
    if (!unitOpts.contains(_selectedUnit)) _selectedUnit = baseUnit;

    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Dialog(
      insetPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 8, vertical: 24) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Restock Produk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ]
              ),
              const Divider(),
              Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Sisa Stok', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      Text(formatStock(oldStock, _units, baseUnit), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Modal Lama', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      Text('${fmtPrice(oldCost)} / $baseUnit', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ]
                )
              ),
              const SizedBox(height: 20),
              const Text('Pembelian Baru', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  initialValue: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'Satuan Pembelian', isDense: true),
                  items: unitOpts.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) => setState(() => _selectedUnit = v),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(labelText: 'Jumlah Masuk', isDense: true),
                  keyboardType: TextInputType.number,
                )),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _totalCostCtrl,
                decoration: const InputDecoration(labelText: 'Total Harga Beli', prefixText: 'Rp ', isDense: true),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              const Text('Penyesuaian Harga Jual', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_units.isEmpty) 
                Text('Produk ini belum memiliki satuan jual.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
              else
                ..._units.map((u) {
                  final name = u['unit_name'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      controller: _sellingPriceCtrls[name],
                      decoration: InputDecoration(labelText: 'Update Harga Jual ($name)', prefixText: 'Rp ', isDense: true),
                      keyboardType: TextInputType.number,
                    ),
                  );
                }),
              
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.inventory),
                  label: const Text('Simpan Restock'),
                ),
              ])
            ]
          )
        )
      )
    );
  }
}
