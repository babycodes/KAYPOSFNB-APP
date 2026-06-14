import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/local_db.dart';
import '../../core/helpers.dart';
import '../../core/auth_provider.dart';
import 'package:provider/provider.dart';

class CashflowPage extends StatefulWidget {
  const CashflowPage({super.key});
  @override
  State<CashflowPage> createState() => _CashflowPageState();
}

class _CashflowPageState extends State<CashflowPage> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late DateTimeRange _dateRange;

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _categories = [];
  // Pre-computed lists for each tab (avoids per-frame filtering)
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _incomeItems = [];
  List<Map<String, dynamic>> _expenseItems = [];
  double _salesIncome = 0;
  double _restockExpense = 0;
  double _manualIncome = 0;
  double _manualExpense = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = await LocalDb.instance;
      final from = _fmtDate(_dateRange.start);
      final to = _fmtDate(_dateRange.end);

      // Load categories
      _categories = (await db.query('cashflow_categories', orderBy: 'type, name')).map((e) => Map<String, dynamic>.from(e)).toList();

      // Load manual cashflow entries
      _entries = (await db.query('cashflows',
        where: 'date BETWEEN ? AND ?',
        whereArgs: [from, to],
        orderBy: 'date DESC, created_at DESC',
      )).map((e) => Map<String, dynamic>.from(e)).toList();

      // Calculate manual totals
      _manualIncome = _entries.where((e) => e['type'] == 'income').fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
      _manualExpense = _entries.where((e) => e['type'] == 'expense').fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));

      // Sales income from transactions table (READ-ONLY query)
      final salesResult = await db.rawQuery('''
        SELECT COALESCE(SUM(total_amount), 0) as total
        FROM transactions
        WHERE status IN ('completed', 'partial_refund')
        AND DATE(created_at) BETWEEN ? AND ?
      ''', [from, to]);
      _salesIncome = (salesResult.first['total'] as num?)?.toDouble() ?? 0;

      // Restock expense from restock_history (READ-ONLY query)
      final restockResult = await db.rawQuery('''
        SELECT COALESCE(SUM(total_cost), 0) as total
        FROM restock_history
        WHERE DATE(timestamp) BETWEEN ? AND ?
      ''', [from, to]);
      _restockExpense = (restockResult.first['total'] as num?)?.toDouble() ?? 0;

      // Pre-compute filtered lists for each tab
      _rebuildFilteredLists();
    } catch (e) {
      debugPrint('Cashflow load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _rebuildFilteredLists() {
    List<Map<String, dynamic>> buildItems(String? typeFilter) {
      final List<Map<String, dynamic>> items = [];
      if (_salesIncome > 0 && (typeFilter == null || typeFilter == 'income')) {
        items.add({
          '_isAuto': true, 'type': 'income',
          'category_name': 'Penjualan Kasir', 'amount': _salesIncome,
          'description': 'Otomatis dari transaksi kasir',
          'date': '${_fmtDate(_dateRange.start)} ~ ${_fmtDate(_dateRange.end)}',
        });
      }
      if (_restockExpense > 0 && (typeFilter == null || typeFilter == 'expense')) {
        items.add({
          '_isAuto': true, 'type': 'expense',
          'category_name': 'Restock Bahan Baku', 'amount': _restockExpense,
          'description': 'Otomatis dari pembelian bahan',
          'date': '${_fmtDate(_dateRange.start)} ~ ${_fmtDate(_dateRange.end)}',
        });
      }
      final filtered = typeFilter == null
        ? _entries
        : _entries.where((e) => e['type'] == typeFilter).toList();
      items.addAll(filtered);
      return items;
    }
    _allItems = buildItems(null);
    _incomeItems = buildItems('income');
    _expenseItems = buildItems('expense');
  }

  double get _totalIncome => _salesIncome + _manualIncome;
  double get _totalExpense => _restockExpense + _manualExpense;
  double get _netCashflow => _totalIncome - _totalExpense;

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _loadData();
    }
  }

  // ══════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return Column(children: [
      // Date filter + action buttons
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_month_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text('${_fmtDate(_dateRange.start)}  →  ${_fmtDate(_dateRange.end)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ]),
            ),
          ),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: () => _showInputDialog(type: 'income'),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Pemasukan', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade50,
              foregroundColor: Colors.green.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () => _showInputDialog(type: 'expense'),
            icon: const Icon(Icons.remove_rounded, size: 16),
            label: const Text('Pengeluaran', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),

      // Summary cards
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: isMobile
          ? Column(children: [
              _summaryCard('Pemasukan', _totalIncome, Colors.green, Icons.trending_up_rounded, cs),
              const SizedBox(height: 8),
              _summaryCard('Pengeluaran', _totalExpense, Colors.red, Icons.trending_down_rounded, cs),
              const SizedBox(height: 8),
              _summaryCard('Saldo Bersih', _netCashflow, _netCashflow >= 0 ? Colors.blue : Colors.red, Icons.account_balance_rounded, cs),
            ])
          : Row(children: [
              Expanded(child: _summaryCard('Pemasukan', _totalIncome, Colors.green, Icons.trending_up_rounded, cs)),
              const SizedBox(width: 12),
              Expanded(child: _summaryCard('Pengeluaran', _totalExpense, Colors.red, Icons.trending_down_rounded, cs)),
              const SizedBox(width: 12),
              Expanded(child: _summaryCard('Saldo Bersih', _netCashflow, _netCashflow >= 0 ? Colors.blue : Colors.red, Icons.account_balance_rounded, cs)),
            ]),
      ),
      const SizedBox(height: 12),

      // Tabs
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          controller: _tabCtrl,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.primary,
          ),
          labelColor: cs.onPrimary,
          unselectedLabelColor: cs.onSurfaceVariant,
          tabs: const [
            Tab(text: 'Semua', height: 36),
            Tab(text: 'Pemasukan', height: 36),
            Tab(text: 'Pengeluaran', height: 36),
          ],
        ),
      ),
      const SizedBox(height: 8),

      // Content
      Expanded(
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabCtrl, children: [
              _buildEntryList(_allItems, cs),
              _buildEntryList(_incomeItems, cs),
              _buildEntryList(_expenseItems, cs),
            ]),
      ),
    ]);
  }

  // ══════════════════════════════════════════
  //  SUMMARY CARD
  // ══════════════════════════════════════════
  Widget _summaryCard(String label, double amount, Color color, IconData icon, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceBright,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(
            '${amount < 0 ? '-' : ''}${fmtPrice(amount.abs())}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ])),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ENTRY LIST
  // ══════════════════════════════════════════
  Widget _buildEntryList(List<Map<String, dynamic>> allItems, ColorScheme cs) {

    if (allItems.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.receipt_long_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
        const SizedBox(height: 8),
        Text('Belum ada data cashflow', style: TextStyle(color: cs.onSurfaceVariant)),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: allItems.length,
      itemBuilder: (_, i) {
        final item = allItems[i];
        final isAuto = item['_isAuto'] == true;
        final isIncome = item['type'] == 'income';
        final color = isIncome ? Colors.green : Colors.red;
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceBright,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isAuto ? cs.primary.withValues(alpha: 0.3) : cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            // Icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isAuto
                  ? (isIncome ? Icons.point_of_sale_rounded : Icons.inventory_rounded)
                  : (isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
                color: color,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(
                  item['category_name']?.toString() ?? '-',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: cs.onSurface),
                )),
                if (isAuto) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('AUTO', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: cs.primary)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                item['description']?.toString() ?? '',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              if (!isAuto) ...[
                const SizedBox(height: 2),
                Text(
                  '${item['date'] ?? ''} • ${item['recorded_name'] ?? ''}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                ),
              ],
            ])),
            const SizedBox(width: 8),
            // Amount + actions
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                '${isIncome ? '+' : '-'}${fmtPrice(amount)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
              ),
              if (!isAuto) ...[
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  InkWell(
                    onTap: () => _showInputDialog(editEntry: item),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit_rounded, size: 14, color: cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _deleteEntry(item),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red.shade400),
                    ),
                  ),
                ]),
              ],
            ]),
          ]),
        );
      },
    );
  }

  // ══════════════════════════════════════════
  //  INPUT DIALOG
  // ══════════════════════════════════════════
  void _showInputDialog({String? type, Map<String, dynamic>? editEntry}) {
    final isEdit = editEntry != null;
    final entryType = type ?? editEntry?['type'] ?? 'expense';
    final isIncome = entryType == 'income';
    final filteredCategories = _categories.where((c) => c['type'] == entryType).toList();

    String? selectedCategoryId = isEdit ? editEntry['category_id']?.toString() : (filteredCategories.isNotEmpty ? filteredCategories.first['id'].toString() : null);
    final amountCtrl = TextEditingController(text: isEdit ? (editEntry['amount'] as num?)?.toStringAsFixed(0) ?? '' : '');
    final descCtrl = TextEditingController(text: isEdit ? editEntry['description']?.toString() ?? '' : '');
    DateTime selectedDate = isEdit
      ? DateTime.tryParse(editEntry['date']?.toString() ?? '') ?? DateTime.now()
      : DateTime.now();

    final auth = context.read<AuthProvider>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(isIncome ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: isIncome ? Colors.green : Colors.red, size: 22),
            const SizedBox(width: 8),
            Text(isEdit ? 'Edit ${isIncome ? 'Pemasukan' : 'Pengeluaran'}' : 'Tambah ${isIncome ? 'Pemasukan' : 'Pengeluaran'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Category dropdown
              DropdownButtonFormField<String>(
                value: selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Kategori', isDense: true),
                items: filteredCategories.map((c) => DropdownMenuItem(
                  value: c['id'].toString(),
                  child: Text(c['name']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (v) => setDState(() => selectedCategoryId = v),
              ),
              const SizedBox(height: 12),

              // Amount
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Jumlah (Rp)', isDense: true, prefixText: 'Rp '),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              // Date picker
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDState(() => selectedDate = picked);
                },
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Tanggal', isDense: true, suffixIcon: Icon(Icons.calendar_month_rounded, size: 18)),
                  child: Text(_fmtDate(selectedDate), style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 12),

              // Description
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Keterangan (opsional)', isDense: true, alignLabelWithHint: true),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton.icon(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0 || selectedCategoryId == null) {
                  showAdminToast(context, '⚠️ Isi jumlah dan kategori');
                  return;
                }
                final catName = filteredCategories.firstWhere(
                  (c) => c['id'].toString() == selectedCategoryId,
                  orElse: () => <String, dynamic>{'name': '-'},
                )['name']?.toString() ?? '-';

                try {
                  final db = await LocalDb.instance;
                  if (isEdit) {
                    await db.update('cashflows', {
                      'category_id': selectedCategoryId,
                      'category_name': catName,
                      'amount': amount,
                      'description': descCtrl.text.trim(),
                      'date': _fmtDate(selectedDate),
                      'updated_at': DateTime.now().toIso8601String(),
                    }, where: 'id = ?', whereArgs: [editEntry['id']]);
                  } else {
                    await db.insert('cashflows', {
                      'id': LocalDb.generateId(),
                      'type': entryType,
                      'category_id': selectedCategoryId,
                      'category_name': catName,
                      'amount': amount,
                      'description': descCtrl.text.trim(),
                      'recorded_by': auth.user?['id']?.toString(),
                      'recorded_name': auth.userName,
                      'date': _fmtDate(selectedDate),
                    });
                  }
                  if (mounted) {
                    Navigator.pop(ctx);
                    showAdminToast(context, '✅ ${isEdit ? 'Diperbarui' : 'Tersimpan'}');
                    _loadData();
                  }
                } catch (e) {
                  showAdminToast(context, '❌ Error: $e');
                }
              },
              icon: Icon(isEdit ? Icons.save_rounded : Icons.add_rounded, size: 16),
              label: Text(isEdit ? 'Simpan' : 'Tambah'),
            ),
          ],
        );
      }),
    );
  }

  // ══════════════════════════════════════════
  //  DELETE
  // ══════════════════════════════════════════
  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Entry?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('Hapus "${entry['category_name']}" - ${fmtPrice((entry['amount'] as num?)?.toDouble() ?? 0)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final db = await LocalDb.instance;
      await db.delete('cashflows', where: 'id = ?', whereArgs: [entry['id']]);
      showAdminToast(context, '🗑️ Entry dihapus');
      _loadData();
    } catch (e) {
      showAdminToast(context, '❌ Error: $e');
    }
  }
}
