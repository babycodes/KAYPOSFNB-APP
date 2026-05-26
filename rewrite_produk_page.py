import sys

with open("frontend/lib/features/admin/produk_page.dart", "r") as f:
    lines = f.readlines()

new_lines = lines[:256]

new_code = """
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
    try {
      await Api.delete('/resep/$id');
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
                    decoration: const InputDecoration(labelText: 'Qty Dibutuhkan', isDense: true),
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
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteIngredient(ing['id']),
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
"""

with open("frontend/lib/features/admin/produk_page.dart", "w") as f:
    f.writelines(new_lines)
    f.write(new_code)
