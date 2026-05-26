import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../kasir/dialogs/confirm_dialog.dart';

class ProdukPage extends StatefulWidget {
  const ProdukPage({super.key});
  @override
  State<ProdukPage> createState() => _ProdukPageState();
}

class _ProdukPageState extends State<ProdukPage> {
  List<dynamic> products = [];
  List<dynamic> categories = [];
  bool isLoading = true;
  String activeTab = 'active'; // 'active' or 'inactive'
  String searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final futures = await Future.wait([
        Api.get('/products/all'),
        Api.get('/categories')
      ]);
      if (mounted) {
        setState(() {
        products = futures[0] as List;
        categories = futures[1] as List;
        isLoading = false;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        showAdminToast(context, 'Error: $e');
      }
    }
  }

  List<dynamic> get filteredProducts {
    return products.where((p) {
      final isItemActive = p['is_active'] == 1;
      final matchTab = activeTab == 'active' ? isItemActive : !isItemActive;
      if (!matchTab) return false;
      
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase();
      final name = (p['name'] ?? '').toString().toLowerCase();
      final barcode = (p['barcode'] ?? '').toString().toLowerCase();
      final cat = (p['category_name'] ?? '').toString().toLowerCase();
      return name.contains(q) || barcode.contains(q) || cat.contains(q);
    }).toList();
  }

  void _openForm([dynamic product]) {
    if (categories.isEmpty) {
      showAdminToast(context, 'Buat kategori terlebih dahulu!');
      return;
    }
    showDialog(context: context, builder: (_) => ProdukFormDialog(
      product: product,
      categories: categories,
      onSave: _loadData,
    ));
  }

  Future<void> _toggleActive(dynamic p) async {
    try {
      await Api.put('/products/${p['id']}', body: {'is_active': p['is_active'] == 1 ? 0 : 1});
      _loadData();
    } catch (e) {
      if (mounted) showAdminToast(context, 'Error: $e');
    }
  }

  Future<void> _downloadTemplate() async {
    final url = Uri.parse('${Api.getApiBase()}/products/template/excel');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) showAdminToast(context, 'Tidak dapat membuka link template');
    }
  }

  Future<void> _importExcel() async {
    if (mounted) showAdminToast(context, 'Fitur Import Excel dinonaktifkan di versi OFFLINE.');
  }

  void _confirmDelete(dynamic p) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => KayConfirmDialog(
      title: 'Hapus Produk',
      message: 'Yakin ingin menghapus produk "${p['name']}" beserta semua data stok dan harga satuannya?',
      confirmText: 'Ya, Hapus',
    ));
    if (confirmed == true && mounted) {
      try {
        await Api.delete('/products/${p['id']}');
        _loadData();
      } catch (e) {
        if (mounted) showAdminToast(context, 'Error: $e');
      }
    }
  }

  void _openRecipe(dynamic product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => RecipeModal(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final items = filteredProducts;

    final activeCount = products.where((p) => p['is_active'] == 1).length;
    final inactiveCount = products.where((p) => p['is_active'] != 1).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            // Tabs
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _tab('active', 'Aktif ($activeCount)', cs),
                _tab('inactive', 'Non-aktif ($inactiveCount)', cs),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(child: TextField(
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Cari nama, barcode, kategori...', prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true, filled: true, fillColor: cs.surfaceBright,
              ),
            )),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Import Excel',
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'download', child: Row(children: [Icon(Icons.download, size: 18), SizedBox(width: 8), Text('Download Template')])),
                const PopupMenuItem(value: 'import', child: Row(children: [Icon(Icons.upload_file, size: 18), SizedBox(width: 8), Text('Import Data (Excel)')])),
              ],
              onSelected: (val) {
                if (val == 'download') _downloadTemplate();
                if (val == 'import') _importExcel();
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // List
        Expanded(child: isLoading 
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text('Tidak ada produk', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
              ]))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final p = items[i];
                  return Card(
                    elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                    color: p['is_active'] == 1 ? cs.surfaceContainer : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
                    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(width: 48, height: 48, decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                          child: Center(child: Text(p['category_icon'] ?? '📦', style: const TextStyle(fontSize: 24)))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(p['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: p['is_active'] == 1 ? cs.onSurface : cs.onSurfaceVariant))),
                            if (p['is_active'] != 1) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(4)), child: Text('NON-AKTIF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onErrorContainer)))],
                          ]),
                          Row(children: [
                            Text('${p['category_name']} ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                            if (p['barcode'] != null && p['barcode'].toString().trim().isNotEmpty)
                              Text('· ${p['barcode']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))
                            else
                              Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)), child: Text('No Barcode', style: TextStyle(fontSize: 9, color: cs.error))),
                          ]),
                        ])),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(fmtPrice((p['price'] as num?)?.toDouble() ?? 0), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: p['is_active'] == 1 ? cs.primary : cs.onSurfaceVariant)),
                            Text('HPP: ${fmtPrice((p['total_hpp'] as num?)?.toDouble() ?? 0)}', style: TextStyle(fontSize: 12, color: cs.error)),
                          ],
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => _openRecipe(p),
                          icon: const Icon(Icons.receipt_long, size: 18),
                          label: const Text("Atur Resep"),
                        ),
                        PopupMenuButton(
                          icon: const Icon(Icons.more_vert),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'edit', child: const Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                            PopupMenuItem(value: 'toggle', child: Row(children: [Icon(p['is_active'] == 1 ? Icons.visibility_off : Icons.visibility, size: 18), SizedBox(width: 8), Text(p['is_active'] == 1 ? 'Non-aktifkan' : 'Aktifkan')])),
                            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
                          ],
                          onSelected: (val) {
                            if (val == 'edit') _openForm(p);
                            if (val == 'toggle') _toggleActive(p);
                            if (val == 'delete') _confirmDelete(p);
                          },
                        )
                      ]),
                    ])),
                  );
                },
              )
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Produk Baru'),
      ),
    );
  }

  Widget _tab(String id, String label, ColorScheme cs) {
    final active = activeTab == id;
    return InkWell(
      onTap: () => setState(() => activeTab = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: active ? cs.primary : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.w500, color: active ? cs.onPrimary : cs.onSurfaceVariant)),
      ),
    );
  }
}


