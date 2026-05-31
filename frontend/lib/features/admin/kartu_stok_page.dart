import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';

class KartuStokPage extends StatefulWidget {
  const KartuStokPage({super.key});
  @override
  State<KartuStokPage> createState() => _KartuStokPageState();
}

class _KartuStokPageState extends State<KartuStokPage> {
  List<dynamic> _data = [];
  List<dynamic> _kategoriBahan = [];
  bool _isLoading = true;
  int? _selectedKategoriId;
  late DateTimeRange _dateRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    _loadKategori();
    _loadData();
  }

  String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtDateShort(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _loadKategori() async {
    try {
      final res = await Api.get('/kategori-bahan');
      if (mounted) setState(() => _kategoriBahan = res as List);
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      String path = '/reports/kartu-stok?start_date=${_fmtDate(_dateRange.start)}&end_date=${_fmtDate(_dateRange.end)}';
      if (_selectedKategoriId != null) path += '&kategori_id=$_selectedKategoriId';
      final res = await Api.get(path);
      if (mounted) setState(() { _data = (res['data'] as List?) ?? []; _isLoading = false; });
    } catch (e) {
      if (mounted) { setState(() => _isLoading = false); showAdminToast(context, 'Error: $e'); }
    }
  }

  Future<void> _pickDateRange() async {
    final result = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime(2030, 12, 31), initialDateRange: _dateRange,
    );
    if (result != null) { setState(() => _dateRange = result); _loadData(); }
  }

  void _showOpnameDialog(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final stockCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final systemStock = (item['system_stock'] as num?)?.toDouble() ?? 0;
    final unit = item['unit']?.toString() ?? '';
    final costPrice = (item['cost_price'] as num?)?.toDouble() ?? 0;
    bool isSaving = false;

    showDialog(context: context, builder: (dialogCtx) {
      return StatefulBuilder(builder: (ctx, setDState) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 440, padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Row(children: [
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.fact_check, color: Colors.indigo.shade700, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Stock Opname', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(item['name']?.toString() ?? '', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ])),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(dialogCtx)),
              ]),
              const SizedBox(height: 20),
              // System stock info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.computer, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Stok di Sistem: ', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  Text('${_fmtNum(systemStock)} $unit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.primary)),
                ]),
              ),
              const SizedBox(height: 16),
              // Physical stock input
              TextField(controller: stockCtrl, decoration: InputDecoration(
                labelText: 'Stok Fisik Aktual', isDense: true, suffixText: unit,
                prefixIcon: const Icon(Icons.scale, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              // Live discrepancy preview
              Padding(padding: const EdgeInsets.only(top: 8), child: ListenableBuilder(
                listenable: stockCtrl,
                builder: (_, __) {
                  final physical = double.tryParse(stockCtrl.text.replaceAll(',', '.')) ?? 0;
                  if (stockCtrl.text.isEmpty) return const SizedBox.shrink();
                  final diff = physical - systemStock;
                  final loss = diff * costPrice;
                  final color = diff == 0 ? Colors.green : diff > 0 ? Colors.blue : Colors.red;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.3))),
                    child: Row(children: [
                      Icon(diff == 0 ? Icons.check_circle : diff > 0 ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        diff == 0 ? 'Stok cocok ✅' : 'Selisih: ${diff > 0 ? "+" : ""}${_fmtNum(diff)} $unit (${fmtPrice(loss)})',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                      )),
                    ]),
                  );
                },
              )),
              const SizedBox(height: 14),
              // Notes
              TextField(controller: notesCtrl, decoration: InputDecoration(
                labelText: 'Alasan Selisih (opsional)', isDense: true, hintText: 'Contoh: Basi tidak tercatat',
                prefixIcon: const Icon(Icons.notes, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ), maxLines: 2),
              const SizedBox(height: 20),
              // Actions
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Batal')),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: isSaving ? null : () async {
                    final physical = double.tryParse(stockCtrl.text.replaceAll(',', '.'));
                    if (physical == null) return;
                    setDState(() => isSaving = true);
                    try {
                      await Api.post('/inventory/opname', body: {
                        'bahan_baku_id': item['id'],
                        'actual_physical_stock': physical,
                        'notes': notesCtrl.text.trim(),
                      });
                      if (mounted) { Navigator.pop(dialogCtx); showAdminToast(context, '✅ Opname berhasil disimpan'); _loadData(); }
                    } catch (e) {
                      if (mounted) { setDState(() => isSaving = false); showAdminToast(context, '❌ Error: $e'); }
                    }
                  },
                  icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text('Simpan Opname', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ]),
            ]),
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    // Summary totals
    double sumWasteValue = 0, sumRestockValue = 0;
    for (final d in _data) {
      sumWasteValue += (d['waste_value'] as num?)?.toDouble() ?? 0;
      sumRestockValue += (d['restock_value'] as num?)?.toDouble() ?? 0;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header: Date Range + Filters ──
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(Icons.date_range, size: 16),
          label: Text('${_fmtDateShort(_dateRange.start)} — ${_fmtDateShort(_dateRange.end)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        // Summary chips
        _summaryChip(cs, '📦 Restock', fmtPrice(sumRestockValue), Colors.green),
        _summaryChip(cs, '🗑️ Waste', fmtPrice(sumWasteValue), Colors.red),
        _summaryChip(cs, '${_data.length} bahan', null, null),
      ]),
      const SizedBox(height: 8),
      // ── Category Filter Chips ──
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
        Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(
          label: const Text('Semua'), selected: _selectedKategoriId == null,
          onSelected: (_) { setState(() => _selectedKategoriId = null); _loadData(); },
        )),
        ..._kategoriBahan.map((k) {
          final kId = (k['id'] as num).toInt();
          return Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(
            label: Text(k['name']?.toString() ?? ''), selected: _selectedKategoriId == kId,
            onSelected: (_) { setState(() => _selectedKategoriId = _selectedKategoriId == kId ? null : kId); _loadData(); },
          ));
        }),
      ])),
      const SizedBox(height: 12),
      // ── Body ──
      Expanded(child: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _data.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.fact_check_outlined, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('Belum ada data ledger', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
            ]))
          : Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: isMobile ? _buildMobileList(cs) : _buildDesktopTable(cs),
            )),
      ),
    ]);
  }

  Widget _summaryChip(ColorScheme cs, String label, String? value, Color? color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: (color ?? cs.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color ?? cs.onSurfaceVariant)),
        if (value != null) ...[const SizedBox(width: 4), Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color ?? cs.primary))],
      ]),
    );
  }

  // ── Desktop: DataTable ──
  Widget _buildDesktopTable(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: ListView(children: [
        DataTable(
          headingRowColor: WidgetStatePropertyAll(cs.surfaceContainer),
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Bahan', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Masuk', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Terjual', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Terbuang', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Selisih', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Sisa Sistem', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _data.map((d) {
            final unit = d['unit']?.toString() ?? '';
            final totalIn = (d['total_in'] as num?)?.toDouble() ?? 0;
            final totalOut = (d['total_out'] as num?)?.toDouble() ?? 0;
            final totalWaste = (d['total_waste'] as num?)?.toDouble() ?? 0;
            final totalAdj = (d['total_adjustment'] as num?)?.toDouble() ?? 0;
            final sysStock = (d['system_stock'] as num?)?.toDouble() ?? 0;

            return DataRow(cells: [
              DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(d['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${d['kategori_name'] ?? ''} • $unit', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ])),
              DataCell(Text(totalIn > 0 ? '+${_fmtNum(totalIn)}' : '-', style: TextStyle(color: totalIn > 0 ? Colors.green.shade700 : cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
              DataCell(Text(totalOut > 0 ? '-${_fmtNum(totalOut)}' : '-', style: TextStyle(color: totalOut > 0 ? Colors.orange.shade700 : cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
              DataCell(Text(totalWaste > 0 ? '-${_fmtNum(totalWaste)}' : '-', style: TextStyle(color: totalWaste > 0 ? Colors.red.shade700 : cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
              DataCell(Text(totalAdj != 0 ? '${totalAdj > 0 ? "+" : ""}${_fmtNum(totalAdj)}' : '-', style: TextStyle(color: totalAdj > 0 ? Colors.blue : totalAdj < 0 ? Colors.red : cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
              DataCell(Text('${_fmtNum(sysStock)} $unit', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary))),
              DataCell(SizedBox(width: 100, child: FilledButton.tonalIcon(
                onPressed: () => _showOpnameDialog(Map<String, dynamic>.from(d)),
                icon: const Icon(Icons.fact_check, size: 14),
                label: const Text('Opname', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ))),
            ]);
          }).toList(),
        ),
      ])),
    );
  }

  // ── Mobile: Card List ──
  Widget _buildMobileList(ColorScheme cs) {
    return ListView.separated(
      itemCount: _data.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = _data[i];
        final unit = d['unit']?.toString() ?? '';
        final totalIn = (d['total_in'] as num?)?.toDouble() ?? 0;
        final totalOut = (d['total_out'] as num?)?.toDouble() ?? 0;
        final totalWaste = (d['total_waste'] as num?)?.toDouble() ?? 0;
        final totalAdj = (d['total_adjustment'] as num?)?.toDouble() ?? 0;
        final sysStock = (d['system_stock'] as num?)?.toDouble() ?? 0;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('${d['kategori_name'] ?? ''} • $unit', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Text('${_fmtNum(sysStock)} $unit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary)),
              ),
            ]),
            const SizedBox(height: 8),
            // Metrics row
            Wrap(spacing: 8, runSpacing: 4, children: [
              _metricChip('Masuk', totalIn > 0 ? '+${_fmtNum(totalIn)}' : '-', Colors.green),
              _metricChip('Terjual', totalOut > 0 ? '-${_fmtNum(totalOut)}' : '-', Colors.orange),
              _metricChip('Terbuang', totalWaste > 0 ? '-${_fmtNum(totalWaste)}' : '-', Colors.red),
              if (totalAdj != 0) _metricChip('Selisih', '${totalAdj > 0 ? "+" : ""}${_fmtNum(totalAdj)}', Colors.blue),
            ]),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, height: 32, child: FilledButton.tonalIcon(
              onPressed: () => _showOpnameDialog(Map<String, dynamic>.from(d)),
              icon: const Icon(Icons.fact_check, size: 14),
              label: const Text('Opname (Sesuaikan Fisik)', style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            )),
          ]),
        );
      },
    );
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text('$label: $value', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.shade700)),
    );
  }

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(2);
  }
}

extension _ColorShade on Color {
  Color get shade700 => this;
}
