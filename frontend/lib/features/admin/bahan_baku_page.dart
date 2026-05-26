import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../kasir/dialogs/confirm_dialog.dart';

class BahanBakuPage extends StatefulWidget {
  const BahanBakuPage({super.key});
  @override
  State<BahanBakuPage> createState() => _BahanBakuPageState();
}

class _BahanBakuPageState extends State<BahanBakuPage> {
  List<dynamic> materials = [];
  bool isLoading = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final res = await Api.get('/bahan-baku');
      if (mounted) setState(() { materials = res as List; isLoading = false; });
    } catch (e) {
      if (mounted) { setState(() => isLoading = false); showAdminToast(context, 'Error: $e'); }
    }
  }

  List<dynamic> get filtered {
    if (searchQuery.isEmpty) return materials;
    final q = searchQuery.toLowerCase();
    return materials.where((m) =>
      (m['name'] ?? '').toString().toLowerCase().contains(q) ||
      (m['unit'] ?? '').toString().toLowerCase().contains(q)
    ).toList();
  }

  void _openForm([dynamic item]) {
    showDialog(context: context, builder: (_) => BahanBakuFormDialog(item: item, onSave: _loadData));
  }

  void _confirmDelete(dynamic item) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => KayConfirmDialog(
      title: 'Hapus Bahan Baku',
      message: 'Yakin ingin menghapus "${item['name']}"? Semua resep yang menggunakan bahan ini juga akan terhapus.',
      confirmText: 'Ya, Hapus',
    ));
    if (confirmed == true && mounted) {
      try {
        await Api.delete('/bahan-baku/${item['id']}');
        _loadData();
      } catch (e) {
        if (mounted) showAdminToast(context, 'Error: $e');
      }
    }
  }

  void _showRestockDialog(dynamic item) {
    final qtyCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final unit = item['unit']?.toString() ?? '';

    showDialog(context: context, builder: (dialogContext) {
      return AlertDialog(
        title: Text('Restock: ${item['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Stok saat ini: ${(item['stock'] as num?)?.toDouble() ?? 0} $unit', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          TextField(
            controller: qtyCtrl,
            decoration: InputDecoration(labelText: 'Jumlah Tambah Stok', suffixText: unit, isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: costCtrl,
            decoration: const InputDecoration(labelText: 'Total Harga Beli Restock', prefixText: 'Rp ', isDense: true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(onPressed: () async {
            final addQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
            final addCost = double.tryParse(costCtrl.text.replaceAll(',', '.')) ?? 0;
            if (addQty <= 0) return;

            final currentStock = (item['stock'] as num?)?.toDouble() ?? 0;
            final currentCostPrice = (item['cost_price'] as num?)?.toDouble() ?? 0;
            final newStock = currentStock + addQty;
            // AVCO: weighted average cost
            final totalOldValue = currentStock * currentCostPrice;
            final newCostPrice = newStock > 0 ? (totalOldValue + addCost) / newStock : currentCostPrice;

            try {
              await Api.put('/bahan-baku/${item['id']}', body: {
                'stock': newStock,
                'cost_price': newCostPrice,
              });
              if (mounted) Navigator.pop(dialogContext);
              _loadData();
            } catch (e) {
              if (mounted) showAdminToast(context, 'Error: $e');
            }
          }, child: const Text('Tambah Stok')),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final items = filtered;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Icon(Icons.scale, color: cs.primary, size: 28),
            const SizedBox(width: 12),
            Text('${materials.length} bahan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
            const SizedBox(width: 16),
            Expanded(child: TextField(
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Cari bahan baku...', prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true, filled: true, fillColor: cs.surfaceBright,
              ),
            )),
          ]),
        ),
        const SizedBox(height: 16),
        // List
        Expanded(child: isLoading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.science_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(searchQuery.isEmpty ? 'Belum ada bahan baku' : 'Bahan baku tidak ditemukan', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                if (searchQuery.isEmpty) FilledButton.icon(
                  onPressed: _openForm,
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah Bahan Baku Pertama'),
                ),
              ]))
            : isMobile ? _buildMobileList(cs, items) : _buildDesktopTable(cs, items),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Bahan Baru'),
      ),
    );
  }

  Widget _buildMobileList(ColorScheme cs, List<dynamic> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = items[i];
        final stock = (m['stock'] as num?)?.toDouble() ?? 0;
        final minAlert = (m['min_stock_alert'] as num?)?.toDouble() ?? 0;
        final isLow = minAlert > 0 && stock <= minAlert;

        final costPrice = (m['cost_price'] as num?)?.toDouble() ?? 0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceBright,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isLow ? cs.error.withValues(alpha: 0.4) : cs.outlineVariant),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.science, color: cs.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(4)),
                  child: Text(m['unit'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSecondaryContainer)),
                ),
                const SizedBox(width: 8),
                Text('Stok: ', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                Text(_formatStock(stock, m['unit'] ?? ''), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isLow ? cs.error : cs.onSurface)),
              ]),
              const SizedBox(height: 2),
              Text('Total Aset / Modal: ${fmtPrice(stock * costPrice)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ])),
            PopupMenuButton(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'restock', child: Row(children: [Icon(Icons.add_box, size: 18, color: Colors.blue), SizedBox(width: 8), Text('Restock', style: TextStyle(color: Colors.blue))])),
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
              ],
              onSelected: (val) {
                if (val == 'restock') _showRestockDialog(m);
                if (val == 'edit') _openForm(m);
                if (val == 'delete') _confirmDelete(m);
              },
            ),
          ]),
        );
      },
    );
  }

  Widget _buildDesktopTable(ColorScheme cs, List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView(children: [
          DataTable(
            headingRowColor: WidgetStatePropertyAll(cs.surfaceContainer),
            dataRowMinHeight: 56, dataRowMaxHeight: 56,
            columns: const [
              DataColumn(label: Text('Nama Bahan', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('Satuan')),
              DataColumn(label: Text('Stok'), numeric: true),
              DataColumn(label: Text('Total Aset / Modal'), numeric: true),
              DataColumn(label: Text('Min. Alert'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: items.map((m) {
              final stock = (m['stock'] as num?)?.toDouble() ?? 0;
              final minAlert = (m['min_stock_alert'] as num?)?.toDouble() ?? 0;
              final isLow = minAlert > 0 && stock <= minAlert;
              final costPrice = (m['cost_price'] as num?)?.toDouble() ?? 0;

              return DataRow(
                color: isLow ? WidgetStatePropertyAll(cs.errorContainer.withValues(alpha: 0.2)) : null,
                cells: [
                  DataCell(Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.science, size: 16, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 10),
                    Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ])),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(6)),
                    child: Text(m['unit'] ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSecondaryContainer)),
                  )),
                  DataCell(Text(_formatStock(stock, m['unit'] ?? ''), style: TextStyle(fontWeight: FontWeight.w900, color: isLow ? cs.error : cs.onSurface))),
                  DataCell(Text(fmtPrice(stock * costPrice))),
                  DataCell(Text(_fmtNum(minAlert), style: TextStyle(color: cs.onSurfaceVariant))),
                  DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.add_box, size: 18, color: Colors.blue), onPressed: () => _showRestockDialog(m), tooltip: 'Restock'),
                    IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openForm(m), tooltip: 'Edit'),
                    IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _confirmDelete(m), tooltip: 'Hapus'),
                  ])),
                ],
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(2);
  }

  String _formatStock(double stock, String unit) {
    if (unit == 'gram' && stock >= 1000) {
      return '${_fmtNum(stock)} $unit (${_fmtNum(stock / 1000)} Kg)';
    } else if (unit == 'ml' && stock >= 1000) {
      return '${_fmtNum(stock)} $unit (${_fmtNum(stock / 1000)} Liter)';
    }
    return '${_fmtNum(stock)} $unit';
  }
}

