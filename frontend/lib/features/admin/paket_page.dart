import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../kasir/dialogs/confirm_dialog.dart';

class PaketPage extends StatefulWidget {
  const PaketPage({super.key});
  @override
  State<PaketPage> createState() => _PaketPageState();
}

class _PaketPageState extends State<PaketPage> {
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
      final isPaket = (p['is_paket'] as num?)?.toInt() == 1;
      if (!isPaket) return false;
      
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
    showDialog(context: context, builder: (_) => PaketFormDialog(
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
    final isPaket = (product['is_paket'] as num?)?.toInt() == 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => isPaket ? PaketItemsModal(product: product) : RecipeModal(product: product),
    ).then((_) {
      _loadData();
    });
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
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = items[i];
                      final isActive = p['is_active'] == 1;
                      return Container(
                        decoration: BoxDecoration(
                          color: isActive ? cs.surfaceBright : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: IntrinsicHeight(child: Row(children: [
                          // Category icon left strip
                          Container(
                            width: 6,
                            decoration: BoxDecoration(
                              color: isActive ? cs.primary.withValues(alpha: 0.3) : cs.outlineVariant,
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Content
                          Expanded(child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(child: Text(p['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isActive ? cs.onSurface : cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                if ((p['is_paket'] as num?)?.toInt() == 1) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.deepOrange, borderRadius: BorderRadius.circular(4)), child: const Text('PAKET', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)))],
                                if (!isActive) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(4)), child: Text('NON-AKTIF', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cs.onErrorContainer)))],
                              ]),
                              const SizedBox(height: 4),
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(4)),
                                  child: Text(p['category_name'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.primary)),
                                ),
                                Text(fmtPrice((p['price'] as num?)?.toDouble() ?? 0), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? cs.primary : cs.onSurfaceVariant)),
                                Text('HPP: ${fmtPrice((p['total_hpp'] as num?)?.toDouble() ?? 0)}', style: TextStyle(fontSize: 11, color: cs.error)),
                              ]),
                              // Package content badges
                              if (p['paket_items'] is List && (p['paket_items'] as List).isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Wrap(spacing: 4, runSpacing: 4, children: [
                                  for (final pi in p['paket_items'])
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade700,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${(pi['qty'] as num?)?.toInt() ?? 1}x ${pi['product_name'] ?? ''}',
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white),
                                      ),
                                    ),
                                ]),
                              ],
                            ]),
                          )),
                          // Actions: Desktop = buttons, Mobile = three dots
                          if (isMobile)
                            PopupMenuButton(
                              icon: const Icon(Icons.more_vert),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'recipe', child: Row(children: [Icon(Icons.fastfood, size: 18, color: Colors.orange), SizedBox(width: 8), Text('Atur Produk Paket', style: TextStyle(color: Colors.orange))])),
                                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                                PopupMenuItem(value: 'toggle', child: Row(children: [Icon(isActive ? Icons.visibility_off : Icons.visibility, size: 18), const SizedBox(width: 8), Text(isActive ? 'Non-aktifkan' : 'Aktifkan')])),
                                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
                              ],
                              onSelected: (val) {
                                if (val == 'recipe') _openRecipe(p);
                                if (val == 'edit') _openForm(p);
                                if (val == 'toggle') _toggleActive(p);
                                if (val == 'delete') _confirmDelete(p);
                              },
                            )
                          else ...[
                            ElevatedButton.icon(
                              onPressed: () => _openRecipe(p),
                              icon: const Icon(Icons.fastfood, size: 16), label: const Text('Isi Paket'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade50, foregroundColor: Colors.orange.shade700, elevation: 0),
                            ),
                            PopupMenuButton(
                              icon: const Icon(Icons.more_vert),
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                                PopupMenuItem(value: 'toggle', child: Row(children: [Icon(isActive ? Icons.visibility_off : Icons.visibility, size: 18), const SizedBox(width: 8), Text(isActive ? 'Non-aktifkan' : 'Aktifkan')])),
                                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
                              ],
                              onSelected: (val) {
                                if (val == 'edit') _openForm(p);
                                if (val == 'toggle') _toggleActive(p);
                                if (val == 'delete') _confirmDelete(p);
                              },
                            ),
                          ],
                        ])),
                      );
                    },
                  ),
                ),
              )
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
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


class PaketFormDialog extends StatefulWidget {
  final dynamic product;
  final List<dynamic> categories;
  final VoidCallback onSave;

  const PaketFormDialog({super.key, this.product, required this.categories, required this.onSave});

  @override
  State<PaketFormDialog> createState() => _PaketFormDialogState();
}

