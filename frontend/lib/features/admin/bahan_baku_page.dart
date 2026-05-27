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
  List<dynamic> kategoriBahanList = [];
  bool isLoading = true;
  String searchQuery = '';
  int? _selectedKategoriId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final results = await Future.wait([
        Api.get('/bahan-baku'),
        Api.get('/kategori-bahan'),
      ]);
      if (mounted) setState(() {
        materials = results[0] as List;
        kategoriBahanList = results[1] as List;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) { setState(() => isLoading = false); showAdminToast(context, 'Error: $e'); }
    }
  }

  List<dynamic> get filtered {
    return materials.where((m) {
      if (_selectedKategoriId != null && (m['kategori_bahan_id'] as num?)?.toInt() != _selectedKategoriId) return false;
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      return (m['name'] ?? '').toString().toLowerCase().contains(q) ||
             (m['unit'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  void _openForm([dynamic item]) {
    showDialog(context: context, builder: (_) => BahanBakuFormDialog(item: item, kategoriBahanList: kategoriBahanList, onSave: _loadData));
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

  // Generate a deterministic color for a category name
  Color _categoryColor(String? name) {
    if (name == null || name.isEmpty) return Colors.grey;
    final colors = [
      Colors.blue, Colors.teal, Colors.orange, Colors.purple,
      Colors.indigo, Colors.pink, Colors.cyan, Colors.amber,
      Colors.deepOrange, Colors.green, Colors.lime, Colors.brown,
    ];
    final hash = name.codeUnits.fold<int>(0, (prev, c) => prev + c);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
        const SizedBox(height: 8),
        // Category Filter Chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text('Semua'),
                  selected: _selectedKategoriId == null,
                  onSelected: (_) => setState(() => _selectedKategoriId = null),
                ),
              ),
              ...kategoriBahanList.map((k) {
                final kId = (k['id'] as num).toInt();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(k['name']?.toString() ?? ''),
                    selected: _selectedKategoriId == kId,
                    onSelected: (_) => setState(() => _selectedKategoriId = _selectedKategoriId == kId ? null : kId),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // List — unified card style for all screen sizes
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
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _buildCardList(cs, items),
                ),
              ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Bahan Baru'),
      ),
    );
  }

  Widget _buildCardList(ColorScheme cs, List<dynamic> items) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = items[i];
        final stock = (m['stock'] as num?)?.toDouble() ?? 0;
        final minAlert = (m['min_stock_alert'] as num?)?.toDouble() ?? 0;
        final isLow = minAlert > 0 && stock <= minAlert;
        final costPrice = (m['cost_price'] as num?)?.toDouble() ?? 0;
        final katName = m['kategori_name']?.toString() ?? 'Lainnya';
        final catColor = _categoryColor(katName);

        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceBright,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isLow ? cs.error.withValues(alpha: 0.4) : cs.outlineVariant),
          ),
          child: Row(children: [
            // Colored left strip (category indicator)
            Container(
              width: 6,
              height: 72,
              decoration: BoxDecoration(
                color: catColor,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: catColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(katName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: catColor)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(4)),
                    child: Text(m['unit'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSecondaryContainer)),
                  ),
                  Text('Stok: ${_formatStock(stock, m['unit'] ?? '')}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isLow ? cs.error : cs.onSurface)),
                ]),
                const SizedBox(height: 2),
                Text('Aset: ${fmtPrice(stock * costPrice)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            )),
            // Action buttons
            IconButton(icon: const Icon(Icons.add_box, size: 20, color: Colors.blue), onPressed: () => _showRestockDialog(m), tooltip: 'Restock'),
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openForm(m), tooltip: 'Edit'),
            IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _confirmDelete(m), tooltip: 'Hapus'),
            const SizedBox(width: 4),
          ]),
        );
      },
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
  final List<dynamic> kategoriBahanList;
  final VoidCallback onSave;
  const BahanBakuFormDialog({super.key, this.item, required this.kategoriBahanList, required this.onSave});
  @override
  State<BahanBakuFormDialog> createState() => _BahanBakuFormDialogState();
}

class _BahanBakuFormDialogState extends State<BahanBakuFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _stockCtrl, _costCtrl, _minAlertCtrl;
  String _selectedUnit = 'gram';
  int? _selectedKategoriId;
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

    // Kategori
    if (m != null) {
      _selectedKategoriId = (m['kategori_bahan_id'] as num?)?.toInt();
      if (_selectedKategoriId == 0) _selectedKategoriId = null;
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
      'kategori_bahan_id': _selectedKategoriId ?? 0,
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

              // Kategori
              DropdownButtonFormField<int>(
                value: _selectedKategoriId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategori Bahan', isDense: true, prefixIcon: Icon(Icons.category_outlined, size: 20)),
                items: widget.kategoriBahanList.map((k) => DropdownMenuItem<int>(value: (k['id'] as num).toInt(), child: Text(k['name']?.toString() ?? ''))).toList(),
                onChanged: (v) => setState(() => _selectedKategoriId = v),
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
