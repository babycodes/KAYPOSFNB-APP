import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../kasir/dialogs/confirm_dialog.dart';

class KategoriBahanPage extends StatefulWidget {
  const KategoriBahanPage({super.key});
  @override
  State<KategoriBahanPage> createState() => _KategoriBahanPageState();
}

class _KategoriBahanPageState extends State<KategoriBahanPage> {
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
      final res = await Api.get('/kategori-bahan');
      if (mounted) setState(() { categories = res as List; isLoading = false; });
    } catch (e) {
      if (mounted) { setState(() => isLoading = false); showAdminToast(context, 'Error: $e'); }
    }
  }

  void _openForm([dynamic cat]) {
    final ctrl = TextEditingController(text: cat?['name']?.toString() ?? '');
    final isEdit = cat != null;

    showDialog(context: context, builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isEdit ? 'Edit Kategori Bahan' : 'Tambah Kategori Bahan'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nama Kategori', isDense: true, prefixIcon: Icon(Icons.category_outlined, size: 20)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () async {
            final name = ctrl.text.trim();
            if (name.isEmpty) return;
            try {
              if (isEdit) {
                await Api.put('/kategori-bahan/${cat['id']}', body: {'name': name});
              } else {
                await Api.post('/kategori-bahan', body: {'name': name});
              }
              if (mounted) Navigator.pop(ctx);
              _loadData();
            } catch (e) {
              if (mounted) showAdminToast(context, 'Error: $e');
            }
          }, child: const Text('Simpan')),
        ],
      );
    });
  }

  void _confirmDelete(dynamic cat) async {
    final count = (cat['item_count'] as num?)?.toInt() ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => KayConfirmDialog(
        title: 'Hapus Kategori Bahan',
        message: count > 0
            ? '⚠️ Peringatan! Menghapus kategori "${cat['name']}" akan MENGHAPUS $count bahan baku terkait di dalamnya. Lanjutkan?'
            : 'Yakin ingin menghapus kategori "${cat['name']}"?',
        confirmText: 'Ya, Hapus',
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await Api.delete('/kategori-bahan/${cat['id']}');
        _loadData();
      } catch (e) {
        if (mounted) showAdminToast(context, 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : categories.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.category_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('Belum ada kategori bahan', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
            ]))
          : LayoutBuilder(builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              if (isMobile) {
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: categories.length,
                  itemBuilder: (context, i) {
                    final cat = categories[i];
                    final count = (cat['item_count'] as num?)?.toInt() ?? 0;
                    return _buildCategoryItem(cat, count, cs);
                  },
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 80,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final cat = categories[i];
                  final count = (cat['item_count'] as num?)?.toInt() ?? 0;
                  return _buildCategoryItem(cat, count, cs);
                },
              );
            }),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCategoryItem(dynamic cat, int count, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.science, color: cs.onTertiaryContainer, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(cat['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('$count Bahan Baku', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert, size: 20),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
            ],
            onSelected: (val) {
              if (val == 'edit') _openForm(cat);
              if (val == 'delete') _confirmDelete(cat);
            },
          ),
        ]),
      ),
    );
  }
}