class ProdukFormDialog extends StatefulWidget {
  final dynamic product;
  final List<dynamic> categories;
  final VoidCallback onSave;

  const ProdukFormDialog({super.key, this.product, required this.categories, required this.onSave});

  @override
  State<ProdukFormDialog> createState() => _ProdukFormDialogState();
}

class _ProdukFormDialogState extends State<ProdukFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _barcodeCtrl, _priceCtrl, _descCtrl;
  int? _selectedCat;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: (p?['name'] ?? '').toString());
    _barcodeCtrl = TextEditingController(text: (p?['barcode'] ?? '').toString());
    _priceCtrl = TextEditingController(text: p != null ? (p['price'] ?? 0).toString() : '');
    _descCtrl = TextEditingController(text: (p?['description'] ?? '').toString());

    if (widget.categories.isNotEmpty) {
      final catId = _toInt(p?['category_id']) ?? _toInt(widget.categories.first['id']);
      if (catId != null) {
        _selectedCat = catId;
      }
    }
  }

  static double _parseIDN(String v) {
    if (v.isEmpty) return 0;
    String clean = v.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isSaving = true);

    final data = {
      'name': toTitleCase(_nameCtrl.text.trim()),
      'category_id': _selectedCat,
      'barcode': _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
      'price': _parseIDN(_priceCtrl.text),
      'description': _descCtrl.text.trim(),
    };

    try {
      if (widget.product != null) {
        await Api.put('/products/${widget.product['id']}', body: data);
      } else {
        await Api.post('/products', body: data);
      }
      if (mounted) {
        widget.onSave();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSaving = false);
        showAdminToast(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    
    return Dialog(
      insetPadding: isMobile ? const EdgeInsets.symmetric(horizontal: 8, vertical: 24) : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(widget.product != null ? 'Edit Produk' : 'Tambah Produk', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Basic Info
              _field(_nameCtrl, 'Nama Produk', true, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedCat,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategori', isDense: true),
                items: widget.categories.map((c) => DropdownMenuItem<int>(value: _toInt(c['id']) ?? 0, child: Text('${c['icon'] ?? '📦'} ${c['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _selectedCat = v),
                validator: (v) => v == null ? 'Wajib' : null,
              ),
              const SizedBox(height: 16),
              _field(_priceCtrl, 'Harga Jual', true, isNum: true, prefix: 'Rp'),
              const SizedBox(height: 16),
              _field(_barcodeCtrl, 'Barcode (opsional)', false),
              const SizedBox(height: 16),
              _field(_descCtrl, 'Deskripsi (opsional)', false),
            ])),
          )),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              const SizedBox(width: 12),
              FilledButton(onPressed: isSaving ? null : _save, child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan Produk')),
            ]),
          )
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, bool required, {bool isNum = false, String? prefix, TextCapitalization? textCapitalization}) {
    return TextFormField(
      controller: ctrl,
      textCapitalization: textCapitalization ?? TextCapitalization.none,
      decoration: InputDecoration(labelText: label, isDense: true, prefixText: prefix != null ? '$prefix ' : null),
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'Wajib' : null : null,
    );
  }
}

class RecipeModal extends StatefulWidget {
  final dynamic product;
  const RecipeModal({super.key, required this.product});

  @override
  State<RecipeModal> createState() => _RecipeModalState();
}

