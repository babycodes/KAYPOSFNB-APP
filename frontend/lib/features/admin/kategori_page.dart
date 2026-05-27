import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../kasir/dialogs/confirm_dialog.dart';

class KategoriPage extends StatefulWidget {
  const KategoriPage({super.key});
  @override
  State<KategoriPage> createState() => _KategoriPageState();
}

class _KategoriPageState extends State<KategoriPage> {
  List<dynamic> categories = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final res = await Api.get('/categories');
      if (mounted) {
        setState(() {
          categories = res as List;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      if (mounted) {
        showAdminToast(context, 'Error: $e');
      }
    }
  }

  void _openForm([dynamic category]) {
    showDialog(
      context: context,
      builder: (_) =>
          KategoriFormDialog(category: category, onSave: () => _loadData()),
    );
  }

  void _confirmDelete(dynamic cat) async {
    final hasProducts = (cat['product_count'] ?? 0) > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => KayConfirmDialog(
        title: 'Hapus Kategori',
        message: hasProducts
            ? 'Kategori "${cat['name']}" memiliki ${cat['product_count']} produk. Menghapus kategori ini juga akan MENGHAPUS SEMUA PRODUK di dalamnya. Lanjutkan?'
            : 'Yakin ingin menghapus kategori "${cat['name']}"?',
        confirmText: 'Ya, Hapus',
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await Api.delete('/categories/${cat['id']}?force=1');
        _loadData();
      } catch (e) {
        if (mounted) {
          showAdminToast(context, 'Error: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : categories.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '📦',
                    style: TextStyle(
                      fontSize: 64,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada kategori',
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : isMobile
            ? ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: categories.length,
                itemBuilder: (context, i) => _buildCategoryItem(categories[i], cs),
              )
            : GridView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisExtent: 90,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: categories.length,
              itemBuilder: (context, i) => _buildCategoryItem(categories[i], cs),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCategoryItem(dynamic cat, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: buildCategoryIcon(cat['icon'])),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cat['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${cat['total_products'] ?? 0} Produk', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
                  ],
                  onSelected: (val) {
                    if (val == 'edit') _openForm(cat);
                    if (val == 'delete') _confirmDelete(cat);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class KategoriFormDialog extends StatefulWidget {
  final dynamic category;
  final VoidCallback onSave;
  const KategoriFormDialog({super.key, this.category, required this.onSave});

  @override
  State<KategoriFormDialog> createState() => _KategoriFormDialogState();
}

class _KategoriFormDialogState extends State<KategoriFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  String _selectedIcon = '📦';
  late TextEditingController _sortCtrl;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.category?['name'] ?? '');
    _selectedIcon = widget.category?['icon'] ?? '📦';
    _sortCtrl = TextEditingController(
      text: (widget.category?['sort_order'] ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();

    _sortCtrl.dispose();
    super.dispose();
  }

  void _openIconPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih Icon Kategori',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: categoryIcons.length,
                  itemBuilder: (context, i) {
                    final key = categoryIcons.keys.elementAt(i);
                    final icon = categoryIcons[key]!;
                    return InkWell(
                      onTap: () {
                        setState(() => _selectedIcon = key);
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _selectedIcon == key
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon,
                          size: 28,
                          color: _selectedIcon == key
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isSaving = true);

    final data = {
      'name': _nameCtrl.text.trim(),
      'icon': _selectedIcon,
      'sort_order': int.tryParse(_sortCtrl.text) ?? 0,
    };

    try {
      if (widget.category != null) {
        await Api.put('/categories/${widget.category['id']}', body: data);
      } else {
        await Api.post('/categories', body: data);
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
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.category != null ? 'Edit Kategori' : 'Tambah Kategori',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  InkWell(
                    onTap: _openIconPicker,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 80,
                      height: 56,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Center(
                        child: buildCategoryIcon(_selectedIcon, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nama Kategori',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _sortCtrl,
                decoration: const InputDecoration(
                  labelText: 'Urutan (Sort Order)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: isSaving ? null : _save,
                    child: isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Simpan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
