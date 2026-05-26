import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Map<String, dynamic> summary = {'total_transactions': 0, 'total_sales': 0, 'total_profit': 0, 'avg_transaction': 0};
  List<dynamic> lowStock = [];
  List<dynamic> topProducts = [];
  List<dynamic> chartData = [];
  // Daily recap data
  int _dailyTxCount = 0;
  double _dailySales = 0;
  int _dailyItemsSold = 0;
  double _dailyProfit = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        Api.get('/transactions/today'),
        Api.get('/inventory/low-stock'),
        Api.get('/reports/products?days=7'),
        Api.get('/reports/chart28'),
      ]);

      // Daily recap from today's transactions
      int txCount = 0;
      double sales = 0;
      int itemsSold = 0;
      double profit = 0;
      try {
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
        final txRes = await Api.get('/transactions?date=$todayStr&limit=999');
        final txList = (txRes['data'] is List) ? txRes['data'] as List : [];
        txCount = txList.length;
        for (var tx in txList) {
          sales += _safeNum(tx['total_amount']);
          final txItems = (tx['items'] is List) ? tx['items'] as List : [];
          for (var item in txItems) {
            itemsSold += _safeNum(item['quantity']).round();
          }
        }
        // Use the pre-calculated profit from the /transactions/today endpoint
        profit = _safeNum(summary['total_profit']);
      } catch (_) {}

      setState(() {
        summary = results[0];
        lowStock = results[1] as List;
        topProducts = ((results[2] as List).take(5)).toList();
        chartData = results[3] as List;
        _dailyTxCount = txCount;
        _dailySales = sales;
        _dailyItemsSold = itemsSold;
        _dailyProfit = profit;
      });
    } catch (_) {}
  }

  static double _safeNum(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  String _fmtK(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}jt';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}rb';
    return '$n';
  }

  String _shortDate(String d) { final p = d.split('-'); return p.length >= 3 ? '${p[2]}/${p[1]}' : d; }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(0), children: [
        // Summary Cards
        Row(children: [
          _summaryCard('Penjualan', fmtPrice(summary['total_sales'] ?? 0), cs.primaryContainer.withValues(alpha: 0.3), cs.primary, cs),
          const SizedBox(width: 8),
          _summaryCard('Profit Bersih', fmtPrice(summary['total_profit'] ?? 0), Colors.green.withValues(alpha: 0.1), Colors.green, cs),
          const SizedBox(width: 8),
          _summaryCard('Transaksi', '${summary['total_transactions'] ?? 0}', cs.secondaryContainer.withValues(alpha: 0.3), cs.secondary, cs),
        ]),
        const SizedBox(height: 16),

        // Charts — Responsive: chart + daily recap
        LayoutBuilder(builder: (_, constraints) {
          final isWide = constraints.maxWidth > 800;
          final chart28Widget = _buildChart28(cs);
          final recapWidget = _buildDailyRecap(cs);
          
          if (isWide) {
            return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: chart28Widget),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: recapWidget),
            ]));
          } else {
            return Column(children: [
              chart28Widget,
              const SizedBox(height: 12),
              recapWidget,
            ]);
          }
        }),
        const SizedBox(height: 16),

        // Low Stock + Top Products
        LayoutBuilder(builder: (_, constraints) {
          final isWide = constraints.maxWidth > 600;
          final children = [
            // Low Stock
            Expanded(flex: 1, child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.warning_amber, size: 16, color: cs.error), const SizedBox(width: 8),
                  Text('Stok Rendah', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface))]),
                const SizedBox(height: 8),
                if (lowStock.isEmpty) Text('Semua stok aman 👍', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant))
                else ...lowStock.take(8).map((item) => Container(
                  margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: cs.errorContainer.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.error.withValues(alpha: 0.1))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(item['name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                    Text('${_safeNum(item['stock']).round()} ${item['unit'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.error)),
                  ]),
                )),
              ]),
            )),
            SizedBox(width: isWide ? 12 : 0, height: isWide ? 0 : 12),
            // Top Products
            Expanded(flex: 1, child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.emoji_events, size: 16, color: cs.primary), const SizedBox(width: 8),
                  Text('Produk Terlaris (7 Hari)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface))]),
                const SizedBox(height: 8),
                if (topProducts.isEmpty) Text('Belum ada data penjualan', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant))
                else ...topProducts.asMap().entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Container(width: 24, height: 24, decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
                      child: Center(child: Text('${e.key + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.value['product_name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                    Text(fmtPrice(e.value['total_revenue'] ?? 0), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary)),
                  ]),
                )),
              ]),
            )),
          ];
          return isWide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: children) : Column(children: children.map((c) => c is Expanded ? SizedBox(width: double.infinity, child: c.child) : c).toList());
        }),
      ]),
    );
  }

  Widget _buildChart28(ColorScheme cs) {
    final allVals = chartData.expand((d) => [_safeNum(d['sales']), _safeNum(d['profit'])]);
    final chartMax = allVals.isEmpty ? 1.0 : allVals.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(16),
      height: 300,
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart, size: 16, color: cs.onSurface), const SizedBox(width: 8),
          Expanded(child: Text('Penjualan vs Profit (28 Hari)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface))),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, color: cs.primary), const SizedBox(width: 4),
            const Text('Sales', style: TextStyle(fontSize: 10)), const SizedBox(width: 8),
            Container(width: 12, height: 12, color: Colors.green), const SizedBox(width: 4),
            const Text('Profit', style: TextStyle(fontSize: 10)),
          ])
        ]),
        const SizedBox(height: 24),
        if (chartData.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Belum ada data', style: TextStyle(color: cs.onSurfaceVariant))))
        else
          Expanded(child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMax * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final idx = group.x.toInt();
                    if (idx < 0 || idx >= chartData.length) return null;
                    return BarTooltipItem(
                      '${_shortDate(chartData[idx]['date']?.toString() ?? '')}\n${_fmtK(rod.toY)}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    );
                  }
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= chartData.length) return const SizedBox();
                      if (idx % 7 != 0 && idx != chartData.length - 1) return const SizedBox();
                      return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(_shortDate(chartData[idx]['date']?.toString() ?? ''), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)));
                    },
                    reservedSize: 28,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) => Text(_fmtK(value), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.3), strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              barGroups: chartData.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: _safeNum(e.value['sales']),
                      color: cs.primary.withValues(alpha: 0.8),
                      width: 6,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    BarChartRodData(
                      toY: _safeNum(e.value['profit']),
                      color: Colors.green.withValues(alpha: 0.8),
                      width: 6,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                );
              }).toList(),
            ),
          )),
      ]),
    );
  }

  /// Daily Recap — text-based summary instead of bar chart
  Widget _buildDailyRecap(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.today, size: 16, color: cs.onSurface),
          const SizedBox(width: 8),
          Text('Rekap Hari Ini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
        ]),
        const SizedBox(height: 16),
        _recapRow(Icons.receipt_long, 'Total Transaksi', '$_dailyTxCount', cs.primary, cs),
        const SizedBox(height: 8),
        _recapRow(Icons.attach_money, 'Pendapatan', fmtPrice(_dailySales), Colors.blue, cs),
        const SizedBox(height: 8),
        _recapRow(Icons.trending_up, 'Profit', fmtPrice(_dailyProfit), _dailyProfit >= 0 ? Colors.green : Colors.red, cs),
        const SizedBox(height: 8),
        _recapRow(Icons.inventory_2, 'Barang Terjual', '$_dailyItemsSold pcs', Colors.orange, cs),
      ]),
    );
  }

  Widget _recapRow(IconData icon, String label, String value, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500))),
        Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)))),
      ]),
    );
  }

  Widget _summaryCard(String label, String value, Color bg, Color textColor, ColorScheme cs) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: textColor.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor))),
      ]),
    ));
  }
}