class _RecipeModalState extends State<RecipeModal> {
  List<dynamic> _ingredients = [];
  List<dynamic> _availableBahan = [];
  bool _isLoading = true;
  
  int? _selectedBahanId;
  final _qtyCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        Api.get('/resep/${widget.product['id']}').catchError((_) => []),
        Api.get('/bahan-baku').catchError((_) => []),
      ]);
      if (mounted) {
        setState(() {
          _ingredients = futures[0] as List;
          _availableBahan = futures[1] as List;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAdminToast(context, 'Gagal memuat data: $e');
      }
    }
  }

  void _addIngredient() async {
    if (!_formKey.currentState!.validate() || _selectedBahanId == null) return;
    
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (qty <= 0) return;

    try {
      await Api.post('/resep', body: {
        'product_id': widget.product['id'],
        'bahan_baku_id': _selectedBahanId,
        'qty_needed': qty,
      });
      _qtyCtrl.clear();
      _selectedBahanId = null;
      _loadData();
    } catch (e) {
      if (mounted) showAdminToast(context, 'Error: $e');
    }
  }

  void _deleteIngredient(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: const Text('Hapus bahan ini dari resep?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Ya, Hapus')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Api.delete('/resep/$id');
      _loadData();
    } catch (e) {
      if (mounted) showAdminToast(context, 'Error: $e');
    }
  }

  void _editIngredientQty(dynamic ing) async {
    final currentQty = (ing['qty_needed'] as num?)?.toDouble() ?? 0;
    final editCtrl = TextEditingController(text: currentQty == currentQty.roundToDouble() ? '${currentQty.round()}' : currentQty.toString());
    final unit = ing['bahan_unit']?.toString() ?? '';

    final newQty = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit Takaran: ${ing['bahan_name']}'),
        content: TextField(
          controller: editCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Qty Dibutuhkan', suffixText: unit, isDense: true),
          onSubmitted: (v) {
            final val = double.tryParse(v.replaceAll(',', '.'));
            Navigator.pop(dialogContext, val);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(onPressed: () {
            final val = double.tryParse(editCtrl.text.replaceAll(',', '.'));
            Navigator.pop(dialogContext, val);
          }, child: const Text('Simpan')),
        ],
      ),
    );

    if (newQty == null || newQty <= 0) return;

    try {
      await Api.put('/resep/${ing['id']}', body: {'qty_needed': newQty});
      _loadData();
    } catch (e) {
      if (mounted) showAdminToast(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    double totalHpp = 0;
    for (var ing in _ingredients) {
      final cost = (ing['bahan_cost_price'] as num?)?.toDouble() ?? 0;
      final qty = (ing['qty_needed'] as num?)?.toDouble() ?? 0;
      totalHpp += cost * qty;
    }

    String selectedUnit = '';
    if (_selectedBahanId != null) {
      try {
        final b = _availableBahan.firstWhere((e) => e['id'] == _selectedBahanId);
        selectedUnit = b['unit']?.toString() ?? '';
      } catch (_) {}
    }

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Atur Resep: ${widget.product['name']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Divider(),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _selectedBahanId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Pilih Bahan Baku', isDense: true),
                    items: _availableBahan.map((b) => DropdownMenuItem<int>(
                      value: b['id'] as int,
                      child: Text('${b['name']} (${b['unit']})'),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedBahanId = v),
                    validator: (v) => v == null ? 'Wajib' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _qtyCtrl,
                    decoration: InputDecoration(
                      labelText: 'Qty Dibutuhkan', 
                      isDense: true,
                      suffixText: selectedUnit.isNotEmpty ? selectedUnit : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => v == null || v.isEmpty ? 'Wajib' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  child: FilledButton.icon(
                    onPressed: _addIngredient,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah'),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Bahan Baku Terdaftar:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _ingredients.isEmpty 
                ? const Center(child: Text('Belum ada bahan baku untuk produk ini.'))
                : ListView.builder(
                    itemCount: _ingredients.length,
                    itemBuilder: (context, i) {
                      final ing = _ingredients[i];
                      final cost = (ing['bahan_cost_price'] as num?)?.toDouble() ?? 0;
                      final qty = (ing['qty_needed'] as num?)?.toDouble() ?? 0;
                      final subtotal = cost * qty;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.science),
                          title: Text('${ing['bahan_name']} - $qty ${ing['bahan_unit']}'),
                          subtitle: Text('Modal per satuan: ${fmtPrice(cost)} | Subtotal: ${fmtPrice(subtotal)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit, color: cs.primary),
                                tooltip: 'Edit takaran',
                                onPressed: () => _editIngredientQty(ing),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Hapus bahan',
                                onPressed: () => _deleteIngredient(ing['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Estimasi HPP/Modal: ${fmtPrice(totalHpp)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary),
            ),
          )
        ],
      ),
    );
  }
}