class _PaketFormDialogState extends State<PaketFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl, _barcodeCtrl, _priceCtrl, _descCtrl;
  dynamic _selectedCat;
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
      final catId = p?['category_id'] ?? widget.categories.first['id'];
      _selectedCat = catId;
    }
  }

  static double _parseIDN(String v) {
    if (v.isEmpty) return 0;
    String clean = v.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
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
      'is_paket': 1,
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
              Text(widget.product != null ? 'Edit Paket' : 'Tambah Paket', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Basic Info
              _field(_nameCtrl, 'Nama Paket', true, textCapitalization: TextCapitalization.words),
              const SizedBox(height: 16),
              DropdownButtonFormField(
                value: _selectedCat,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategori', isDense: true),
                items: widget.categories.map((c) => DropdownMenuItem(value: c['id'], child: Text('${c['icon'] ?? '📦'} ${c['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
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
              FilledButton(onPressed: isSaving ? null : _save, child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan Paket')),
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
  
  dynamic _selectedBahanId;
  final _qtyCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Maps master unit to recipe input unit for human-readable entry
  /// Kg → gram, Liter → ml. Other units pass through unchanged.
  String _recipeInputUnit(String masterUnit) {
    final lower = masterUnit.toLowerCase();
    if (lower == 'kg') return 'gram';
    if (lower == 'liter' || lower == 'l') return 'ml';
    return masterUnit;
  }

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

    // Check for duplicate: if this bahan already exists in the recipe
    final existing = _ingredients.where((ing) => ing['bahan_baku_id'] == _selectedBahanId).toList();
    if (existing.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bahan sudah ada di dalam resep, silakan edit jumlahnya.')),
        );
      }
      return;
    }

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

  void _showBahanPicker(BuildContext parentContext) {
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        String search = '';
        return StatefulBuilder(builder: (ctx, setSheetState) {
          final filteredBahan = _availableBahan.where((b) {
            if (search.isEmpty) return true;
            final q = search.toLowerCase();
            return (b['name'] ?? '').toString().toLowerCase().contains(q);
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, scrollController) => Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Pilih Bahan Baku', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ]),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Cari bahan baku...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: (v) => setSheetState(() => search = v),
                  ),
                ]),
              ),
              const Divider(),
              Expanded(
                child: filteredBahan.isEmpty
                    ? Center(child: Text('Tidak ditemukan', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filteredBahan.length,
                        itemBuilder: (_, i) {
                          final b = filteredBahan[i];
                          final isSelected = _selectedBahanId == b['id'];
                          return ListTile(
                            leading: Icon(Icons.science, color: isSelected ? Theme.of(ctx).colorScheme.primary : null),
                            title: Text(b['name']?.toString() ?? '', style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                            subtitle: Text('${b['unit']} • Stok: ${(b['stock'] as num?)?.toStringAsFixed(0) ?? '0'}'),
                            trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(ctx).colorScheme.primary) : null,
                            onTap: () {
                              setState(() => _selectedBahanId = b['id']);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
              ),
            ]),
          );
        });
      },
    );
  }

  void _deleteIngredient(dynamic id) async {
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
    final unit = _recipeInputUnit(ing['bahan_unit']?.toString() ?? '');

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
      final unit = (ing['bahan_unit'] ?? '').toString().toLowerCase();
      final normalizedCost = (unit == 'kg' || unit == 'liter' || unit == 'l') ? cost / 1000 : cost;
      totalHpp += normalizedCost * qty;
    }

    String selectedUnit = '';
    if (_selectedBahanId != null) {
      try {
        final b = _availableBahan.firstWhere((e) => e['id'] == _selectedBahanId);
        final masterUnit = b['unit']?.toString() ?? '';
        selectedUnit = _recipeInputUnit(masterUnit);
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
            child: Builder(builder: (context) {
              final isMobile = MediaQuery.sizeOf(context).width < 600;

              // Find selected bahan name for display
              String selectedBahanLabel = 'Pilih Bahan Baku';
              if (_selectedBahanId != null) {
                try {
                  final b = _availableBahan.firstWhere((e) => e['id'] == _selectedBahanId);
                  selectedBahanLabel = '${b['name']} (${b['unit']})';
                } catch (_) {}
              }

              final bahanSelector = InkWell(
                onTap: () => _showBahanPicker(context),
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Bahan Baku *',
                    isDense: true,
                    prefixIcon: const Icon(Icons.science, size: 20),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                    errorText: _selectedBahanId == null && _formKey.currentState?.validate() == false ? 'Wajib' : null,
                  ),
                  child: Text(selectedBahanLabel, overflow: TextOverflow.ellipsis),
                ),
              );

              final qtyField = TextFormField(
                controller: _qtyCtrl,
                decoration: InputDecoration(
                  labelText: 'Qty Dibutuhkan',
                  isDense: true,
                  suffixText: selectedUnit.isNotEmpty ? selectedUnit : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v == null || v.isEmpty ? 'Wajib' : null,
              );

              final addBtn = FilledButton.icon(
                onPressed: _addIngredient,
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              );

              if (isMobile) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  bahanSelector,
                  const SizedBox(height: 12),
                  qtyField,
                  const SizedBox(height: 12),
                  addBtn,
                ]);
              }

              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: bahanSelector),
                const SizedBox(width: 12),
                Expanded(child: qtyField),
                const SizedBox(width: 12),
                Container(margin: const EdgeInsets.only(top: 4), child: addBtn),
              ]);
            }),
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
                      final masterUnit = (ing['bahan_unit'] ?? '').toString();
                      final lowerUnit = masterUnit.toLowerCase();
                      final recipeUnit = _recipeInputUnit(masterUnit);
                      final baseCost = (lowerUnit == 'kg' || lowerUnit == 'liter' || lowerUnit == 'l') ? cost / 1000 : cost;
                      final biayaBahan = baseCost * qty;
                      final qtyStr = qty == qty.roundToDouble() ? qty.round().toString() : qty.toStringAsFixed(2);
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.science),
                          title: Text('${ing['bahan_name']} — $qtyStr $recipeUnit'),
                          subtitle: Text('Modal: ${fmtPrice(baseCost)}/$recipeUnit | Biaya Bahan: ${fmtPrice(biayaBahan)}'),
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

