import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});
  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  List<dynamic> transactions = [];
  int total = 0;
  double totalSalesAmount = 0;
  
  String activeTab = 'day'; // 'day', 'month', 'year'
  
  // Day filter — date range
  late DateTimeRange _dateRange;
  // Month filter
  late int _selectedMonth;
  late int _selectedYear;
  // Year filter
  late int _selectedYearOnly;
  
  int? expandedId;
  List<dynamic> expandedDetails = [];
  
  // Monthly/Yearly summary
  Map<String, dynamic> _periodSummary = {};
  List<dynamic> _periodBreakdown = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(start: now, end: now);
    _selectedMonth = now.month;
    _selectedYear = now.year;
    _selectedYearOnly = now.year;
    _loadData();
  }

  static double _safeNum(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadData() async {
    try {
      if (activeTab == 'day') {
        final startStr = _fmtDate(_dateRange.start);
        final endStr = _fmtDate(_dateRange.end);
        final res = await Api.get('/transactions?date_start=$startStr&date_end=$endStr&limit=999');
        final data = (res['data'] is List) ? res['data'] as List : [];
        double sales = 0;
        for (var tx in data) { sales += _safeNum(tx['total_amount']); }
        if (mounted) {
          setState(() {
          transactions = data;
          total = data.length;
          totalSalesAmount = sales;
        });
        }
      } else if (activeTab == 'month') {
        final ms = _selectedMonth.toString().padLeft(2, '0');
        final res = await Api.get('/reports/monthly?month=$ms&year=$_selectedYear');
        if (mounted) {
          setState(() {
          _periodSummary = res['summary'] ?? {};
          _periodBreakdown = res['daily'] ?? [];
        });
        }
      } else {
        // Year: aggregate all months
        Map<String, dynamic> combinedSummary = {'total_transactions': 0, 'total_sales': 0.0};
        List<dynamic> combinedDaily = [];
        for (int m = 1; m <= 12; m++) {
          final ms = m.toString().padLeft(2, '0');
          try {
            final r = await Api.get('/reports/monthly?month=$ms&year=$_selectedYearOnly');
            final summ = r['summary'] ?? {};
            final txCount = _safeNum(summ['total_transactions']).round();
            if (txCount > 0) {
              combinedSummary['total_transactions'] = (combinedSummary['total_transactions'] as num) + txCount;
              combinedSummary['total_sales'] = (combinedSummary['total_sales'] as num) + _safeNum(summ['total_sales']);
              combinedDaily.add({
                'date': '$_selectedYearOnly-$ms',
                'count': txCount,
                'sales': _safeNum(summ['total_sales']),
              });
            }
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
          _periodSummary = combinedSummary;
          _periodBreakdown = combinedDaily;
        });
        }
      }
    } catch (_) {}
  }

  Future<void> _showDetailDialog(Map<String, dynamic> tx) async {
    try {
      final res = await Api.get('/transactions/${tx['id']}');
      final details = res['details'] as List? ?? [];
      
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;
      
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Detail Transaksi #${tx['id']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Waktu', style: TextStyle(color: cs.onSurfaceVariant)),
                            Text('${tx['created_at']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Kasir', style: TextStyle(color: cs.onSurfaceVariant)),
                            Text(tx['cashier_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Daftar Produk', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface)),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: details.length,
                      separatorBuilder: (_, _) => Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
                      itemBuilder: (ctx, i) {
                        final d = details[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d['product_name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text('${d['quantity']} ${d['unit_used']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Text(fmtPrice(d['subtotal']), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: cs.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          if (tx['discount_total'] != null && tx['discount_total'] > 0) ...[
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('Diskon', style: TextStyle(color: cs.onSurfaceVariant)),
                              Text('-${fmtPrice(tx['discount_total'])}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ]),
                            const SizedBox(height: 8),
                          ],
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Total Akhir', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.bold)),
                            Text(fmtPrice(tx['total_amount']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: cs.primary)),
                          ]),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Bayar', style: TextStyle(color: cs.onSurfaceVariant)),
                            Text(fmtPrice(tx['paid_amount']), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text('Kembali', style: TextStyle(color: cs.onSurfaceVariant)),
                            Text(fmtPrice(tx['change_amount']), style: TextStyle(fontWeight: FontWeight.bold, color: cs.secondary)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      );
    } catch (e) {
      if (mounted) showToast(context, 'Gagal memuat detail transaksi');
    }
  }

  void _switchTab(String tab) {
    setState(() { activeTab = tab; expandedId = null; });
    _loadData();
  }

  Future<void> _pickDay() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (result != null) {
      setState(() => _dateRange = result);
      _loadData();
    }
  }

  void _pickMonth() {
    final cs = Theme.of(context).colorScheme;
    showDialog(context: context, builder: (_) {
      int tempMonth = _selectedMonth;
      int tempYear = _selectedYear;
      return StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: const Text('Pilih Bulan & Tahun'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setDialogState(() => tempYear--)),
              Expanded(child: Text('$tempYear', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setDialogState(() => tempYear++)),
            ]),
            const SizedBox(height: 12),
            GridView.count(crossAxisCount: 4, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 6, crossAxisSpacing: 6,
              children: List.generate(12, (i) {
                final m = i + 1;
                final isSelected = m == tempMonth;
                final names = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
                return InkWell(onTap: () => setDialogState(() => tempMonth = m),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(names[i], style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isSelected ? cs.onPrimary : cs.onSurface)),
                  ));
              }),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(onPressed: () {
              Navigator.pop(ctx);
              setState(() { _selectedMonth = tempMonth; _selectedYear = tempYear; });
              _loadData();
            }, child: const Text('Terapkan')),
          ],
        );
      });
    });
  }

  void _pickYear() {
    showDialog(context: context, builder: (_) {
      int tempYear = _selectedYearOnly;
      return StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: const Text('Pilih Tahun'),
          content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setDialogState(() => tempYear--)),
            Text('$tempYear', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setDialogState(() => tempYear++)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(onPressed: () {
              Navigator.pop(ctx);
              setState(() => _selectedYearOnly = tempYear);
              _loadData();
            }, child: const Text('Terapkan')),
          ],
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final months = ['','Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Tab Bar + Date Picker
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Container(
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
          padding: const EdgeInsets.all(4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _tabBtn('Harian', 'day', cs),
            _tabBtn('Bulanan', 'month', cs),
            _tabBtn('Tahunan', 'year', cs),
          ]),
        ),
        // Smart date picker button
        if (activeTab == 'day')
          FilledButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(_dateRange.start == _dateRange.end
              ? '${_dateRange.start.day}/${_dateRange.start.month}/${_dateRange.start.year}'
              : '${_dateRange.start.day}/${_dateRange.start.month} — ${_dateRange.end.day}/${_dateRange.end.month}/${_dateRange.end.year}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )
        else if (activeTab == 'month')
          FilledButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month, size: 16),
            label: Text('${months[_selectedMonth]} $_selectedYear', style: const TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          )
        else
          FilledButton.icon(
            onPressed: _pickYear,
            icon: const Icon(Icons.date_range, size: 16),
            label: Text('$_selectedYearOnly', style: const TextStyle(fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
      ]),
      const SizedBox(height: 16),

      // DAILY view
      if (activeTab == 'day') ...[
        // Summary bar
        Wrap(spacing: 12, runSpacing: 8, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: cs.secondaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
            child: Text('$total transaksi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.secondary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Total: ', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              Text(fmtPrice(totalSalesAmount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        if (transactions.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Tidak ada transaksi', style: TextStyle(color: cs.onSurfaceVariant))))
        else
          Expanded(child: isMobile ? _buildDailyMobileList(cs) : _buildDailyDesktopTable(cs)),
      ],

      // MONTHLY / YEARLY view
      if (activeTab != 'day') ...[
        Row(children: [
          Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TOTAL PENJUALAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                child: Text(fmtPrice(_periodSummary['total_sales'] ?? 0), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.primary))),
            ]))),
          const SizedBox(width: 12),
          Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.secondaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('JUMLAH TRANSAKSI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('${_periodSummary['total_transactions'] ?? 0}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.secondary)),
            ]))),
        ]),
        const SizedBox(height: 16),
        if (_periodBreakdown.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Tidak ada data', style: TextStyle(color: cs.onSurfaceVariant))))
        else
          Expanded(child: _buildPeriodTable(cs)),
      ],
    ]);
  }

  Widget _tabBtn(String label, String val, ColorScheme cs) {
    final active = activeTab == val;
    return InkWell(onTap: () => _switchTab(val), borderRadius: BorderRadius.circular(8),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: active ? cs.primary : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? cs.onPrimary : cs.onSurfaceVariant))));
  }

  // --- Period Table (Monthly/Yearly breakdown) ---
  Widget _buildPeriodTable(ColorScheme cs) {
    return Container(decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: ListView(children: [
        DataTable(
          headingRowColor: WidgetStatePropertyAll(cs.surfaceContainer),
          columns: [
            DataColumn(label: Text(activeTab == 'month' ? 'Tanggal' : 'Bulan', style: const TextStyle(fontWeight: FontWeight.bold))),
            const DataColumn(label: Text('Transaksi', style: TextStyle(fontWeight: FontWeight.bold))),
            const DataColumn(label: Text('Penjualan', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _periodBreakdown.map((d) => DataRow(cells: [
            DataCell(Text(d['date']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text('${d['count'] ?? 0}')),
            DataCell(Text(fmtPrice(d['sales'] ?? 0), style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary))),
          ])).toList(),
        )
      ])));
  }

  // --- Daily Desktop Table ---
  Widget _buildDailyDesktopTable(ColorScheme cs) {
    return Container(decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: ListView(children: [
        DataTable(
          headingRowColor: WidgetStatePropertyAll(cs.surfaceContainer),
          columns: const [
            DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Waktu')),
            DataColumn(label: Text('Kasir')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Diskon')),
            DataColumn(label: Text('Bayar')),
            DataColumn(label: Text('Kembali')),
          ],
          rows: _buildDailyRows(cs),
        )
      ])));
  }

  List<DataRow> _buildDailyRows(ColorScheme cs) {
    List<DataRow> rows = [];
    for (var tx in transactions) {
      final ca = (tx['created_at'] ?? '').toString();
      final time = ca.contains(' ') ? ca.split(' ')[1] : ca;
      rows.add(DataRow(
        color: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.hovered) ? cs.surfaceContainer.withValues(alpha: 0.3) : null),
        cells: [
          DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text('#${tx['id']}', style: TextStyle(color: cs.onSurfaceVariant, fontFamily: 'monospace')))),
          DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(time))),
          DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(tx['cashier_name'] ?? '-'))),
          DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(fmtPrice(tx['total_amount']), style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)))),
          DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(tx['discount_total'] != null && tx['discount_total'] > 0 ? fmtPrice(tx['discount_total']) : '-', style: const TextStyle(color: Colors.green, fontSize: 13)),
            if (tx['discount_total'] != null && tx['discount_total'] > 0)
              Text('Oleh: ${tx['discount_by'] == 'system' ? 'Sistem' : tx['discount_by'] == 'stacked' ? 'Sistem+Kasir' : tx['cashier_name']}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]))),
          DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(fmtPrice(tx['paid_amount'])))),
          DataCell(InkWell(onTap: () => _showDetailDialog(tx), child: Text(fmtPrice(tx['change_amount']), style: TextStyle(color: cs.secondary)))),
        ]
      ));
    }
    return rows;
  }

  // --- Daily Mobile List ---
  Widget _buildDailyMobileList(ColorScheme cs) {
    return ListView.builder(itemCount: transactions.length, itemBuilder: (ctx, i) {
      final tx = transactions[i];
      final ca = (tx['created_at'] ?? '').toString();
      final time = ca.contains(' ') ? ca.split(' ')[1] : ca;

      return Container(margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
        child: InkWell(onTap: () => _showDetailDialog(tx), borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('#${tx['id']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontFamily: 'monospace')),
            Text(time, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(tx['cashier_name'] ?? '-', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Text(fmtPrice(tx['total_amount']), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
          ]),
        ]))));
    });
  }
}