// ──────────────────────────────────────────────────
// Bahan Baku Create/Edit Form Dialog
// ──────────────────────────────────────────────────
class BahanBakuFormDialog extends StatefulWidget {
  final dynamic item;
  final VoidCallback onSave;
  const BahanBakuFormDialog({super.key, this.item, required this.onSave});
  @override
  State<BahanBakuFormDialog> createState() => _BahanBakuFormDialogState();
}

class _BahanBakuFormDialogState extends State<BahanBakuFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _stockCtrl, _costCtrl, _minAlertCtrl;
  String _selectedUnit = 'gram';
  bool _isSaving = false;

  static const _units = ['Kg', 'gram', 'Liter', 'ml', 'pcs'];

  @override
  void initState() {
    super.initState();
    final m = widget.item;
    _nameCtrl = TextEditingController(text: (m?['name'] ?? '').toString());
    
    final dbUnit = m != null ? (m['unit'] ?? '').toString() : '';
    final stock = m != null ? (m['stock'] as num?)?.toDouble() ?? 0 : 0.0;
    final costPrice = m != null ? (m['cost_price'] as num?)?.toDouble() ?? 0 : 0.0;
    
    // Reverse conversion: show user-friendly units
    double displayQty = stock;
    double displayTotalCost = stock * costPrice;
    String displayUnit = dbUnit;
    
    if (m != null) {
      if (dbUnit == 'gram' && stock >= 1000) {
        displayUnit = 'Kg';
        displayQty = stock / 1000;
      } else if (dbUnit == 'ml' && stock >= 1000) {
        displayUnit = 'Liter';
        displayQty = stock / 1000;
      }
    }
    
    _stockCtrl = TextEditingController(text: m != null ? _fmtInit(displayQty) : '');
    _costCtrl = TextEditingController(text: m != null ? _fmtInit(displayTotalCost) : '');
    _minAlertCtrl = TextEditingController(text: m != null ? _fmtInit((m['min_stock_alert'] as num?)?.toDouble() ?? 0) : '');

    if (m != null && _units.contains(displayUnit)) {
      _selectedUnit = displayUnit;
    } else if (m != null && _units.contains(dbUnit)) {
      _selectedUnit = dbUnit;
    } else if (m == null) {
      _selectedUnit = 'Kg';
    }
  }

  String _fmtInit(double v) {
    if (v == 0) return '';
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final qtyBeliStr = _stockCtrl.text.replaceAll(',', '.');
    final totalHargaStr = _costCtrl.text.replaceAll(',', '.');
    
    final qtyBeli = double.tryParse(qtyBeliStr) ?? 0;
    final totalHarga = double.tryParse(totalHargaStr) ?? 0;
    
    String baseUnit = _selectedUnit;
    double totalBaseQty = qtyBeli;
    
    if (_selectedUnit == 'Kg') {
      baseUnit = 'gram';
      totalBaseQty = qtyBeli * 1000;
    } else if (_selectedUnit == 'Liter') {
      baseUnit = 'ml';
      totalBaseQty = qtyBeli * 1000;
    }
    
    final pricePerBaseUnit = totalBaseQty > 0 ? totalHarga / totalBaseQty : 0.0;

    final data = {
      'name': toTitleCase(_nameCtrl.text.trim()),
      'unit': baseUnit,
      'stock': totalBaseQty,
      'cost_price': pricePerBaseUnit,
      'min_stock_alert': double.tryParse(_minAlertCtrl.text.replaceAll(',', '.')) ?? 0,
    };

    try {
      if (widget.item != null) {
        await Api.put('/bahan-baku/${widget.item['id']}', body: data);
      } else {
        await Api.post('/bahan-baku', body: data);
      }
      if (mounted) {
        widget.onSave();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showAdminToast(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final isEdit = widget.item != null;

    return Dialog(
      insetPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 8, vertical: 24) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.science, color: cs.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(isEdit ? 'Edit Bahan Baku' : 'Tambah Bahan Baku', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 20),

              // Nama Bahan
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama Bahan *', isDense: true, prefixIcon: Icon(Icons.label_outline, size: 20)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 16),

              // Satuan
              DropdownButtonFormField<String>(
                value: _selectedUnit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Satuan *', isDense: true, prefixIcon: Icon(Icons.straighten, size: 20)),
                items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                onChanged: (v) => setState(() => _selectedUnit = v ?? 'gram'),
                validator: (v) => v == null ? 'Wajib dipilih' : null,
              ),
              const SizedBox(height: 16),

              // Stok Awal & Harga Beli
              isMobile ? Column(children: [
                TextFormField(
                  controller: _stockCtrl,
                  decoration: InputDecoration(labelText: 'Jumlah Beli', isDense: true, prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20), suffixText: _selectedUnit),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _costCtrl,
                  decoration: const InputDecoration(labelText: 'Total Harga Beli', isDense: true, prefixText: 'Rp ', prefixIcon: Icon(Icons.payments_outlined, size: 20)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ]) : Row(children: [
                Expanded(child: TextFormField(
                  controller: _stockCtrl,
                  decoration: InputDecoration(labelText: 'Jumlah Beli', isDense: true, suffixText: _selectedUnit),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(
                  controller: _costCtrl,
                  decoration: const InputDecoration(labelText: 'Total Harga Beli', isDense: true, prefixText: 'Rp '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                )),
              ]),
              const SizedBox(height: 16),

              // Min Stock Alert
              TextFormField(
                controller: _minAlertCtrl,
                decoration: InputDecoration(labelText: 'Batas Peringatan Stok Minimum', isDense: true, suffixText: _selectedUnit, prefixIcon: const Icon(Icons.warning_amber, size: 20)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 24),

              // Actions
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: Text(isEdit ? 'Simpan Perubahan' : 'Tambah Bahan'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
