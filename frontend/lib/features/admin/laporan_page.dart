import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});
  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // === Shared date state ===
  late DateTimeRange _dateRange;

  // === Penjualan data ===
  List<dynamic> transactions = [];
  double totalSalesAmount = 0;

  // === Refund data ===
  List<dynamic> refundItems = [];

  // === Waste data ===
  List<dynamic> wasteItems = [];

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() { if (!_tabCtrl.indexIsChanging) _loadData(); });
    final now = DateTime.now();
    _dateRange = DateTimeRange(start: now, end: now);
    _loadData();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  static double _safeNum(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtDateDisplay(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    final startStr = _fmtDate(_dateRange.start);
    final endStr = _fmtDate(_dateRange.end);
    try {
      switch (_tabCtrl.index) {
        case 0: // Penjualan
          final res = await Api.get('/transactions?date_start=$startStr&date_end=$endStr&limit=999');
          final data = (res['data'] is List) ? res['data'] as List : [];
          double sales = 0;
          for (var tx in data) { sales += _safeNum(tx['total_amount']); }
          if (mounted) setState(() { transactions = data; totalSalesAmount = sales; });
          break;
        case 1: // Refund
          final res = await Api.get('/reports/refund-history?date_start=$startStr&date_end=$endStr');
          if (mounted) setState(() => refundItems = (res is List) ? res : []);
          break;
        case 2: // Waste
          final res = await Api.get('/reports/waste-history?date_start=$startStr&date_end=$endStr');
          if (mounted) setState(() => wasteItems = (res is List) ? res : []);
          break;
      }
    } catch (_) {}
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _pickDate() async {
    final result = await showDateRangePicker(
      context: context, firstDate: DateTime(2024), lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (result != null) { setState(() => _dateRange = result); _loadData(); }
  }

  // ── Detail Transaksi Dialog ──
  Future<void> _showDetailDialog(Map<String, dynamic> tx) async {
    try {
      final res = await Api.get('/transactions/${tx['id']}');
      var txData = res['transaction'] as Map<String, dynamic>? ?? tx;
      var details = res['details'] as List? ?? [];
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;

      showDialog(context: context, builder: (ctx) {
        final status = txData['status']?.toString() ?? 'completed';
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 500, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
            child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Row(children: [
                Expanded(child: Text('Transaksi #${txData['id']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                _statusBadge(status),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
              ]),
              const Divider(height: 20),
              // Info
              _infoRow('Waktu', '${txData['created_at']}', cs),
              _infoRow('Kasir', txData['cashier_name'] ?? '-', cs),
              _infoRow('Pembayaran', (txData['payment_method'] ?? '-').toString().toUpperCase(), cs),
              const SizedBox(height: 12),
              // Items
              Flexible(child: ListView.separated(
                shrinkWrap: true, itemCount: details.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                itemBuilder: (_, i) {
                  final d = details[i];
                  final qty = _safeNum(d['quantity']);
                  final refQty = _safeNum(d['refunded_qty']);
                  final price = _safeNum(d['sold_price']);
                  final disc = _safeNum(d['discount_percent']);
                  final effectivePrice = price * (1 - disc / 100);
                  final sub = effectivePrice * (qty - refQty);
                  final fullyRefunded = refQty >= qty;
                  return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d['product_name']?.toString() ?? '-', style: TextStyle(fontWeight: FontWeight.w600, decoration: fullyRefunded ? TextDecoration.lineThrough : null, color: fullyRefunded ? Colors.grey : null)),
                      Text('${qty.round()} × ${fmtPrice(price)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      if (refQty > 0) Text('Refund: ${refQty.round()} pcs', style: TextStyle(fontSize: 11, color: Colors.red.shade600, fontWeight: FontWeight.bold)),
                    ])),
                    Text(fmtPrice(sub), style: TextStyle(fontWeight: FontWeight.bold, color: fullyRefunded ? Colors.grey : cs.primary)),
                  ]));
                },
              )),
              const Divider(height: 20),
              // Totals
              _infoRow('Total', fmtPrice(txData['total_amount']), cs, bold: true, color: status == 'voided' ? cs.error : cs.primary),
              if (_safeNum(txData['discount_total']) > 0)
                _infoRow('Diskon', '-${fmtPrice(txData['discount_total'])}', cs, color: Colors.green),
              _infoRow('Bayar', fmtPrice(txData['paid_amount']), cs),
              _infoRow('Kembali', fmtPrice(txData['change_amount']), cs, color: cs.secondary),
            ])),
          ),
        );
      });
    } catch (_) { if (mounted) showToast(context, 'Gagal memuat detail'); }
  }

  Widget _statusBadge(String status) {
    if (status == 'voided') return _badge('VOID', Colors.red);
    if (status == 'partial_refund') return _badge('REFUND', Colors.orange);
    return const SizedBox.shrink();
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
  );

  Widget _infoRow(String label, String value, ColorScheme cs, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      // Top bar: Tabs + Date picker
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
        Expanded(child: TabBar(
          controller: _tabCtrl,
          labelColor: cs.primary, unselectedLabelColor: cs.onSurfaceVariant,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [Tab(text: 'Penjualan'), Tab(text: 'Refund'), Tab(text: 'Waste')],
        )),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.date_range, size: 16),
          label: Text(
            _dateRange.start == _dateRange.end
              ? _fmtDateDisplay(_dateRange.start)
              : '${_fmtDateDisplay(_dateRange.start)} — ${_fmtDateDisplay(_dateRange.end)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        ),
      ])),
      // Content
      Expanded(child: isLoading
        ? const Center(child: CircularProgressIndicator())
        : TabBarView(controller: _tabCtrl, physics: const NeverScrollableScrollPhysics(), children: [
            _buildPenjualanTab(cs),
            _buildRefundTab(cs),
            _buildWasteTab(cs),
          ]),
      ),
    ]);
  }

  // ══════════════════════════════════════════
  // TAB 1: PENJUALAN
  // ══════════════════════════════════════════
  Widget _buildPenjualanTab(ColorScheme cs) {
    if (transactions.isEmpty) return _emptyState('Tidak ada transaksi', Icons.receipt_long);
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    return Column(children: [
      // Summary chips
      Row(children: [
        _summaryChip('${transactions.length} transaksi', cs.secondaryContainer, cs.secondary),
        const SizedBox(width: 8),
        _summaryChip('Total: ${fmtPrice(totalSalesAmount)}', cs.primaryContainer, cs.primary),
      ]),
      const SizedBox(height: 12),
      Expanded(child: isMobile ? _penjualanMobileList(cs) : _penjualanDesktopTable(cs)),
    ]);
  }

  Widget _summaryChip(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: bg.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
  );

  Widget _penjualanDesktopTable(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: ListView(children: [
        DataTable(
          headingRowColor: WidgetStatePropertyAll(cs.surfaceContainer),
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Waktu', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Kasir', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Total', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Metode', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: transactions.map((tx) {
            final ca = (tx['created_at'] ?? '').toString();
            final time = ca.length > 10 ? ca.substring(11, 16) : ca;
            final status = tx['status']?.toString() ?? 'completed';
            return DataRow(
              color: WidgetStateProperty.resolveWith((s) {
                if (status == 'voided') return Colors.red.shade50.withValues(alpha: 0.3);
                if (status == 'partial_refund') return Colors.orange.shade50.withValues(alpha: 0.3);
                return null;
              }),
              cells: [
                DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text('#${tx['id']}', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: cs.onSurfaceVariant)))),
                DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(time))),
                DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(tx['cashier_name'] ?? '-'))),
                DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(fmtPrice(tx['total_amount']), style: TextStyle(fontWeight: FontWeight.bold, color: status == 'voided' ? cs.error : cs.primary)))),
                DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text((tx['payment_method'] ?? '-').toString().toUpperCase(), style: const TextStyle(fontSize: 12)))),
                DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: _statusBadge(status))),
              ],
            );
          }).toList(),
        ),
      ])),
    );
  }

  Widget _penjualanMobileList(ColorScheme cs) {
    return ListView.builder(itemCount: transactions.length, itemBuilder: (_, i) {
      final tx = transactions[i];
      final ca = (tx['created_at'] ?? '').toString();
      final time = ca.length > 10 ? ca.substring(11, 16) : ca;
      final status = tx['status']?.toString() ?? 'completed';
      return Card(
        elevation: 0, margin: const EdgeInsets.only(bottom: 6),
        color: status == 'voided' ? Colors.red.shade50 : status == 'partial_refund' ? Colors.orange.shade50 : cs.surfaceBright,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
        child: InkWell(onTap: () => _showDetailDialog(tx), borderRadius: BorderRadius.circular(12),
          child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('#${tx['id']}', style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: cs.onSurfaceVariant)),
                const SizedBox(width: 6),
                _statusBadge(status),
              ]),
              const SizedBox(height: 4),
              Text(tx['cashier_name'] ?? '-', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtPrice(tx['total_amount']), style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
              Text(time, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
          ]))),
      );
    });
  }

  // ══════════════════════════════════════════
  // TAB 2: REFUND
  // ══════════════════════════════════════════
  Widget _buildRefundTab(ColorScheme cs) {
    if (refundItems.isEmpty) return _emptyState('Tidak ada refund', Icons.undo);

    // Group by tx_id
    final Map<String, List<dynamic>> grouped = {};
    for (var item in refundItems) {
      final txId = item['tx_id']?.toString() ?? '?';
      grouped.putIfAbsent(txId, () => []).add(item);
    }

    final totalRefundAmount = refundItems.fold<double>(0.0, (sum, item) {
      final price = _safeNum(item['sold_price']);
      final disc = _safeNum(item['discount_percent']);
      final rQty = _safeNum(item['refunded_qty']);
      return sum + (price * (1 - disc / 100) * rQty);
    });

    return Column(children: [
      Row(children: [
        _summaryChip('${grouped.length} transaksi refund', Colors.orange.shade100, Colors.orange.shade800),
        const SizedBox(width: 8),
        _summaryChip('Total: -${fmtPrice(totalRefundAmount)}', Colors.red.shade100, Colors.red.shade700),
      ]),
      const SizedBox(height: 12),
      Expanded(child: ListView.builder(
        itemCount: grouped.keys.length,
        itemBuilder: (_, i) {
          final txId = grouped.keys.elementAt(i);
          final items = grouped[txId]!;
          final first = items.first;
          final kasir = first['cashier_name']?.toString() ?? '-';
          final status = first['status']?.toString() ?? '';
          final updatedAt = first['updated_at']?.toString() ?? '';
          final time = updatedAt.length > 10 ? updatedAt.substring(11, 16) : updatedAt;

          return Card(
            elevation: 0, margin: const EdgeInsets.only(bottom: 8),
            color: cs.surfaceBright,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.orange.shade200)),
            child: ExpansionTile(
              shape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.undo, size: 18, color: Colors.orange.shade700),
              ),
              title: Row(children: [
                Expanded(child: Text('TX #$txId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                _statusBadge(status),
              ]),
              subtitle: Text('Kasir: $kasir · $time', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              children: items.map((item) {
                final price = _safeNum(item['sold_price']);
                final disc = _safeNum(item['discount_percent']);
                final rQty = _safeNum(item['refunded_qty']);
                final refundVal = price * (1 - disc / 100) * rQty;
                return ListTile(
                  dense: true,
                  title: Text(item['product_name']?.toString() ?? '-', style: const TextStyle(fontSize: 13)),
                  subtitle: Text('Qty refund: ${rQty.round()} × ${fmtPrice(price)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  trailing: Text('-${fmtPrice(refundVal)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 13)),
                );
              }).toList(),
            ),
          );
        },
      )),
    ]);
  }

  // ══════════════════════════════════════════
  // TAB 3: WASTE
  // ══════════════════════════════════════════
  Widget _buildWasteTab(ColorScheme cs) {
    if (wasteItems.isEmpty) return _emptyState('Tidak ada waste', Icons.delete_outline);

    final totalLoss = wasteItems.fold<double>(0.0, (sum, w) => sum + _safeNum(w['financial_value']).abs());

    // Group product waste by product name + timestamp (same batch)
    // Raw material waste stays individual
    final List<Map<String, dynamic>> groupedItems = [];
    final Map<String, Map<String, dynamic>> productGroups = {};

    for (final w in wasteItems) {
      final notes = w['notes']?.toString() ?? '';
      final isProductWaste = notes.startsWith('Produk Gagal:');

      if (isProductWaste) {
        // Parse product name from notes
        final content = notes.replaceFirst('Produk Gagal: ', '');
        final parts = content.split(' - ');
        final productName = parts.isNotEmpty ? parts[0].trim() : 'Unknown';
        final timestamp = w['timestamp']?.toString() ?? '';
        // Group key: productName + timestamp (minute precision)
        final tsKey = timestamp.length > 16 ? timestamp.substring(0, 16) : timestamp;
        final groupKey = '$productName|$tsKey';

        if (!productGroups.containsKey(groupKey)) {
          // Parse reason
          String reason = '';
          if (parts.length > 1) {
            reason = parts.sublist(1).join(' - ').replaceAll(RegExp(r'\[.*?\]'), '').trim();
          }
          // Parse reporter
          String reporter = '-';
          final byMatch = RegExp(r'\[(?:Oleh|Di-refund oleh|Dilaporkan oleh)[:\s]*([^\]]+)\]', caseSensitive: false).firstMatch(notes);
          if (byMatch != null) reporter = byMatch.group(1)!.trim();

          productGroups[groupKey] = {
            'type': 'product',
            'product_name': productName,
            'reason': reason,
            'reporter': reporter,
            'timestamp': timestamp,
            'total_loss': 0.0,
            'ingredients': <Map<String, dynamic>>[],
          };
        }

        productGroups[groupKey]!['total_loss'] =
            (productGroups[groupKey]!['total_loss'] as double) + _safeNum(w['financial_value']).abs();
        (productGroups[groupKey]!['ingredients'] as List).add({
          'name': w['bahan_name']?.toString() ?? '-',
          'qty': _safeNum(w['qty_change']).abs(),
          'unit': w['bahan_unit']?.toString() ?? '',
          'loss': _safeNum(w['financial_value']).abs(),
        });
      } else {
        // Raw material — individual entry
        String reason = '';
        final isRaw = notes.startsWith('Bahan Rusak:');
        if (isRaw) {
          final content = notes.replaceFirst('Bahan Rusak: ', '');
          final parts = content.split(' - ');
          if (parts.length > 1) {
            reason = parts.sublist(1).join(' - ').replaceAll(RegExp(r'\[.*?\]'), '').trim();
          }
        }
        String reporter = '-';
        final byMatch = RegExp(r'\[(?:Oleh|Di-refund oleh|Dilaporkan oleh)[:\s]*([^\]]+)\]', caseSensitive: false).firstMatch(notes);
        if (byMatch != null) reporter = byMatch.group(1)!.trim();

        groupedItems.add({
          'type': 'raw',
          'bahan_name': w['bahan_name']?.toString() ?? '-',
          'qty': _safeNum(w['qty_change']).abs(),
          'unit': w['bahan_unit']?.toString() ?? '',
          'loss': _safeNum(w['financial_value']).abs(),
          'reason': reason,
          'reporter': reporter,
          'timestamp': w['timestamp']?.toString() ?? '',
        });
      }
    }

    // Add grouped product items
    final sortedProductGroups = productGroups.values.toList()
      ..sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
    groupedItems.insertAll(0, sortedProductGroups);

    return Column(children: [
      Row(children: [
        _summaryChip('${wasteItems.length} entri waste', Colors.red.shade100, Colors.red.shade800),
        const SizedBox(width: 8),
        _summaryChip('Kerugian: ${fmtPrice(totalLoss)}', Colors.red.shade100, Colors.red.shade700),
      ]),
      const SizedBox(height: 12),
      Expanded(child: ListView.builder(
        itemCount: groupedItems.length,
        itemBuilder: (_, i) {
          final item = groupedItems[i];
          final isProduct = item['type'] == 'product';
          final timestamp = item['timestamp']?.toString() ?? '';
          final time = timestamp.length > 10 ? timestamp.substring(11, 16) : '';
          final date = timestamp.length >= 10 ? timestamp.substring(0, 10) : '';
          final reason = item['reason']?.toString() ?? '';
          final reporter = item['reporter']?.toString() ?? '-';

          if (isProduct) {
            // Grouped product waste card
            final ingredients = item['ingredients'] as List<Map<String, dynamic>>;
            final totalLoss = item['total_loss'] as double;

            return Card(
              elevation: 0, margin: const EdgeInsets.only(bottom: 8),
              color: cs.surfaceBright,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.orange.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.restaurant, size: 20, color: Colors.orange.shade700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
                        child: Text('Produk Jadi', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                      ),
                      const SizedBox(height: 4),
                      Text(item['product_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ])),
                    Text('-${fmtPrice(totalLoss)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red.shade700)),
                  ]),
                  const SizedBox(height: 8),
                  // Ingredient list
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('📦 Bahan terpakai:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          ...ingredients.map((ing) {
                            final qtyStr = ing['qty'] == (ing['qty'] as double).roundToDouble()
                                ? (ing['qty'] as double).round().toString()
                                : (ing['qty'] as double).toStringAsFixed(2);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(children: [
                                Text('• ${ing['name']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                const Spacer(),
                                Text('$qtyStr ${ing['unit']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                                const SizedBox(width: 8),
                                Text('-${fmtPrice(ing['loss'] as double)}', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                              ]),
                            );
                          }),
                        ]),
                      ),
                      if (reason.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Alasan: $reason', style: TextStyle(fontSize: 12, color: Colors.red.shade600))),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${reporter != '-' ? 'Oleh: $reporter' : ''}${reporter != '-' && time.isNotEmpty ? ' · ' : ''}$date $time',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            );
          } else {
            // Raw material waste card
            final qtyVal = item['qty'] as double;
            final qtyStr = qtyVal == qtyVal.roundToDouble() ? qtyVal.round().toString() : qtyVal.toStringAsFixed(2);

            return Card(
              elevation: 0, margin: const EdgeInsets.only(bottom: 8),
              color: cs.surfaceBright,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.red.shade200)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.science_outlined, size: 20, color: Colors.red.shade700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                        child: Text('Bahan Mentah', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                      ),
                      const SizedBox(height: 4),
                      Text(item['bahan_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ])),
                    Text('-${fmtPrice(item['loss'] as double)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red.shade700)),
                  ]),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$qtyStr ${item['unit']} terbuang', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      if (reason.isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 2), child: Text('Alasan: $reason', style: TextStyle(fontSize: 12, color: Colors.red.shade600))),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${reporter != '-' ? 'Oleh: $reporter' : ''}${reporter != '-' && time.isNotEmpty ? ' · ' : ''}$date $time',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            );
          }
        },
      )),
    ]);
  }

  Widget _emptyState(String msg, IconData icon) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
    const SizedBox(height: 12),
    Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]));
}
