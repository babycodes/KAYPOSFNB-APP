import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';


class DiskonPage extends StatefulWidget {
  const DiskonPage({super.key});
  @override
  State<DiskonPage> createState() => _DiskonPageState();
}

class _DiskonPageState extends State<DiskonPage> {
  List<dynamic> discounts = [];
  bool isLoading = true;
  dynamic _selectedDiscount;

  @override
  void initState() {
    super.initState();
    _loadDiscounts();
  }

  Future<void> _loadDiscounts() async {
    setState(() => isLoading = true);
    try {
      final res = await Api.get('/discounts');
      setState(() => discounts = res as List<dynamic>);
    } catch (e) {
      showToast(context, '❌ Gagal memuat diskon: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _openForm([dynamic diskon]) async {
    try {
      final res = await Api.get('/products');
      if (res is List && res.isEmpty) {
        if (mounted) {
          showAdminToast(context, 'Silakan buat produk terlebih dahulu');
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => DiskonFormDialog(
          diskon: diskon,
          onSave: _loadDiscounts,
        ),
      );
    }
  }

  void _openDetail(dynamic diskon) {
    setState(() => _selectedDiscount = diskon);
  }

  void _confirmDelete(dynamic diskon) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Diskon'),
        content: Text('Hapus diskon "${diskon['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Api.delete('/discounts/${diskon['id']}');
                showToast(context, '✅ Diskon dihapus');
                _loadDiscounts();
              } catch (e) {
                showToast(context, '❌ Gagal menghapus diskon: $e');
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(dynamic diskon, bool val) async {
    try {
      await Api.put('/discounts/${diskon['id']}', body: {
        ...diskon,
        'is_active': val ? 1 : 0,
      });
      _loadDiscounts();
    } catch (e) {
      showToast(context, '❌ Gagal update status: $e');
    }
  }

  String _formatSchedule(dynamic diskon) {
    final type = diskon['schedule_type']?.toString() ?? 'all_day';
    final val = diskon['schedule_value']?.toString() ?? '';
    
    if (type == 'all_day') return 'Setiap Hari';
    if (type == 'specific_days') {
      try {
        final dayMap = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
        final days = val.split(',').map((e) => int.tryParse(e.trim())).where((e) => e != null).cast<int>();
        final result = days.map((d) => d >= 1 && d <= 7 ? dayMap[d - 1] : '').where((e) => e.isNotEmpty).join(', ');
        return result.isNotEmpty ? result : val;
      } catch (_) {
        return val;
      }
    }
    if (type == 'date_range') {
      try {
        final months = ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
        final parts = val.split(',');
        if (parts.length == 2) {
          final startParts = parts[0].trim().split('-');
          final endParts = parts[1].trim().split('-');
          if (startParts.length == 3 && endParts.length == 3) {
            final sDay = int.parse(startParts[2]);
            final sMonth = int.parse(startParts[1]);
            final sYear = int.parse(startParts[0]);
            final eDay = int.parse(endParts[2]);
            final eMonth = int.parse(endParts[1]);
            final eYear = int.parse(endParts[0]);
            // Same month and year: "12 - 15 November 2023"
            if (sMonth == eMonth && sYear == eYear) {
              return '$sDay - $eDay ${months[eMonth]} $eYear';
            }
            // Same year: "12 November - 15 Desember 2023"
            if (sYear == eYear) {
              return '$sDay ${months[sMonth]} - $eDay ${months[eMonth]} $eYear';
            }
            // Different year
            return '$sDay ${months[sMonth]} $sYear - $eDay ${months[eMonth]} $eYear';
          }
        }
      } catch (_) {}
    }
    return val;
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedDiscount != null) {
      return DiskonDetailPage(
        diskon: _selectedDiscount,
        onBack: () {
          setState(() => _selectedDiscount = null);
          _loadDiscounts();
        },
      );
    }
    
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : discounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.discount_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text('Belum ada diskon', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: discounts.length,
                  itemBuilder: (context, index) {
                    final d = discounts[index];
                    final isActive = d['is_active'] == 1;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        onTap: () => _openDetail(d),
                        leading: CircleAvatar(
                          backgroundColor: isActive ? cs.primaryContainer : cs.surfaceContainerHighest,
                          child: Icon(Icons.discount, color: isActive ? cs.primary : cs.onSurfaceVariant),
                        ),
                        title: Text(d['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${d['discount_percent']}% • ${_formatSchedule(d)}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isActive,
                              onChanged: (val) => _toggleActive(d, val),
                            ),
                            PopupMenuButton(
                              icon: const Icon(Icons.more_vert),
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Hapus', style: TextStyle(color: Colors.red))])),
                              ],
                              onSelected: (val) {
                                if (val == 'edit') _openForm(d);
                                if (val == 'delete') _confirmDelete(d);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ----------------------------------------------------------------------------
// MASTER FORM: Create / Edit Discount (Name, Percent, Schedule Only)
// ----------------------------------------------------------------------------
class DiskonFormDialog extends StatefulWidget {
  final dynamic diskon;
  final VoidCallback onSave;

  const DiskonFormDialog({super.key, this.diskon, required this.onSave});

  @override
  State<DiskonFormDialog> createState() => _DiskonFormDialogState();
}

class _DiskonFormDialogState extends State<DiskonFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _percentCtrl;
  late TextEditingController _scheduleValueCtrl;

  String _scheduleType = 'all_day'; // all_day | date_range | specific_days
  bool isSaving = false;
  List<String> _selectedDays = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.diskon?['name'] ?? '');
    _percentCtrl = TextEditingController(text: (widget.diskon?['discount_percent'] ?? '').toString());
    _scheduleValueCtrl = TextEditingController(text: widget.diskon?['schedule_value'] ?? '');

    if (widget.diskon != null) {
      _scheduleType = widget.diskon['schedule_type'] ?? 'all_day';
      if (_scheduleType == 'specific_days') {
        _selectedDays = _scheduleValueCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _percentCtrl.dispose();
    _scheduleValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (range != null) {
      setState(() {
        _scheduleValueCtrl.text = '${range.start.toIso8601String().split('T')[0]},${range.end.toIso8601String().split('T')[0]}';
      });
    }
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_scheduleType == 'specific_days') {
      _scheduleValueCtrl.text = _selectedDays.join(',');
    }
    
    if (_scheduleType != 'all_day' && _scheduleValueCtrl.text.isEmpty) {
      showToast(context, 'Pilih jadwal terlebih dahulu');
      return;
    }

    setState(() => isSaving = true);
    
    final payload = {
      'name': _nameCtrl.text,
      'discount_percent': int.tryParse(_percentCtrl.text) ?? 0,
      'schedule_type': _scheduleType,
      'schedule_value': _scheduleValueCtrl.text,
      'is_active': widget.diskon?['is_active'] ?? 1,
    };

    // If it's a new discount, add empty arrays for target
    if (widget.diskon == null) {
      payload['target_categories'] = [];
      payload['target_products'] = [];
    }

    try {
      if (widget.diskon == null) {
        await Api.post('/discounts', body: payload);
        if (mounted) showToast(context, '✅ Diskon ditambahkan');
      } else {
        await Api.put('/discounts/${widget.diskon['id']}', body: payload);
        if (mounted) showToast(context, '✅ Diskon diperbarui');
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onSave();
      }
    } catch (e) {
      if (mounted) showToast(context, '❌ Gagal menyimpan diskon: $e');
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.diskon == null ? 'Tambah Diskon' : 'Edit Diskon'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Promo / Diskon', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _percentCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nilai Diskon (%)', border: OutlineInputBorder(), suffixText: '%'),
                validator: (v) {
                  if (v!.isEmpty) return 'Wajib diisi';
                  final num = int.tryParse(v);
                  if (num == null || num <= 0 || num > 100) return 'Tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _scheduleType,
                decoration: const InputDecoration(labelText: 'Jadwal', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'all_day', child: Text('Setiap Hari (All Day)')),
                  DropdownMenuItem(value: 'date_range', child: Text('Rentang Tanggal')),
                  DropdownMenuItem(value: 'specific_days', child: Text('Hari Tertentu (Misal: Senin)')),
                ],
                onChanged: (v) {
                  setState(() {
                    _scheduleType = v!;
                    _scheduleValueCtrl.clear();
                  });
                },
              ),
              if (_scheduleType == 'date_range') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _scheduleValueCtrl,
                  readOnly: true,
                  onTap: _pickDateRange,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Rentang Tanggal',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                ),
              ] else if (_scheduleType == 'specific_days') ...[
                const SizedBox(height: 16),
                const Text('Pilih Hari:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'].map((day) {
                    final dayInt = {'Senin': '1', 'Selasa': '2', 'Rabu': '3', 'Kamis': '4', 'Jumat': '5', 'Sabtu': '6', 'Minggu': '7'}[day]!;
                    final isSelected = _selectedDays.contains(dayInt);
                    return FilterChip(
                      label: Text(day),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedDays.add(dayInt);
                          } else {
                            _selectedDays.remove(dayInt);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: isSaving ? null : _save,
          child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Simpan'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// DETAIL PAGE: View Discount & Manage Products/Categories
// ----------------------------------------------------------------------------
class DiskonDetailPage extends StatefulWidget {
  final dynamic diskon;
  final VoidCallback onBack;
  const DiskonDetailPage({super.key, required this.diskon, required this.onBack});

  @override
  State<DiskonDetailPage> createState() => _DiskonDetailPageState();
}

class _DiskonDetailPageState extends State<DiskonDetailPage> {
  late dynamic diskon;
  List<dynamic> targetCategories = [];
  List<dynamic> targetProducts = [];
  Map<dynamic, String> disabledCategories = {};
  Map<dynamic, String> disabledProducts = {};
  
  List<dynamic> allProducts = [];
  List<dynamic> allCategories = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    diskon = widget.diskon;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final pRes = await Api.get('/products');
      final cRes = await Api.get('/categories');
      final dRes = await Api.get('/discounts');
      
      dynamic latestDiskon = diskon;
      Map<dynamic, String> dCats = {};
      Map<dynamic, String> dProds = {};
      
      for (var d in (dRes as List)) {
        if (d['id'] == diskon['id']) {
          latestDiskon = d;
        } else if (d['is_active'] == 1 || d['is_active'] == true) {
          final promoName = d['name'].toString();
          final tCats = (d['target_categories'] as List?) ?? [];
          final tProds = (d['target_products'] as List?) ?? [];
          
          for (final cId in tCats) {
            dCats[cId] = promoName;
            final childProducts = (pRes as List).where((p) => p['category_id'] == cId).map((p) => p['id']).toList();
            for (final cpId in childProducts) {
              dProds[cpId] = promoName;
            }
          }
          for (final pId in tProds) {
            dProds[pId] = promoName;
          }
        }
      }
      
      setState(() {
        allProducts = pRes as List<dynamic>;
        allCategories = cRes as List<dynamic>;
        diskon = latestDiskon;
        
        targetCategories = (diskon['target_categories'] as List?) ?? [];
        targetProducts = (diskon['target_products'] as List?) ?? [];
        disabledCategories = dCats;
        disabledProducts = dProds;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) showToast(context, '❌ Gagal memuat data: $e');
      setState(() => isLoading = false);
    }
  }

  void _openTargetModal() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    Widget dialog = TargetSelectionModal(
      allProducts: allProducts,
      allCategories: allCategories,
      initialCategories: targetCategories,
      initialProducts: targetProducts,
      disabledCategories: disabledCategories,
      disabledProducts: disabledProducts,
      onSave: (cats, prods) async {
        cats.removeWhere((cId) {
          if (disabledCategories.containsKey(cId) && disabledCategories[cId] != diskon['name']) return true;
          final catProds = allProducts.where((p) => p['category_id'] == cId).toList();
          return catProds.any((p) => disabledProducts.containsKey(p['id']) && disabledProducts[p['id']] != diskon['name']);
        });
        prods.removeWhere((id) => disabledProducts.containsKey(id) && disabledProducts[id] != diskon['name']);
        try {
          await Api.put('/discounts/${diskon['id']}', body: {
            ...diskon,
            'target_categories': cats,
            'target_products': prods,
          });
          _loadData();
        } catch (e) {
          showToast(context, '❌ Gagal menyimpan target: $e');
        }
      },
    );
    
    if (isMobile) {
      showDialog(context: context, builder: (_) => Dialog.fullscreen(child: dialog));
    } else {
      showDialog(context: context, builder: (_) => dialog);
    }
  }

  String _formatScheduleDetail(dynamic diskon) {
    final type = diskon['schedule_type']?.toString() ?? 'all_day';
    final val = diskon['schedule_value']?.toString() ?? '';
    
    if (type == 'all_day') return 'Setiap Hari';
    if (type == 'specific_days') {
      try {
        final dayMap = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
        final days = val.split(',').map((e) => int.tryParse(e.trim())).where((e) => e != null).cast<int>();
        final result = days.map((d) => d >= 1 && d <= 7 ? dayMap[d - 1] : '').where((e) => e.isNotEmpty).join(', ');
        return result.isNotEmpty ? result : val;
      } catch (_) {
        return val;
      }
    }
    if (type == 'date_range') {
      try {
        final months = ['', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
        final parts = val.split(',');
        if (parts.length == 2) {
          final startParts = parts[0].trim().split('-');
          final endParts = parts[1].trim().split('-');
          if (startParts.length == 3 && endParts.length == 3) {
            final sDay = int.parse(startParts[2]);
            final sMonth = int.parse(startParts[1]);
            final sYear = int.parse(startParts[0]);
            final eDay = int.parse(endParts[2]);
            final eMonth = int.parse(endParts[1]);
            final eYear = int.parse(endParts[0]);
            if (sMonth == eMonth && sYear == eYear) {
              return '$sDay - $eDay ${months[eMonth]} $eYear';
            }
            if (sYear == eYear) {
              return '$sDay ${months[sMonth]} - $eDay ${months[eMonth]} $eYear';
            }
            return '$sDay ${months[sMonth]} $sYear - $eDay ${months[eMonth]} $eYear';
          }
        }
      } catch (_) {}
    }
    return val;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    final cs = Theme.of(context).colorScheme;
    
    List<dynamic> displayCategories = allCategories.where((c) => targetCategories.contains(c['id'])).toList();
    List<dynamic> displayProducts = allProducts.where((p) => targetProducts.contains(p['id'])).toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: const Text('Detail Diskon'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 0,
              color: cs.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(diskon['name'], style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                        Chip(
                          label: Text(diskon['is_active'] == 1 ? "Aktif" : "Non-Aktif"),
                          backgroundColor: diskon['is_active'] == 1 ? Colors.green.withValues(alpha: 0.2) : cs.errorContainer,
                          labelStyle: TextStyle(color: diskon['is_active'] == 1 ? Colors.green.shade800 : cs.error, fontWeight: FontWeight.bold),
                          side: BorderSide.none,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.percent, color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('Diskon: ${diskon['discount_percent']}%', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.calendar_month, color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Jadwal: ${_formatScheduleDetail(diskon)}', style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Target Diskon', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            if (targetCategories.isEmpty && targetProducts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: const Column(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 48),
                    SizedBox(height: 8),
                    Text('Belum ada target produk atau kategori yang dipilih.'),
                    Text('Diskon ini tidak akan berlaku untuk produk manapun.'),
                  ],
                ),
              )
            else ...[
              if (displayCategories.isNotEmpty) ...[
                Text('Kategori Terpilih', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.primary)),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayCategories.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.category, size: 20)),
                      title: Text(displayCategories[i]['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              if (displayProducts.isNotEmpty) ...[
                Text('Produk Terpilih', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.primary)),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayProducts.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.inventory_2, size: 20)),
                      title: Text(displayProducts[i]['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openTargetModal,
                icon: const Icon(Icons.add),
                label: const Text('Kelola Produk / Kategori'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// TARGET SELECTION MODAL
// ----------------------------------------------------------------------------
class TargetSelectionModal extends StatefulWidget {
  final List<dynamic> allProducts;
  final List<dynamic> allCategories;
  final List<dynamic> initialCategories;
  final List<dynamic> initialProducts;
  final Map<dynamic, String> disabledCategories;
  final Map<dynamic, String> disabledProducts;
  final Function(List<dynamic> cats, List<dynamic> prods) onSave;

  const TargetSelectionModal({
    super.key,
    required this.allProducts,
    required this.allCategories,
    required this.initialCategories,
    required this.initialProducts,
    this.disabledCategories = const {},
    this.disabledProducts = const {},
    required this.onSave,
  });

  @override
  State<TargetSelectionModal> createState() => _TargetSelectionModalState();
}

class _TargetSelectionModalState extends State<TargetSelectionModal> {
  late List<dynamic> selectedCats;
  late List<dynamic> selectedProds;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    selectedCats = List.from(widget.initialCategories);
    selectedProds = List.from(widget.initialProducts);
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = widget.allProducts.where((p) => p['name'].toString().toLowerCase().contains(searchQuery.toLowerCase())).toList();
    final filteredCategories = widget.allCategories.where((c) {
      final matchName = c['name'].toString().toLowerCase().contains(searchQuery.toLowerCase());
      final hasMatchingProduct = filteredProducts.any((p) => p['category_id'] == c['id']);
      return matchName || hasMatchingProduct;
    }).toList();

    Widget content = SizedBox(
      width: 600,
      height: 600,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Cari kategori atau produk...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => searchQuery = v),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: filteredCategories.length,
              itemBuilder: (ctx, i) {
                final c = filteredCategories[i];
                final isCatSelected = selectedCats.contains(c['id']);
                final isCatDisabled = widget.disabledCategories.containsKey(c['id']);
                final catPromoName = widget.disabledCategories[c['id']];
                final catProds = filteredProducts.where((p) => p['category_id'] == c['id']).toList();
                final shouldExpand = searchQuery.isNotEmpty && catProds.isNotEmpty;
                
                return ExpansionTile(
                  key: Key('${c['id']}_$shouldExpand'),
                  initiallyExpanded: shouldExpand,
                  title: Text(c['name']),
                  subtitle: isCatDisabled ? Text('(Aktif di promo $catPromoName)', style: const TextStyle(color: Colors.red, fontSize: 10)) : null,
                  leading: Checkbox(
                    value: isCatSelected || isCatDisabled,
                    onChanged: isCatDisabled ? null : (val) {
                      setState(() {
                        if (val == true) {
                          selectedCats.add(c['id']);
                          for (final p in catProds) {
                            if (!widget.disabledProducts.containsKey(p['id'])) {
                              if (!selectedProds.contains(p['id'])) {
                                selectedProds.add(p['id']);
                              }
                            }
                          }
                        } else {
                          selectedCats.remove(c['id']);
                          for (final p in catProds) {
                            selectedProds.remove(p['id']);
                          }
                        }
                      });
                    },
                  ),
                  children: catProds.map((p) {
                    final isProdDisabled = widget.disabledProducts.containsKey(p['id']); 
                    final isProdSelected = selectedProds.contains(p['id']) || (isCatSelected && !isProdDisabled);
                    final prodPromoName = widget.disabledProducts[p['id']];
                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      title: Text(p['name']),
                      subtitle: widget.disabledProducts.containsKey(p['id']) ? Text('(Aktif di promo $prodPromoName)', style: const TextStyle(color: Colors.red, fontSize: 10)) : null,
                      value: isProdSelected,
                      enabled: !isProdDisabled,
                      onChanged: isProdDisabled ? null : (val) {
                        setState(() {
                          if (val == true) {
                            selectedProds.add(p['id']);
                          } else {
                            selectedProds.remove(p['id']);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Dialog.fullscreen(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pilih Target Diskon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            Expanded(child: content),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    widget.onSave(selectedCats, selectedProds);
                    Navigator.pop(context);
                  },
                  child: const Text('Simpan Pilihan'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

