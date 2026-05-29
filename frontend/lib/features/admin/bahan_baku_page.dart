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
    final baseUnit = item['unit']?.toString() ?? '';

    // Build unit options based on base unit
    final List<String> unitOptions = _getRestockUnitOptions(baseUnit);
    String selectedUnit = unitOptions.first;

    showDialog(context: context, builder: (dialogContext) {
      return StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Text('Restock: ${item['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Stok saat ini: ${_formatStock((item['stock'] as num?)?.toDouble() ?? 0, baseUnit)}', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'Jumlah Restock', isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              )),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<String>(
                  value: selectedUnit,
                  decoration: const InputDecoration(labelText: 'Satuan', isDense: true),
                  items: unitOptions.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                  onChanged: (v) { if (v != null) setDialogState(() => selectedUnit = v); },
                ),
              ),
            ]),
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
              final inputQty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
              final addCost = double.tryParse(costCtrl.text.replaceAll(',', '.')) ?? 0;
              if (inputQty <= 0) return;

              // Convert to base unit
              final multiplier = _getUnitMultiplier(selectedUnit, baseUnit);
              final addQty = inputQty * multiplier;

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
    });
  }

  List<String> _getRestockUnitOptions(String baseUnit) {
    final lower = baseUnit.toLowerCase();
    if (lower == 'gram' || lower == 'gr' || lower == 'g') return ['gram', 'Kg'];
    if (lower == 'kg') return ['Kg', 'gram'];
    if (lower == 'ml') return ['ml', 'Liter'];
    if (lower == 'liter' || lower == 'l') return ['Liter', 'ml'];
    // Default: just show the base unit
    return [baseUnit];
  }

  double _getUnitMultiplier(String inputUnit, String baseUnit) {
    final from = inputUnit.toLowerCase();
    final to = baseUnit.toLowerCase();
    // Kg → gram
    if (from == 'kg' && (to == 'gram' || to == 'gr' || to == 'g')) return 1000;
    // gram → Kg
    if ((from == 'gram' || from == 'gr' || from == 'g') && to == 'kg') return 0.001;
    // Liter → ml
    if ((from == 'liter' || from == 'l') && to == 'ml') return 1000;
    // ml → Liter
    if (from == 'ml' && (to == 'liter' || to == 'l')) return 0.001;
    return 1.0; // Same unit or unknown
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCardList(ColorScheme cs, List<dynamic> items) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = items[i];
        final stock = (m['stock'] as num?)?.toDouble() ?? 0;
        final minAlert = (m['min_stock_alert'] as num?)?.toDouble() ?? 0;
        final isOut = stock == 0;
        final isLow = !isOut && minAlert > 0 && stock <= minAlert;
        final costPrice = (m['cost_price'] as num?)?.toDouble() ?? 0;
        final katName = m['kategori_name']?.toString() ?? 'Lainnya';

        // Stock-based left strip color
        final Color stripColor;
        if (isOut) {
          stripColor = Colors.red;
        } else if (isLow) {
          stripColor = Colors.amber.shade700;
        } else {
          stripColor = cs.primary.withValues(alpha: 0.3);
        }

        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceBright,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isOut ? cs.error.withValues(alpha: 0.4) : isLow ? Colors.amber.withValues(alpha: 0.4) : cs.outlineVariant),
          ),
          child: Row(children: [
            // Stock-based left strip
            Container(
              width: 6,
              height: 72,
              decoration: BoxDecoration(
                color: stripColor,
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
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
                    child: Text(katName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.primary)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(4)),
                    child: Text(m['unit'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSecondaryContainer)),
                  ),
                  Text('Stok: ${_formatStock(stock, m['unit'] ?? '')}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOut ? cs.error : isLow ? Colors.amber.shade800 : cs.onSurface)),
                  if (isOut)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                      child: const Text('Habis', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                    )
                  else if (isLow)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
                      child: const Text('Stok Rendah', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                ]),
                const SizedBox(height: 2),
                Text('Aset: ${fmtPrice(stock * costPrice)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            )),
            // Action buttons: Desktop = icon row, Mobile = three dots
            if (isMobile)
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
              )
            else ...[
              IconButton(icon: const Icon(Icons.add_box, size: 20, color: Colors.blue), onPressed: () => _showRestockDialog(m), tooltip: 'Restock'),
              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openForm(m), tooltip: 'Edit'),
              IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => _confirmDelete(m), tooltip: 'Hapus'),
              const SizedBox(width: 4),
            ],
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
    final lower = unit.toLowerCase();
    // Master unit Kg: show gram equivalent when < 1
    if (lower == 'kg') {
      if (stock < 1 && stock > 0) {
        return '${_fmtNum(stock)} $unit (${_fmtNum(stock * 1000)} gram)';
      }
      return '${_fmtNum(stock)} $unit';
    }
    // Base unit gram: show Kg equivalent when >= 1000
    if (lower == 'gram' || lower == 'gr' || lower == 'g') {
      if (stock >= 1000) {
        return '${_fmtNum(stock)} $unit (${_fmtNum(stock / 1000)} Kg)';
      }
      return '${_fmtNum(stock)} $unit';
    }
    // Master unit Liter: show ml equivalent when < 1
    if (lower == 'liter' || lower == 'l') {
      if (stock < 1 && stock > 0) {
        return '${_fmtNum(stock)} $unit (${_fmtNum(stock * 1000)} ml)';
      }
      return '${_fmtNum(stock)} $unit';
    }
    // Base unit ml: show Liter equivalent when >= 1000
    if (lower == 'ml') {
      if (stock >= 1000) {
        return '${_fmtNum(stock)} $unit (${_fmtNum(stock / 1000)} Liter)';
      }
      return '${_fmtNum(stock)} $unit';
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
    final minAlert = m != null ? (m['min_stock_alert'] as num?)?.toDouble() ?? 0 : 0.0;
    
    // Master Unit Architecture: show unit price directly (no total multiplication)
    _stockCtrl = TextEditingController(text: m != null ? _fmtInit(stock) : '');
    _costCtrl = TextEditingController(text: m != null ? _fmtInit(costPrice) : '');
    _minAlertCtrl = TextEditingController(text: m != null ? _fmtInit(minAlert) : '');

    if (m != null && _units.contains(dbUnit)) {
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
    final unitPriceStr = _costCtrl.text.replaceAll(',', '.');
    
    final qtyBeli = double.tryParse(qtyBeliStr) ?? 0;
    final unitPrice = double.tryParse(unitPriceStr) ?? 0;
    
    // Master Unit Architecture: save unit price directly (no division)
    final double minAlertInput = double.tryParse(_minAlertCtrl.text.replaceAll(',', '.')) ?? 0;

    final data = {
      'name': toTitleCase(_nameCtrl.text.trim()),
      'unit': _selectedUnit,  // Master unit locked as-is
      'stock': qtyBeli,
      'cost_price': unitPrice,
      'min_stock_alert': minAlertInput,
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

              // Stok & Harga per Satuan
              isMobile ? Column(children: [
                TextFormField(
                  controller: _stockCtrl,
                  decoration: InputDecoration(labelText: isEdit ? 'Stok Saat Ini' : 'Jumlah Beli', isDense: true, prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20), suffixText: _selectedUnit),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _costCtrl,
                  decoration: InputDecoration(labelText: 'Harga Modal per $_selectedUnit', isDense: true, prefixText: 'Rp ', prefixIcon: const Icon(Icons.payments_outlined, size: 20)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ]) : Row(children: [
                Expanded(child: TextFormField(
                  controller: _stockCtrl,
                  decoration: InputDecoration(labelText: isEdit ? 'Stok Saat Ini' : 'Jumlah Beli', isDense: true, suffixText: _selectedUnit),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(
                  controller: _costCtrl,
                  decoration: InputDecoration(labelText: 'Harga Modal per $_selectedUnit', isDense: true, prefixText: 'Rp '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                )),
              ]),
              // Nilai Aset Tersisa (read-only, computed from current stock × unit price)
              if (isEdit) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Builder(builder: (_) {
                  final curStock = double.tryParse(_stockCtrl.text.replaceAll(',', '.')) ?? 0;
                  final curPrice = double.tryParse(_costCtrl.text.replaceAll(',', '.')) ?? 0;
                  return Text('💰 Nilai Aset Tersisa: ${fmtPrice(curStock * curPrice)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary));
                }),
              ),
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
