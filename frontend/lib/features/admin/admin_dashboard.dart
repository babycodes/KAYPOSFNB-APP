import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../core/helpers.dart';
import '../../services/sync_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _loading = true;
  Map<String, dynamic> _summary = {};
  List<dynamic> _chart28 = [];
  List<dynamic> _topProducts = [];
  List<dynamic> _topWaste = [];
  int? _hoveredBarIndex;

  @override
  void initState() {
    super.initState();
    _load();
    SyncService.syncNotifier.addListener(_onSyncEvent);
  }

  @override
  void dispose() {
    SyncService.syncNotifier.removeListener(_onSyncEvent);
    super.dispose();
  }

  void _onSyncEvent() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        Api.get('/reports/dashboard-summary'),
        Api.get('/reports/chart28'),
        Api.get('/reports/products?days=30'),
        Api.get('/reports/top-waste'),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _chart28 = results[1] as List;
        _topProducts = ((results[2] as List).take(10)).toList();
        _topWaste = results[3] as List;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Dashboard Load Error: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  static double _safeNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmtK(num n) {
    if (n.abs() >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}jt';
    if (n.abs() >= 1000) return '${(n / 1000).toStringAsFixed(0)}rb';
    return n.round().toString();
  }

  String _fmtNum(double n) {
    if (n == n.roundToDouble()) return n.round().toString();
    return n.toStringAsFixed(2);
  }

  String _fmtDynUnit(double qty, String masterUnit) {
    final absQty = qty.abs();
    final sign = qty < 0 ? '-' : '';
    final uLower = masterUnit.toLowerCase().trim();
    if (uLower == 'kg' && absQty > 0 && absQty < 1) return '$sign${_fmtNum(absQty * 1000)} gram';
    if ((uLower == 'liter' || uLower == 'l') && absQty > 0 && absQty < 1) return '$sign${_fmtNum(absQty * 1000)} ml';
    return '$sign${_fmtNum(absQty)} $masterUnit';
  }

  String _shortDate(String d) {
    final p = d.split('-');
    return p.length >= 3 ? '${p[2]}/${p[1]}' : d;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width > 800;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(0), children: [
        // ── SECTION 1: Summary Cards ──
        _buildSummaryCards(cs, isWide),
        const SizedBox(height: 20),
        // ── SECTION 2: 28-Day Trend Chart ──
        _buildNativeChart(cs),
        const SizedBox(height: 20),
        // ── SECTION 3: Top Products + Top Waste ──
        _buildBottomSection(cs, isWide),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════
  // SECTION 1: Summary Cards
  // ═══════════════════════════════════════════════════
  Widget _buildSummaryCards(ColorScheme cs, bool isWide) {
    final cards = [
      _MetricData('Penjualan Hari Ini', fmtPrice(_safeNum(_summary['today_revenue'])), Icons.point_of_sale, const Color(0xFF2196F3), const Color(0xFFE3F2FD)),
      _MetricData('Transaksi Hari Ini', '${(_safeNum(_summary['today_tx_count'])).round()}', Icons.receipt_long, const Color(0xFF7C4DFF), const Color(0xFFEDE7F6)),
      _MetricData('Penjualan Bulan Ini', fmtPrice(_safeNum(_summary['monthly_revenue'])), Icons.trending_up, const Color(0xFF00BFA5), const Color(0xFFE0F2F1)),
      _MetricData('HPP Bulan Ini', fmtPrice(_safeNum(_summary['monthly_cogs'])), Icons.account_balance_wallet, const Color(0xFFFF7043), const Color(0xFFFBE9E7)),
      _MetricData('Profit Bulan Ini', fmtPrice(_safeNum(_summary['monthly_profit'])), Icons.savings, _safeNum(_summary['monthly_profit']) >= 0 ? const Color(0xFF43A047) : Colors.red, _safeNum(_summary['monthly_profit']) >= 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE)),
    ];

    if (isWide) {
      return Row(children: cards.map((m) => Expanded(child: Padding(
        padding: EdgeInsets.only(right: m == cards.last ? 0 : 10),
        child: _buildMetricCard(m, cs),
      ))).toList());
    }
    // Mobile: 2-column grid responding to actual available width
    return LayoutBuilder(builder: (context, constraints) {
      final w = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10, runSpacing: 10,
        children: cards.map((m) => SizedBox(width: w, child: _buildMetricCard(m, cs))).toList(),
      );
    });
  }

  Widget _buildMetricCard(_MetricData m, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: m.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: m.color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: m.color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Icon(m.icon, size: 18, color: m.color),
          ),
          const Spacer(),
        ]),
        const SizedBox(height: 12),
        Text(m.label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(m.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface))),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════
  // SECTION 2: Native Bar Chart (28 Days)
  // ═══════════════════════════════════════════════════
  Widget _buildNativeChart(ColorScheme cs) {
    if (_chart28.isEmpty) {
      return Container(
        height: 260,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: cs.surfaceBright, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
        child: Center(child: Text('Belum ada data penjualan', style: TextStyle(color: cs.onSurfaceVariant))),
      );
    }

    final maxSales = _chart28.map((d) => _safeNum(d['sales'])).reduce(max).clamp(1.0, double.infinity);
    final maxProfit = _chart28.map((d) => _safeNum(d['profit'])).reduce(max).clamp(1.0, double.infinity);
    final chartMax = max(maxSales, maxProfit);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: cs.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.bar_chart, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Penjualan vs Profit (28 Hari)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface))),
          _legendDot(cs.primary, 'Penjualan'),
          const SizedBox(width: 12),
          _legendDot(Colors.green.shade600, 'Profit'),
        ]),
        const SizedBox(height: 8),
        // Y-axis labels + bars
        SizedBox(
          height: 220,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // Y-axis
            SizedBox(width: 44, height: 200, child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_fmtK(chartMax), style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
              Text(_fmtK(chartMax * 0.75), style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
              Text(_fmtK(chartMax * 0.5), style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
              Text(_fmtK(chartMax * 0.25), style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
              Text('0', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            ])),
            const SizedBox(width: 8),
            // Bars area
            Expanded(child: LayoutBuilder(builder: (_, constraints) {
              return Stack(children: [
                // Grid lines
                ...List.generate(5, (i) => Positioned(
                  left: 0, right: 0, bottom: (constraints.maxHeight - 20) * i / 4,
                  child: Container(height: 0.5, color: cs.outlineVariant.withValues(alpha: 0.4)),
                )),
                // Bars
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: _chart28.asMap().entries.map((e) {
                  final sales = _safeNum(e.value['sales']);
                  final profit = _safeNum(e.value['profit']);
                  final salesFraction = chartMax > 0 ? (sales / chartMax).clamp(0.0, 1.0) : 0.0;
                  final profitFraction = chartMax > 0 ? (profit / chartMax).clamp(0.0, 1.0) : 0.0;
                  final isHovered = _hoveredBarIndex == e.key;
                  final dateStr = e.value['date']?.toString() ?? '';
                  final showLabel = e.key % 7 == 0 || e.key == _chart28.length - 1;

                  return Expanded(child: GestureDetector(
                    onTapDown: (_) => setState(() => _hoveredBarIndex = e.key),
                    onTapUp: (_) => Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _hoveredBarIndex = null); }),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      // Tooltip
                      if (isHovered)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(6)),
                          child: Text('${_shortDate(dateStr)}\n${_fmtK(sales)} / ${_fmtK(profit)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 8, color: cs.onInverseSurface, fontWeight: FontWeight.bold, height: 1.3)),
                        ),
                      // Bar pair
                      SizedBox(height: constraints.maxHeight - 20, child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bar(salesFraction, cs.primary.withValues(alpha: isHovered ? 1 : 0.75)),
                          const SizedBox(width: 1),
                          _bar(profitFraction, Colors.green.shade600.withValues(alpha: isHovered ? 1 : 0.7)),
                        ],
                      )),
                      // X-axis label
                      SizedBox(height: 20, child: showLabel
                        ? Text(_shortDate(dateStr), style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant))
                        : const SizedBox()),
                    ]),
                  ));
                }).toList()),
              ]);
            })),
          ]),
        ),
      ]),
    );
  }

  Widget _bar(double fraction, Color color) {
    return FractionallySizedBox(
      heightFactor: fraction > 0 ? fraction.clamp(0.01, 1.0) : 0.005,
      alignment: Alignment.bottomCenter,
      child: Container(
        width: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10)),
    ]);
  }

  // ═══════════════════════════════════════════════════
  // SECTION 3: Top Products + Top Waste
  // ═══════════════════════════════════════════════════
  Widget _buildBottomSection(ColorScheme cs, bool isWide) {
    final productsWidget = _buildTopProducts(cs);
    final wasteWidget = _buildTopWaste(cs);

    if (isWide) {
      return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 1, child: productsWidget),
        const SizedBox(width: 12),
        Expanded(flex: 1, child: wasteWidget),
      ]));
    }
    return Column(children: [productsWidget, const SizedBox(height: 12), wasteWidget]);
  }

  Widget _buildTopProducts(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.emoji_events, size: 16, color: Colors.amber.shade800),
          ),
          const SizedBox(width: 10),
          Text('10 Produk Terlaris', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
          const Spacer(),
          Text('30 Hari', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 12),
        if (_topProducts.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('Belum ada data', style: TextStyle(color: cs.onSurfaceVariant))))
        else
          ..._topProducts.asMap().entries.map((e) {
            final rank = e.key + 1;
            final p = e.value;
            final qty = _safeNum(p['total_qty']).round();
            final revenue = _safeNum(p['total_revenue']);
            final medalColor = rank == 1 ? Colors.amber : rank == 2 ? Colors.grey.shade400 : rank == 3 ? Colors.brown.shade300 : null;
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: rank <= 3 ? medalColor!.withValues(alpha: 0.08) : cs.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: rank <= 3 ? Border.all(color: medalColor!.withValues(alpha: 0.2)) : null,
              ),
              child: Row(children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: medalColor ?? cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: Text('$rank', style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold,
                    color: medalColor != null ? Colors.white : cs.onPrimaryContainer,
                  ))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['product_name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text('$qty terjual', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ])),
                Text(fmtPrice(revenue), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.primary)),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _buildTopWaste(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade600),
          ),
          const SizedBox(width: 10),
          Text('Top 5 Kerugian / Waste', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: cs.onSurface)),
          const Spacer(),
          Text('Bulan Ini', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 12),
        if (_topWaste.isEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_outline, size: 40, color: Colors.green.shade300),
              const SizedBox(height: 8),
              Text('Tidak ada waste bulan ini 👍', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ]),
          ))
        else
          ..._topWaste.asMap().entries.map((e) {
            final w = e.value;
            final qty = _safeNum(w['total_qty']);
            final loss = _safeNum(w['total_loss']);
            final unit = w['unit']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.error.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: cs.errorContainer, shape: BoxShape.circle),
                  child: Center(child: Text('${e.key + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.error))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text(_fmtDynUnit(qty, unit), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                ])),
                Text('-${fmtPrice(loss)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.error)),
              ]),
            );
          }),
      ]),
    );
  }
}

class _MetricData {
  final String label, value;
  final IconData icon;
  final Color color, bgColor;
  const _MetricData(this.label, this.value, this.icon, this.color, this.bgColor);
}