class PaketItemsModal extends StatefulWidget {
  final dynamic product;
  const PaketItemsModal({super.key, required this.product});
  @override
  State<PaketItemsModal> createState() => _PaketItemsModalState();
}

class _PaketItemsModalState extends State<PaketItemsModal> {
  List<dynamic> _items = [];
  List<dynamic> _allProducts = [];
  bool _isLoading = true;
  dynamic _selectedProductId;
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        Api.get('/paket-items/${widget.product['id']}').catchError((_) => []),
        Api.get('/products/all').catchError((_) => []),
      ]);
      if (mounted) {
        setState(() {
          _items = futures[0] as List;
          // Filter out the paket itself and other pakets from selection
          _allProducts = (futures[1] as List).where((p) {
            final id = p['id'];
            final isPaket = (p['is_paket'] as num?)?.toInt() == 1;
            return id != widget.product['id'] && !isPaket && p['is_active'] == 1;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) { setState(() => _isLoading = false); showAdminToast(context, 'Error: $e'); }
    }
  }

  void _addItem() async {
    if (_selectedProductId == null) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    if (qty <= 0) return;

    final existing = _items.where((i) => i['product_id'] == _selectedProductId).toList();
    if (existing.isNotEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk sudah ada di dalam paket.')));
      return;
    }

    try {
      await Api.post('/paket-items', body: {
        'paket_id': widget.product['id'],
        'product_id': _selectedProductId,
        'qty': qty,
      });
      _qtyCtrl.text = '1';
      _selectedProductId = null;
      _loadData();
    } catch (e) {
      if (mounted) showAdminToast(context, 'Error: $e');
    }
  }

  void _deleteItem(dynamic id) async {
    try {
      await Api.delete('/paket-items/$id');
      _loadData();
    } catch (e) {
      if (mounted) showAdminToast(context, 'Error: $e');
    }
  }

  void _editItemQty(dynamic item) async {
    final currentQty = (item['qty'] as num?)?.toInt() ?? 1;
    final editCtrl = TextEditingController(text: currentQty.toString());

    final newQty = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit Qty: ${item['product_name']}'),
        content: TextField(
          controller: editCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Qty', isDense: true),
          onSubmitted: (v) {
            final val = int.tryParse(v);
            Navigator.pop(dialogContext, val);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(onPressed: () {
            final val = int.tryParse(editCtrl.text);
            Navigator.pop(dialogContext, val);
          }, child: const Text('Simpan')),
        ],
      ),
    );

    if (newQty == null || newQty <= 0) return;

    try {
      await Api.put('/paket-items/${item['id']}', body: {'qty': newQty});
      _loadData();
    } catch (e) {
      if (mounted) showAdminToast(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text('🍱 Atur Isi Paket: ${widget.product['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const Divider(),
        const SizedBox(height: 8),
        // Add item row
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField(
              value: _selectedProductId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Pilih Produk', isDense: true),
              items: _allProducts.map((p) => DropdownMenuItem(
                value: p['id'],
                child: Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setState(() => _selectedProductId = v),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: TextFormField(
              controller: _qtyCtrl,
              decoration: const InputDecoration(labelText: 'Qty', isDense: true),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('Tambah')),
        ]),
        const SizedBox(height: 16),
        const Text('Isi Paket:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Expanded(
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
              ? const Center(child: Text('Belum ada produk di dalam paket ini.'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.fastfood),
                        title: Text('${item['qty']}x ${item['product_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(fmtPrice((item['product_price'] as num?)?.toDouble() ?? 0)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: cs.primary),
                              onPressed: () => _editItemQty(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteItem(item['id']),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Total ${_items.length} produk di dalam paket', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        ),
      ]),
    );
  }
}
