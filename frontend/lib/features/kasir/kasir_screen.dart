import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api.dart';
import '../../core/auth_provider.dart';
import '../../core/helpers.dart';
import '../../shared/widgets/theme_toggle.dart';

import 'widgets/product_card.dart';
import 'widgets/cart_item_widget.dart';
import 'dialogs/payment_dialog.dart';
import 'dialogs/receipt_modal.dart';
import 'dialogs/confirm_dialog.dart';
import 'dialogs/printer_settings_dialog.dart';
import '../auth/lock_screen.dart';
import '../../services/printer_service.dart';
import '../../services/receipt_generator.dart';
import '../admin/waste_report_dialog.dart';

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});
  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  List<dynamic> products = [];
  List<dynamic> categories = [];
  List<Map<String, dynamic>> cart = [];
  dynamic selectedCategory;
  String searchQuery = '';
  bool showSearch = false;
  bool cartOpen = false;
  bool showDashboard = false;
  bool showHistory = false;
  bool showProfile = false;
  bool showHeldCarts = false;

  String? activeCartLabel;
  String profileMsg = '';
  final _nameCtrl = TextEditingController();
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  Map<String, dynamic> todayStats = {'total_transactions': 0, 'total_sales': 0, 'avg_transaction': 0};
  List<dynamic> txHistory = [];
  List<dynamic> heldCarts = [];
  int _mobileNavIndex = 0;

  // === SAFE PARSERS — used everywhere, crash-proof ===
  static double _safeNum(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }
  /// Format stock for alert modal — shows gram/ml for fractional Kg/Liter
  static String _formatAlertStock(double stock, String unit) {
    final lower = unit.toLowerCase();
    String fmtNum(double n) => n == n.roundToDouble() ? n.round().toString() : n.toStringAsFixed(2);
    if (lower == 'kg') {
      if (stock < 1 && stock > 0) return '${fmtNum(stock * 1000)} gram';
      return '${fmtNum(stock)} $unit';
    }
    if (lower == 'liter' || lower == 'l') {
      if (stock < 1 && stock > 0) return '${fmtNum(stock * 1000)} ml';
      return '${fmtNum(stock)} $unit';
    }
    return '${fmtNum(stock)} $unit';
  }

  double get cartTotal => cart.fold(0.0, (s, i) {
    final price = _safeNum(i['unit_price']);
    final qty = _safeNum(i['quantity']);
    final discountPercent = _safeNum(i['discount_percent']);
    return s + (price * (1 - discountPercent / 100)) * qty;
  });

  double get cartSubtotal => cart.fold(0.0, (s, i) {
    final price = _safeNum(i['unit_price']);
    final qty = _safeNum(i['quantity']);
    return s + price * qty;
  });

  List<dynamic> get comboProducts => products.where((p) => (p['is_paket'] as num?)?.toInt() == 1).toList();

  List<dynamic> get filteredProducts => products.where((p) {
    bool matchCat = false;
    if (selectedCategory == -999) {
      try { matchCat = _getProductDiscount(p) > 0; } catch (_) { matchCat = false; }
    } else if (selectedCategory == -998) {
      matchCat = (p['is_paket'] as num?)?.toInt() == 1;
    } else {
      matchCat = selectedCategory == null || p['category_id'] == selectedCategory;
    }
    
    final q = searchQuery.toLowerCase();
    final name = (p['name'] ?? '').toString().toLowerCase();
    final matchSearch = searchQuery.isEmpty || 
        name.contains(q) ||
        (p['barcode']?.toString().toLowerCase().contains(q) ?? false);
    return matchCat && matchSearch;
  }).toList();

  @override
  void initState() {
    super.initState();
    ProductCard.setApiGetter(Api.get);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (!auth.isLoggedIn) { context.go('/login'); return; }
      PrinterService().init();

      _loadData();
      _loadDashboard();
      _loadHeldCarts();
      _loadStockAlerts();
    });
  }

  @override
  void dispose() { 
    super.dispose(); 
  }

  void _closeAllModals() {
    showDashboard = false; showHistory = false; showProfile = false;
    showHeldCarts = false; cartOpen = false; showSearch = false;
    searchQuery = '';
  }

  List<dynamic> activeDiscounts = [];

  /// Recipes indexed by product_id.toString() → [{bahan_baku_id, qty_needed}]
  Map<String, List<Map<String, dynamic>>> _recipes = {};
  /// Material stocks indexed by bahan_baku_id.toString() → stock (double)
  Map<String, double> _materialStocks = {};

  /// Stock alert counters for badge display
  int _stockHabisCount = 0;
  int _stockRendahCount = 0;

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        Api.get('/products'), Api.get('/categories'), Api.get('/discounts'), Api.get('/stock-pool'),
      ]);
      setState(() { 
        products = results[0] as List; 
        categories = results[1] as List; 
        final allDiscounts = results[2] as List;
        activeDiscounts = allDiscounts.where((d) => d['is_active'] == 1).toList();

        // Build recipe & material maps from stock-pool
        _recipes = {};
        _materialStocks = {};
        final stockPool = results[3] as List;
        for (final row in stockPool) {
          if (row is! Map) continue;
          final pid = row['product_id']?.toString() ?? '';
          final mid = row['bahan_baku_id']?.toString() ?? '';
          if (pid.isEmpty || mid.isEmpty) continue;
          _recipes.putIfAbsent(pid, () => []).add({
            'bahan_baku_id': mid,
            'qty_needed': _safeNum(row['qty_needed']),
          });
          // Master Unit Normalizer: convert Kg→gram, Liter→ml in-memory
          // so the cashier engine (which expects base units) calculates correctly.
          // DB remains untouched — this is a read-time mapping only.
          double stock = _safeNum(row['bahan_stock']);
          final unit = (row['bahan_unit'] ?? '').toString().toLowerCase();
          if (unit == 'kg') {
            stock *= 1000; // Kg → gram
          } else if (unit == 'liter' || unit == 'l') {
            stock *= 1000; // Liter → ml
          }
          _materialStocks[mid] = stock;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadDashboard() async {
    try {
      final results = await Future.wait([Api.get('/transactions/today'), Api.get('/transactions?limit=10')]);
      setState(() { todayStats = results[0]; });
    } catch (_) {}
  }

  Future<void> _loadHeldCarts() async {
    try { final r = await Api.get('/held-carts'); if (mounted) setState(() => heldCarts = r as List); } catch (_) {}
  }

  /// Load stock alert counts for badge display on Stok button.
  Future<void> _loadStockAlerts() async {
    try {
      final alertBahan = await Api.get('/bahan-baku/alerts') as List;
      if (!mounted) return;
      int habis = 0, rendah = 0;
      for (final b in alertBahan) {
        if (_safeNum(b['stock']) <= 0) { habis++; } else { rendah++; }
      }
      setState(() { _stockHabisCount = habis; _stockRendahCount = rendah; });
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final res = await Api.get('/transactions?date=$today&limit=50');
      setState(() => txHistory = (res['data'] ?? []) as List);
    } catch (_) { setState(() => txHistory = []); }
  }

  Future<void> _showStockAlert() async {
    try {
      final alertBahan = await Api.get('/bahan-baku/alerts') as List;
      if (!mounted) return;
      
      final outOfStock = alertBahan.where((b) {
        final stock = _safeNum(b['stock']);
        return stock <= 0;
      }).toList();
      
      final lowStock = alertBahan.where((b) {
        final stock = _safeNum(b['stock']);
        return stock > 0;
      }).toList();
      
      final cs = Theme.of(context).colorScheme;
      final totalAlerts = outOfStock.length + lowStock.length;
      
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.notifications_active, color: cs.error, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('Peringatan Stok Bahan Baku', style: TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(
          width: 440,
          child: totalAlerts == 0
            ? const Padding(padding: EdgeInsets.all(16), child: Text('✅ Semua stok bahan baku aman!', style: TextStyle(fontSize: 14)))
            : ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
                child: DefaultTabController(
                  length: 2,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TabBar(
                      labelColor: cs.primary,
                      indicatorColor: cs.primary,
                      tabs: [
                        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.error, size: 16, color: Colors.red),
                          const SizedBox(width: 6),
                          Text('Habis (${outOfStock.length})'),
                        ])),
                        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.warning_amber, size: 16, color: Colors.amber.shade700),
                          const SizedBox(width: 6),
                          Text('Rendah (${lowStock.length})'),
                        ])),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(child: SizedBox(
                      height: 300,
                      child: TabBarView(children: [
                        // Tab 1: Out of Stock
                        outOfStock.isEmpty
                          ? const Center(child: Text('Tidak ada bahan habis', style: TextStyle(fontSize: 13)))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: outOfStock.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final item = outOfStock[i];
                                final unit = item['unit']?.toString() ?? '';
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('HABIS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                  title: Text(item['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  trailing: Text('0 $unit', style: TextStyle(fontWeight: FontWeight.bold, color: cs.error)),
                                );
                              },
                            ),
                        // Tab 2: Low Stock
                        lowStock.isEmpty
                          ? const Center(child: Text('Tidak ada bahan stok rendah', style: TextStyle(fontSize: 13)))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: lowStock.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final item = lowStock[i];
                                final stock = _safeNum(item['stock']);
                                final minAlert = _safeNum(item['min_stock_alert']);
                                final unit = item['unit']?.toString() ?? '';
                                return ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
                                    child: const Text('RENDAH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                  title: Text(item['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  subtitle: Text('Min: ${_formatAlertStock(minAlert, unit)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                  trailing: Text(_formatAlertStock(stock, unit), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                                );
                              },
                            ),
                      ]),
                    )),
                  ]),
                ),
              ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ));
    } catch (e) {
      if (mounted) showToast(context, 'Gagal memuat stok: $e');
    }
  }

  int _getProductDiscount(dynamic product) => _getPromoInfo(product).$1;

  (int, String?) _getPromoInfo(dynamic product) {
    int maxDiscount = 0;
    String? promoName;
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    final weekdayStr = now.weekday.toString();

    for (final d in activeDiscounts) {
      final sType = d['schedule_type']?.toString() ?? 'all_day';
      final sVal = d['schedule_value']?.toString() ?? '';
      bool scheduleMatch = false;

      if (sType == 'all_day') {
        scheduleMatch = true;
      } else if (sType == 'specific_days' || sType == 'by_day') {
        final daysList = sVal.split(',').map((e) => e.trim());
        if (daysList.contains(weekdayStr)) scheduleMatch = true;
      } else if (sType == 'date_range') {
        try {
          final parts = sVal.contains(',') ? sVal.split(',') : sVal.split(' to ');
          if (parts.length == 2) {
            final start = DateTime.parse(parts[0].trim());
            final startDay = DateTime(start.year, start.month, start.day);
            final end = DateTime.parse(parts[1].trim());
            final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
            if (now.compareTo(startDay) >= 0 && now.compareTo(endDay) <= 0) scheduleMatch = true;
          }
        } catch (_) {}
      } else if (sType == 'specific_date') {
        if (sVal.startsWith(todayStr)) scheduleMatch = true;
      }

      if (!scheduleMatch) continue;

      bool applies = false;
      final targetCats = (d['target_categories'] as List?) ?? [];
      final targetProds = (d['target_products'] as List?) ?? [];
      
      final safeTargetCats = targetCats.map((e) => e.toString()).toList();
      final safeTargetProds = targetProds.map((e) => e.toString()).toList();
      final pCatId = product['category_id']?.toString() ?? '';
      final pId = product['id']?.toString() ?? '';
      
      // Strict OR evaluation
      if (d['target_ids'] == 'ALL') {
        applies = true;
      } else if (safeTargetCats.isEmpty && safeTargetProds.isEmpty) {
        applies = false;
      } else {
        applies = safeTargetCats.contains(pCatId) || safeTargetProds.contains(pId);
      }

      if (applies) {
        final percent = (d['discount_percent'] as num?)?.toInt() ?? 0;
        if (percent > maxDiscount) {
          maxDiscount = percent;
          promoName = d['name']?.toString();
        }
      }
    }
    return (maxDiscount, promoName);
  }

  double _calcUnitPrice(dynamic product, String unitName) {
    return _safeNum(product['price']);
  }


  Future<void> _handleProductSelect(dynamic product) async {
    // Use _getEffectiveStock for real-time dynamic stock check (not stale snapshot)
    final int currentEffective = _getEffectiveStock(product);
    if (currentEffective == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stok bahan tidak cukup untuk menambah "${product['name']}"'), duration: const Duration(seconds: 2)),
      );
      return;
    }
    
    String? addonSummary;
    if ((product['is_paket'] as num?)?.toInt() == 1) {
      try {
        final items = await Api.get('/paket-items/${product['id']}');
        if (items is List && items.isNotEmpty) {
          final summaryLines = items.map((i) => '  - ${i['qty']}x ${i['product_name']} (Rp 0)').toList();
          addonSummary = summaryLines.join('\n');
        }
      } catch (_) {}
    }
    
    _addToCart(product, 'pcs', 1, addonSummary);
  }

  /// Shadow deduction: counts how many units of [productId] are consumed
  /// across the entire cart (direct items + items consumed inside packages).
  int _getCartQtyForProduct(dynamic productId) {
    final String pid = productId.toString();
    int total = 0;
    for (final item in cart) {
      if (item['product'] is Map) {
        final p = item['product'];
        if (p['id']?.toString() == pid) {
          total += _safeNum(item['quantity']).round();
        } else if ((p['is_paket'] as num?)?.toInt() == 1 && p['paket_items'] is List) {
          for (final pi in p['paket_items']) {
            if (pi is Map && pi['product_id']?.toString() == pid) {
              total += _safeNum(item['quantity']).round() * _safeNum(pi['qty']).round();
            }
          }
        }
      }
    }
    return total;
  }

  /// Same as _getCartQtyForProduct but for held/parked carts.
  int _getHeldQtyForProduct(dynamic productId) {
    final String pid = productId.toString();
    int total = 0;
    for (final held in heldCarts) {
      final cartData = held['cart_data'];
      if (cartData is List) {
        for (final item in cartData) {
          if (item is Map && item['product'] is Map) {
            final p = item['product'];
            if (p['id']?.toString() == pid) {
              total += _safeNum(item['quantity']).round();
            } else if ((p['is_paket'] as num?)?.toInt() == 1 && p['paket_items'] is List) {
              for (final pi in p['paket_items']) {
                if (pi is Map && pi['product_id']?.toString() == pid) {
                  total += _safeNum(item['quantity']).round() * _safeNum(pi['qty']).round();
                }
              }
            }
          }
        }
      }
    }
    return total;
  }

  /// Computes total raw material consumed by ALL cart + held items.
  /// Returns Map<materialId.toString(), totalConsumed>.
  Map<String, double> _computeCartMaterialUsage() {
    final Map<String, double> usage = {};

    void addUsageForProduct(String productId, double qty) {
      final recipe = _recipes[productId];
      if (recipe == null) return;
      for (final ing in recipe) {
        final mid = ing['bahan_baku_id']?.toString() ?? '';
        final needed = _safeNum(ing['qty_needed']);
        if (mid.isNotEmpty && needed > 0) {
          usage[mid] = (usage[mid] ?? 0) + (qty * needed);
        }
      }
    }

    void processCartList(List cartData) {
      for (final item in cartData) {
        if (item is! Map || item['product'] is! Map) continue;
        final p = item['product'];
        final double qty = _safeNum(item['quantity']);
        if (qty <= 0) continue;

        if ((p['is_paket'] as num?)?.toInt() == 1 && p['paket_items'] is List) {
          for (final pi in p['paket_items']) {
            if (pi is! Map) continue;
            final childId = pi['product_id']?.toString() ?? '';
            final childQty = _safeNum(pi['qty']);
            addUsageForProduct(childId, qty * childQty);
          }
        } else {
          addUsageForProduct(p['id']?.toString() ?? '', qty);
        }
      }
    }

    // Current cart
    processCartList(cart);
    // Held carts
    for (final held in heldCarts) {
      if (held['cart_data'] is List) processCartList(held['cart_data']);
    }
    return usage;
  }

  /// Returns the real-time effective stock for a product.
  /// For regular products: -1 = no recipe/unlimited, 0 = sold out, >0 = available.
  /// For packages: ALWAYS returns 0 or >0 (never -1).
  ///
  /// MATHEMATICAL CHAIN (Cross-Product Shared Material Pool):
  /// 1. cartUsage[M] = SUM of all material M consumed by cart + held items
  /// 2. Remaining[M] = DB_Stock[M] - cartUsage[M]
  /// 3. Regular:  Effective(C) = MIN( floor( Remaining[M_i] / Recipe_Needed[M_i] ) )
  /// 4. Package:  packageMaterialNeed[M] = SUM(childQty * childRecipe[M]) for all children
  ///             Effective(P) = MIN( floor( Remaining[M_i] / packageMaterialNeed[M_i] ) )
  int _getEffectiveStock(dynamic product) {
    if (product is! Map) return -1;

    // === PACKAGE (is_paket == 1): Material-aggregated capacity ===
    // Instead of MIN(childEffective/childQty) — which double-counts shared
    // ingredients — we aggregate the total raw material cost of 1 whole package
    // and divide remaining global stock by that aggregate.
    if ((product['is_paket'] as num?)?.toInt() == 1) {
      try {
        final paketItems = product['paket_items'];
        if (paketItems is! List || paketItems.isEmpty) return 0;

        // Step 1: Aggregate total raw materials needed for 1 package unit.
        // Map<materialId, totalQtyNeeded>
        final Map<String, double> packageMaterialNeed = {};
        bool hasAnyRecipeChild = false;

        for (final pi in paketItems) {
          if (pi is! Map) continue;
          final String childIdStr = pi['product_id']?.toString() ?? '';
          if (childIdStr.isEmpty) continue;
          final double childQtyInPaket = _safeNum(pi['qty']);
          if (childQtyInPaket <= 0) continue;

          final childRecipe = _recipes[childIdStr];
          if (childRecipe == null || childRecipe.isEmpty) {
            // Child has no recipe — check if it even exists in products
            // If it has available_portions from SQL, we must fall back to
            // child-based MIN for this specific child.
            // For now, skip (treat as unlimited ingredient).
            continue;
          }

          hasAnyRecipeChild = true;
          for (final ing in childRecipe) {
            final mid = ing['bahan_baku_id']?.toString() ?? '';
            final double qtyNeeded = _safeNum(ing['qty_needed']);
            if (mid.isNotEmpty && qtyNeeded > 0) {
              // Total material per 1 package = childQtyInPaket * recipe per 1 child
              packageMaterialNeed[mid] = 
                (packageMaterialNeed[mid] ?? 0) + (childQtyInPaket * qtyNeeded);
            }
          }
        }

        // No children have recipes → treat as high-availability
        if (!hasAnyRecipeChild || packageMaterialNeed.isEmpty) return 999;

        // Step 2: Compute max packages from remaining raw materials
        final cartUsage = _computeCartMaterialUsage();
        int minPortions = 999999;
        for (final entry in packageMaterialNeed.entries) {
          final String mid = entry.key;
          final double neededPerPackage = entry.value;
          if (neededPerPackage <= 0) continue;
          final double totalStock = _materialStocks[mid] ?? 0;
          final double consumed = cartUsage[mid] ?? 0;
          final double remaining = totalStock - consumed;
          final int portions = (remaining / neededPerPackage).floor();
          if (portions < minPortions) minPortions = portions;
        }

        if (minPortions == 999999) return 999;
        return minPortions < 0 ? 0 : minPortions;
      } catch (_) {
        return 0;
      }
    }

    // === REGULAR PRODUCT: Material-pool-aware effective stock ===
    final String pid = product['id']?.toString() ?? '';
    final recipe = _recipes[pid];

    // No recipe loaded → check legacy available_portions as fallback
    if (recipe == null || recipe.isEmpty) {
      final dynamic rawPortions = product['available_portions'];
      if (rawPortions == null) return -1; // No recipe = unlimited
      // Fallback: use old simple deduction
      final int maxPortions = (rawPortions as num).toInt();
      final int inCart = _getCartQtyForProduct(product['id']);
      final int inHeld = _getHeldQtyForProduct(product['id']);
      int effectiveStock = maxPortions - inCart - inHeld;
      return effectiveStock < 0 ? 0 : effectiveStock;
    }

    // Material-pool-aware calculation
    final cartUsage = _computeCartMaterialUsage();
    int minPortions = 999999;
    for (final ing in recipe) {
      final mid = ing['bahan_baku_id']?.toString() ?? '';
      final double qtyNeeded = _safeNum(ing['qty_needed']);
      if (mid.isEmpty || qtyNeeded <= 0) continue;
      final double totalStock = _materialStocks[mid] ?? 0;
      final double consumed = cartUsage[mid] ?? 0;
      final double remaining = totalStock - consumed;
      final int portions = (remaining / qtyNeeded).floor();
      if (portions < minPortions) minPortions = portions;
    }
    int result = minPortions == 999999 ? -1 : minPortions;
    return result < 0 ? 0 : result; // ABSOLUTE CLAMP
  }

  /// Returns the BASE stock from raw DB materials WITHOUT any cart/held deductions.
  /// Used to differentiate "HABIS" (DB truly at 0) vs "DI PESAN" (reserved in cart/held).
  int _getBaseStock(dynamic product) {
    if (product is! Map) return -1;

    // Package: compute from raw materials WITHOUT cart deductions
    if ((product['is_paket'] as num?)?.toInt() == 1) {
      final paketItems = product['paket_items'];
      if (paketItems is! List || paketItems.isEmpty) return 0;

      final Map<String, double> packageMaterialNeed = {};
      bool hasAnyRecipeChild = false;
      for (final pi in paketItems) {
        if (pi is! Map) continue;
        final childIdStr = pi['product_id']?.toString() ?? '';
        if (childIdStr.isEmpty) continue;
        final childQtyInPaket = _safeNum(pi['qty']);
        if (childQtyInPaket <= 0) continue;
        final childRecipe = _recipes[childIdStr];
        if (childRecipe == null || childRecipe.isEmpty) continue;
        hasAnyRecipeChild = true;
        for (final ing in childRecipe) {
          final mid = ing['bahan_baku_id']?.toString() ?? '';
          final qtyNeeded = _safeNum(ing['qty_needed']);
          if (mid.isNotEmpty && qtyNeeded > 0) {
            packageMaterialNeed[mid] = (packageMaterialNeed[mid] ?? 0) + (childQtyInPaket * qtyNeeded);
          }
        }
      }
      if (!hasAnyRecipeChild || packageMaterialNeed.isEmpty) return 999;
      int minPortions = 999999;
      for (final entry in packageMaterialNeed.entries) {
        final totalStock = _materialStocks[entry.key] ?? 0;
        if (entry.value <= 0) continue;
        final portions = (totalStock / entry.value).floor();
        if (portions < minPortions) minPortions = portions;
      }
      return (minPortions == 999999) ? 999 : (minPortions < 0 ? 0 : minPortions);
    }

    // Regular product: compute from raw materials WITHOUT cart deductions
    final String pid = product['id']?.toString() ?? '';
    final recipe = _recipes[pid];
    if (recipe == null || recipe.isEmpty) {
      final rawPortions = product['available_portions'];
      if (rawPortions == null) return -1;
      return (rawPortions as num).toInt();
    }
    int minPortions = 999999;
    for (final ing in recipe) {
      final mid = ing['bahan_baku_id']?.toString() ?? '';
      final qtyNeeded = _safeNum(ing['qty_needed']);
      if (mid.isEmpty || qtyNeeded <= 0) continue;
      final totalStock = _materialStocks[mid] ?? 0;
      final portions = (totalStock / qtyNeeded).floor();
      if (portions < minPortions) minPortions = portions;
    }
    int result = minPortions == 999999 ? -1 : minPortions;
    return result < 0 ? 0 : result;
  }
  void _addToCart(dynamic product, String unitName, num quantity, [String? addonSummary]) {
    final idx = cart.indexWhere((i) => i['product'] is Map && i['product']['id'] == product['id'] && i['selected_unit'] == unitName && (i['addon_summary'] ?? '') == (addonSummary ?? ''));
    if (idx >= 0) {
      _setItemQuantity(idx, _safeNum(cart[idx]['quantity']) + quantity.toDouble());
    } else {
      cart.add({
        'product': product, 
        'selected_unit': unitName, 
        'quantity': 0, 
        'unit_price': _calcUnitPrice(product, unitName),
        'discount_percent': _getProductDiscount(product),
        if (addonSummary != null) 'addon_summary': addonSummary,
      });
      _setItemQuantity(cart.length - 1, quantity.toDouble());
    }
  }

  /// Computes the max quantity this cart item can hold, based on
  /// current effective stock (material-pool-aware) + its current qty.
  int _getMaxCartQty(int cartIndex) {
    if (cartIndex < 0 || cartIndex >= cart.length) return 0;
    final product = cart[cartIndex]['product'];
    if (product is! Map) return 999;
    final int currentQty = _safeNum(cart[cartIndex]['quantity']).round();
    final int effective = _getEffectiveStock(product);
    if (effective == -1) return 9999; // Unlimited (no recipe)
    // effective already accounts for this item's current qty in cart,
    // so max allowed = currentQty + effective ("how many more can be added")
    return currentQty + effective;
  }

  void _incrementItem(int i) {
    final int maxQty = _getMaxCartQty(i);
    final int currentQty = _safeNum(cart[i]['quantity']).round();
    if (currentQty >= maxQty) return; // Already at max — block
    _setItemQuantity(i, _safeNum(cart[i]['quantity']) + 1);
  }
  void _decrementItem(int i) { if (_safeNum(cart[i]['quantity']) > 1) _setItemQuantity(i, _safeNum(cart[i]['quantity']) - 1); }
  void _removeItem(int i) => setState(() => cart.removeAt(i));
  
  void _setItemQuantity(int i, double qty) {
    if (qty < 0) qty = 0;

    // Enforce material-pool-aware max quantity
    final int maxQty = _getMaxCartQty(i);
    if (qty > maxQty) qty = maxQty.toDouble();
    
    setState(() {
      cart[i]['quantity'] = qty;
    });
  }

  Future<void> _handleCheckout(double paidAmount, double discountTotal, String discountType, String discountBy) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => KayConfirmDialog(
      title: 'Konfirmasi Transaksi',
      message: 'Pastikan semua item dan jumlah pembayaran sudah benar. Transaksi akan langsung tersimpan dan tidak bisa diubah.',
      confirmText: 'Ya, Proses Pembelian',
    ));
    if (confirmed != true) return;
    try {
      final items = cart.map((c) {
        final price = _safeNum(c['unit_price']);
        final qty = _safeNum(c['quantity']);
        final discountPercent = _safeNum(c['discount_percent']);
        final discountAmount = (price * (discountPercent / 100)) * qty;
        return {
          'product_id': c['product']['id'],
          'unit_name': c['selected_unit'],
          'quantity': c['quantity'],
          'price': price,
          'discount_percent': discountPercent,
          'discount_amount': discountAmount,
          if (c['addon_summary'] != null) 'addon_summary': c['addon_summary'],
        };
      }).toList();
      final result = await Api.post('/transactions', body: {
        'items': items, 
        'paid_amount': paidAmount,
        'discount_total': discountTotal,
        'discount_type': discountType,
        'discount_by': discountBy,
      });
      if (mounted) {
        setState(() { cart.clear(); cartOpen = false; activeCartLabel = null; });
        if (activeCartLabel != null) {
          try { Api.delete('/held-carts/${activeCartLabel!}'); } catch (_) {}
        }
        _loadDashboard(); _loadData(); _loadStockAlerts();
        
        
        showDialog(context: context, builder: (_) => ReceiptModal(transaction: result['transaction'], details: List<Map<String, dynamic>>.from(result['details'])));
      }
    } catch (e) { if (mounted) showToast(context, '❌ ${e.toString().replaceFirst("Exception: ", "")}'); }
  }

  void _handleLogout() async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => const KayConfirmDialog(
      title: 'Logout', message: 'Yakin ingin logout dari kasir?', confirmText: 'Ya, Logout'));
    if (confirmed == true && mounted) { context.read<AuthProvider>().logout(); context.go('/login'); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isMobile = MediaQuery.sizeOf(context).width < 768;

    // Lock screen overlay
    if (auth.isLocked) return const LockScreen();

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(children: [
      Column(children: [
        // === APPBAR ===
        Container(
          color: Theme.of(context).appBarTheme.backgroundColor ?? cs.primary,
          padding: EdgeInsets.only(left: 16, right: 16, top: MediaQuery.of(context).padding.top, bottom: 0),
          constraints: const BoxConstraints(minHeight: 48),
          child: SizedBox(height: 48, child: Row(children: [
            Image.asset('assets/icon-512.png', width: 28, height: 28),
            const SizedBox(width: 12),
            const Text('KAYPOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.5)),
          ])),
        ),

        // === TOOLBAR ===
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: cs.surface, border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)))),
          child: Row(children: [
            // Category dropdown
            Builder(builder: (ctx) {
              final dropdown = Container(height: 36, constraints: isMobile ? null : const BoxConstraints(maxWidth: 220), padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
                child: DropdownButtonHideUnderline(child: DropdownButton<int?>(
                  value: selectedCategory, isExpanded: true, isDense: true,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('📦 Semua Kategori')),
                    const DropdownMenuItem(value: -999, child: Text('🎁 Promo', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))),
                    const DropdownMenuItem(value: -998, child: Text('🎁 Paket Combo', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))),
                    ...categories.map((c) {
                      final cId = c['id'];
                      return DropdownMenuItem(value: cId, child: Text('${c['icon'] ?? '📦'} ${c['name'] ?? ''}'));
                    }),
                  ],
                  onChanged: (v) => setState(() => selectedCategory = v),
                )));
              return isMobile ? Expanded(child: dropdown) : dropdown;
            }),
            const SizedBox(width: 8),
            // Desktop search
            if (!isMobile) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: SizedBox(height: 40, child: TextField(
              onChanged: (v) => setState(() => searchQuery = v),
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              decoration: const InputDecoration(hintText: 'Cari produk...', prefixIcon: Icon(Icons.search, size: 18)),
            )))),
            
            // Action buttons wrapped in Flexible to prevent overflow
            Flexible(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMobile) ...[
                        const SizedBox(width: 8),
                        _toolbarBtn(Icons.pie_chart, 'Rekap', onTap: () { setState(() { _closeAllModals(); showDashboard = true; }); _loadDashboard(); }),
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.history, 'Riwayat', onTap: () { setState(() { _closeAllModals(); showHistory = true; }); _loadHistory(); }),
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.notifications, 'Stok', onTap: _showStockAlert,
                          badge: (_stockHabisCount + _stockRendahCount) > 0 ? '${_stockHabisCount + _stockRendahCount}' : null),
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.delete_sweep, 'Waste', onTap: () {
                          setState(() => _closeAllModals());
                          WasteReportDialog.show(context, onSaved: () { _loadData(); _loadStockAlerts(); });
                        }),
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.person, 'Profile', onTap: () => setState(() { _closeAllModals(); showProfile = true; })),
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.print, 'Printer', onTap: () { setState(() => _closeAllModals()); showDialog(context: context, builder: (_) => const PrinterSettingsDialog()); }),
                      ],
                      // Held carts indicator
                      if (heldCarts.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.access_time, 'Ditahan', color: cs.secondaryContainer, textColor: cs.onSecondaryContainer,
                          badge: heldCarts.length.toString(), onTap: () { setState(() { _closeAllModals(); showHeldCarts = true; }); _loadHeldCarts(); }),
                      ],
                      if (isMobile) ...[
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.notifications, 'Stok', onTap: _showStockAlert,
                          badge: (_stockHabisCount + _stockRendahCount) > 0 ? '${_stockHabisCount + _stockRendahCount}' : null),
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.delete_sweep, 'Waste', onTap: () {
                          setState(() => _closeAllModals());
                          WasteReportDialog.show(context, onSaved: () { _loadData(); _loadStockAlerts(); });
                        }),
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.print, 'Printer', onTap: () { setState(() => _closeAllModals()); showDialog(context: context, builder: (_) => const PrinterSettingsDialog()); }),
                      ],
                      if (!isMobile) ...[
                        if (auth.isAdmin) ...[const SizedBox(width: 4), _toolbarBtn(Icons.settings, 'Admin', color: cs.tertiaryContainer, textColor: cs.onTertiaryContainer, onTap: () => context.go('/admin'))],
                        const SizedBox(width: 4),
                        _toolbarBtn(Icons.logout, 'Keluar', color: cs.errorContainer.withValues(alpha: 0.5), textColor: cs.error, onTap: _handleLogout),
                      ],
                      const SizedBox(width: 4),
                      // Lock button
                      _toolbarBtn(Icons.lock, 'Kunci', color: cs.errorContainer.withValues(alpha: 0.5), textColor: cs.error, onTap: () { context.read<AuthProvider>().lock(); }),
                      const SizedBox(width: 4),
                      const ThemeToggleButton(),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),

        // === MOBILE SEARCH BAR ===
        if (isMobile && showSearch) Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: cs.surfaceContainer.withValues(alpha: 0.5), border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)))),
          child: Row(children: [
            Expanded(child: TextField(
              autofocus: true, onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(hintText: 'Cari produk...', prefixIcon: const Icon(Icons.search, size: 16), isDense: true,
                filled: true, fillColor: cs.surfaceContainer, 
                contentPadding: const EdgeInsets.symmetric(vertical: 10)),
            )),
            const SizedBox(width: 8),
            InkWell(onTap: () => setState(() { showSearch = false; searchQuery = ''; }),
              child: Container(width: 36, height: 36, decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant))),
          ]),
        ),

        // === MAIN CONTENT ===
        Expanded(child: Row(children: [
          // Product Grid
          Expanded(child: Padding(
            padding: EdgeInsets.only(left: 4, right: 4, top: 4, bottom: isMobile ? 76 : 4),
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    if (filteredProducts.isEmpty) return const SizedBox.shrink();
                    final activeNames = <String>{};
                    for (final p in filteredProducts) {
                      final info = _getPromoInfo(p);
                      if (info.$1 > 0 && info.$2 != null) activeNames.add(info.$2!);
                    }
                    if (activeNames.isEmpty) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                      child: Row(
                        children: [
                          const Icon(Icons.local_offer, color: Colors.orange, size: 16),
                          const SizedBox(width: 8),
                          const Text('🎁 Promo Aktif:', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 6),
                          Expanded(child: Wrap(
                            spacing: 6, runSpacing: 4,
                            children: activeNames.map((name) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [Colors.green.shade600, Colors.green.shade700]),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                              ),
                              child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            )).toList(),
                          )),
                        ],
                      ),
                    );
                  }
                ),
                if (filteredProducts.isNotEmpty && filteredProducts.any((p) => (p['is_paket'] as num?)?.toInt() == 1)) Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                  child: Row(
                    children: [
                      const Icon(Icons.fastfood, color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text('🔥 Menu Paket Spesial Tersedia', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredProducts.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🔍', style: TextStyle(fontSize: 30)),
                        const SizedBox(height: 8),
                        Text('Produk tidak ditemukan', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: cs.onSurfaceVariant)),
                      ]))
                    : GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: isMobile ? 216 : 264,
                          mainAxisExtent: 68, crossAxisSpacing: 6, mainAxisSpacing: 6),
                        itemCount: filteredProducts.length,
                        itemBuilder: (_, i) {
                          final product = filteredProducts[i];
                          final promoInfo = _getPromoInfo(product);
                          final effectiveStock = _getEffectiveStock(product);
                          final baseStock = _getBaseStock(product);
                          return ProductCard(
                            product: product, 
                            bookedQty: _getCartQtyForProduct(product['id']).toDouble(), 
                            discountPercent: promoInfo.$1,
                            promoName: promoInfo.$2,
                            effectiveStock: effectiveStock,
                            baseStock: baseStock,
                            onSelect: _handleProductSelect
                          );
                        },
                      ),
                ),
              ],
            ),
          )),

          // Desktop Cart Sidebar
          if (!isMobile) Container(
            width: (MediaQuery.sizeOf(context).width * 0.40).clamp(320.0, 600.0),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, border: Border(left: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)))),
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  const Text('🛒 Keranjang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (cart.isNotEmpty) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                    child: Text('${cart.length}', style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)))],
                ]),
                if (cart.isNotEmpty) TextButton(onPressed: _clearCart, child: Text('Kosongkan', style: TextStyle(color: cs.error, fontSize: 12, fontWeight: FontWeight.w600))),
              ])),
              const Divider(height: 1),
              Expanded(child: cart.isEmpty
                ? Center(child: Text('Keranjang Kosong', style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.w500, fontSize: 14)))
                : ListView.builder(padding: const EdgeInsets.all(12), itemCount: cart.length,
                    itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 8),
                      child: CartItemWidget(item: cart[i], maxAllowedQty: _getMaxCartQty(i), onIncrement: () => _incrementItem(i), onDecrement: () => _decrementItem(i), onRemove: () => _removeItem(i), onSetQuantity: (q) => _setItemQuantity(i, q))))),
              const Divider(height: 1),
              Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                  Text(fmtPrice(cartTotal), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: cs.primary)),
                ]),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, height: 44, child: FilledButton(
                  onPressed: cart.isEmpty ? null : () => _holdCart(),
                  style: FilledButton.styleFrom(backgroundColor: cs.secondaryContainer, foregroundColor: cs.onSecondaryContainer, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.access_time, size: 14), SizedBox(width: 6), Text('Tahan', style: TextStyle(fontWeight: FontWeight.bold))]),
                )),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 56, child: FilledButton(
                  onPressed: cart.isEmpty ? null : () => _showPayment(),
                  style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 1),
                  child: const Text('💳 BAYAR SEKARANG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                )),
              ])),
            ]),
          ),
        ])),
      ]),
      // === OVERLAYS ===
      // Dashboard overlay
      if (showDashboard) ...[_overlay(() => setState(() => showDashboard = false)),
        Center(child: Material(elevation: 8, borderRadius: BorderRadius.circular(16), color: cs.surfaceBright,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('📊 Rekap Hari Ini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                InkWell(onTap: () => setState(() => showDashboard = false), child: const Text('✕')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _statCard('Penjualan', fmtPrice(todayStats['total_sales'] ?? 0), cs.primaryContainer.withValues(alpha: 0.3), cs.primary),
                const SizedBox(width: 8),
                _statCard('Transaksi', '${todayStats['total_transactions'] ?? 0}', cs.secondaryContainer.withValues(alpha: 0.3), cs.secondary),
                const SizedBox(width: 8),
                _statCard('Rata-Rata', fmtPrice(todayStats['avg_transaction'] ?? 0), cs.tertiaryContainer.withValues(alpha: 0.3), cs.tertiary),
              ]),
              if (todayStats['cashier_breakdown'] != null && (todayStats['cashier_breakdown'] as List).isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Rincian per Kasir', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: (todayStats['cashier_breakdown'] as List).length,
                    itemBuilder: (context, index) {
                      final item = (todayStats['cashier_breakdown'] as List)[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: cs.primaryContainer,
                              child: Icon(Icons.person, size: 16, color: cs.onPrimaryContainer),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['cashier_name']?.toString() ?? 'Kasir Offline', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('${item['total_transactions']} transaksi', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Text(
                              fmtPrice(item['total_sales'] ?? 0),
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: cs.primary),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ])))))],
      // History overlay
      if (showHistory) ...[_overlay(() => setState(() => showHistory = false)),
        Center(child: Material(elevation: 8, borderRadius: BorderRadius.circular(16), color: cs.surfaceBright,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.all(16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('📄 Riwayat Hari Ini', style: TextStyle(fontWeight: FontWeight.bold)), InkWell(onTap: () => setState(() => showHistory = false), child: const Text('✕'))])),
              const Divider(height: 1),
              Flexible(child: txHistory.isEmpty
                ? const Padding(padding: EdgeInsets.all(32), child: Text('Belum ada transaksi hari ini'))
                : ListView.builder(shrinkWrap: true, itemCount: txHistory.length, padding: const EdgeInsets.all(12),
                    itemBuilder: (_, i) { final tx = txHistory[i];
                      final txStatus = tx['status']?.toString() ?? 'completed';
                      final isVoided = txStatus == 'voided';
                      final isPartial = txStatus == 'partial_refund';
                      return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isVoided ? Colors.red.shade50 : isPartial ? Colors.orange.shade50 : cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: isVoided ? Border.all(color: Colors.red.shade200) : isPartial ? Border.all(color: Colors.orange.shade200) : null,
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('#${tx['id']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          if (isVoided) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)), child: const Text('VOID', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)))]
                          else if (isPartial) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)), child: const Text('REFUND', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)))],
                          const Spacer(),
                          Text('${tx['created_at'] ?? ''}'.split(' ').last.length >= 5 ? '${tx['created_at']}'.split(' ').last.substring(0, 5) : '', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                        ]),
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(tx['cashier_name'] ?? '-', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          Text(fmtPrice(tx['total_amount'] ?? 0), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isVoided ? cs.error : cs.primary, decoration: isVoided ? TextDecoration.lineThrough : null)),
                        ]),
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Bayar: ${fmtPrice(tx['paid_amount'] ?? 0)}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)), Text('Kembali: ${fmtPrice(tx['change_amount'] ?? 0)}', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: SizedBox(height: 32, child: FilledButton(onPressed: () => _reprintReceipt(tx['id']),
                            style: FilledButton.styleFrom(backgroundColor: cs.primaryContainer, foregroundColor: cs.onPrimaryContainer, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.print, size: 12), SizedBox(width: 4), Text('Cetak Ulang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))])))),
                          const SizedBox(width: 8),
                          Expanded(child: SizedBox(height: 32, child: FilledButton(onPressed: () => _showKasirTxDetail(tx),
                            style: FilledButton.styleFrom(backgroundColor: isVoided ? cs.errorContainer : cs.secondaryContainer, foregroundColor: isVoided ? cs.onErrorContainer : cs.onSecondaryContainer, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long, size: 12), SizedBox(width: 4), Text('Detail & Refund', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))])))),
                        ]),
                      ])); })),
            ]))))],
      // Held carts overlay
      if (showHeldCarts) ...[_overlay(() => setState(() => showHeldCarts = false)),
        Positioned(top: 120, right: 16, width: 320,
          child: Material(elevation: 8, borderRadius: BorderRadius.circular(16), color: cs.surfaceBright,
            child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('⏱ Ditahan (${heldCarts.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                InkWell(onTap: () => setState(() => showHeldCarts = false), child: const Text('✕'))]),
              const SizedBox(height: 8),
              if (heldCarts.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Tidak ada transaksi ditahan')),
              ...heldCarts.map((h) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h['label'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('${(h['cart_data'] is List ? (h['cart_data'] as List).length : 0)} item · ${fmtPrice(h['total'] ?? 0)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: SizedBox(height: 32, child: FilledButton(onPressed: () => _recallCart(h), style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text('Panggil', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))))),
                    const SizedBox(width: 8),
                    SizedBox(height: 32, child: IconButton(
                      style: IconButton.styleFrom(backgroundColor: cs.secondaryContainer, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      icon: Icon(Icons.receipt_long, size: 16, color: cs.onSecondaryContainer),
                      onPressed: () => _showHeldCartDetail(h),
                    )),
                    const SizedBox(width: 8),
                    SizedBox(height: 32, child: FilledButton(onPressed: () => _deleteHeldCart(h['id'], h['label'] ?? 'antrian ini'),
                      style: FilledButton.styleFrom(backgroundColor: cs.errorContainer.withValues(alpha: 0.5), foregroundColor: cs.error, padding: const EdgeInsets.symmetric(horizontal: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Hapus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
                  ]),
                ]))),
            ]))))],
      // Profile overlay
      if (showProfile) ...[_overlay(() => setState(() => showProfile = false)),
        Center(child: Material(elevation: 8, borderRadius: BorderRadius.circular(16), color: cs.surfaceBright,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 384, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
            child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('👤 Profil Saya', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                InkWell(onTap: () => setState(() => showProfile = false), child: Container(width: 32, height: 32, decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant)))]),
              if (profileMsg.isNotEmpty) ...[const SizedBox(height: 12), Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: profileMsg.startsWith('✅') ? Colors.green.withValues(alpha: 0.1) : cs.errorContainer, borderRadius: BorderRadius.circular(8)),
                child: Text(profileMsg, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: profileMsg.startsWith('✅') ? Colors.green : cs.onErrorContainer), textAlign: TextAlign.center))],
              const SizedBox(height: 16),
              // === NAME ===
              _sectionBox('📝 Nama Tampilan', [
                _field(_nameCtrl..text = _nameCtrl.text.isEmpty ? auth.userName : _nameCtrl.text, 'Nama', false),
              ], 'Simpan Nama', cs.primary, cs.onPrimary, _saveName),
              const SizedBox(height: 12),
              // === PASSWORD ===
              _sectionBox('🔑 Ganti Password', [
                _field(_oldPasswordCtrl, 'Password Lama', true),
                const SizedBox(height: 8),
                _field(_newPasswordCtrl, 'Password Baru', true),
                const SizedBox(height: 8),
                _field(_confirmPasswordCtrl, 'Konfirmasi Password', true),
              ], 'Simpan Password', cs.secondary, cs.onSecondary, _savePassword),
              const SizedBox(height: 12),
              // === PIN ===
              _sectionBox('🔢 Ganti PIN (6 angka)', [
                _field(_oldPinCtrl, 'PIN Lama', true, isPin: true),
                const SizedBox(height: 8),
                _field(_newPinCtrl, 'PIN Baru', true, isPin: true),
                const SizedBox(height: 8),
                _field(_confirmPinCtrl, 'Konfirmasi PIN', true, isPin: true),
              ], 'Simpan PIN', cs.tertiary, cs.onTertiary, _savePin),
            ])))))],
      // Mobile cart bottom sheet
      if (cartOpen && isMobile) ...[_overlay(() => setState(() => cartOpen = false)),
        Positioned(left: 0, right: 0, bottom: 0, child: Material(elevation: 8, color: cs.surfaceBright,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [const Text('🛒 Keranjang', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)), child: Text('${cart.length}', style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)))]),
                Row(children: [
                  if (cart.isNotEmpty) TextButton(onPressed: _clearCart, child: Text('Kosongkan', style: TextStyle(color: cs.error, fontSize: 12))),
                  InkWell(onTap: () => setState(() => cartOpen = false), child: Container(width: 32, height: 32, decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant))),
                ]),
              ])),
              const Divider(),
              Flexible(child: ListView.builder(shrinkWrap: true, itemCount: cart.length, padding: const EdgeInsets.all(12),
                itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: CartItemWidget(item: cart[i], maxAllowedQty: _getMaxCartQty(i), onIncrement: () => _incrementItem(i), onDecrement: () => _decrementItem(i), onRemove: () => _removeItem(i), onSetQuantity: (q) => _setItemQuantity(i, q))))),
              Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)), Text(fmtPrice(cartTotal), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.primary))]),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: SizedBox(height: 44, child: FilledButton(onPressed: cart.isEmpty ? null : _holdCart, style: FilledButton.styleFrom(backgroundColor: cs.secondaryContainer, foregroundColor: cs.onSecondaryContainer, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.access_time, size: 14), SizedBox(width: 6), Text('Tahan', style: TextStyle(fontWeight: FontWeight.bold))]))))]),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 56, child: FilledButton(onPressed: cart.isEmpty ? null : _showPayment, style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 1),
                  child: const Text('💳 BAYAR SEKARANG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))),
              ])),
            ]))))],
      ]),

      // Mobile FAB
      floatingActionButton: isMobile && cart.isNotEmpty && !cartOpen ? FloatingActionButton(
        onPressed: () => setState(() => cartOpen = true),
        backgroundColor: cs.primary,
        child: Badge(label: Text('${cart.length}'), child: Icon(Icons.shopping_bag, color: cs.onPrimary)),
      ) : null,

      // Mobile Bottom Nav
      bottomNavigationBar: isMobile ? Container(
        margin: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
        decoration: BoxDecoration(color: cs.surfaceBright.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(24),
          child: BottomNavigationBar(
            currentIndex: _mobileNavIndex, backgroundColor: Colors.transparent, elevation: 0, type: BottomNavigationBarType.fixed,
            selectedItemColor: cs.primary, unselectedItemColor: cs.onSurfaceVariant,
            selectedLabelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold), unselectedLabelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
            onTap: (i) { setState(() { _closeAllModals(); _mobileNavIndex = i; });
              if (i == 0) { setState(() => showDashboard = true); _loadDashboard(); }
              else if (i == 1) { setState(() => showHistory = true); _loadHistory(); }
              else if (i == 2) setState(() => showSearch = true);
              else if (i == 3) setState(() => showProfile = true);
              else if (auth.isAdmin && i == 4) context.go('/admin');
              else if ((auth.isAdmin && i == 5) || (!auth.isAdmin && i == 4)) _handleLogout();
            },
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.pie_chart), label: 'Rekap'),
              const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Riwayat'),
              const BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Cari'),
              const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
              if (auth.isAdmin) const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Admin'),
              const BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'Keluar'),
            ],
          )),
      ) : null,
    );
  }

  void _showPayment() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => PaymentDialog(subtotal: cartSubtotal, systemDiscount: cartSubtotal - cartTotal, onConfirm: _handleCheckout));
  }

  Future<void> _holdCart() async {
    if (cart.isEmpty) return;
    if (activeCartLabel != null) {
      _doHoldCart(activeCartLabel!);
      return;
    }
    int counter = 1;
    String defaultLabel = 'Pembeli $counter';
    while (heldCarts.any((c) => c['label'] == defaultLabel)) {
      counter++;
      defaultLabel = 'Pembeli $counter';
    }
    final ctrl = TextEditingController(text: defaultLabel);
    final label = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('🛒 Tahan Transaksi'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Beri nama untuk antrian ini', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(
          hintText: 'Nama pembeli...', filled: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? defaultLabel : ctrl.text.trim()), child: const Text('Simpan')),
      ],
    ));
    if (label != null) _doHoldCart(label);
  }

  Future<void> _doHoldCart(String label) async {
    try {
      await Api.post('/held-carts', body: {'label': label, 'cart_data': cart, 'total': cartTotal});
      setState(() { cart.clear(); cartOpen = false; activeCartLabel = null; });
      await _loadHeldCarts(); _loadData();
    } catch (e) { if (mounted) showToast(context, 'Gagal: $e'); }
  }

  Future<void> _clearCart() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const KayConfirmDialog(
        title: 'Kosongkan Keranjang',
        message: 'Apakah Anda yakin ingin mengosongkan semua item di keranjang ini?',
        confirmText: 'Ya, Kosongkan',
      ),
    );
    if (confirmed == true) {
      setState(() {
        cart.clear();
        activeCartLabel = null;
        if (MediaQuery.sizeOf(context).width < 768) cartOpen = false;
      });
    }
  }

  Future<void> _recallCart(dynamic held) async {
    if (cart.isNotEmpty) {
      await Api.post('/held-carts', body: {'label': activeCartLabel ?? 'Pembeli aktif', 'cart_data': cart, 'total': cartTotal}).catchError((_) {});
    }
    await Api.delete('/held-carts/${held['id']}').catchError((_) {});
    final cartList = (held['cart_data'] is List) ? held['cart_data'] as List : [];
    setState(() { cart = List<Map<String, dynamic>>.from(cartList.map((e) => (e is Map) ? Map<String, dynamic>.from(e) : <String, dynamic>{})); activeCartLabel = held['label']?.toString(); showHeldCarts = false; });
    await _loadHeldCarts();
  }

  Future<void> _showHeldCartDetail(dynamic held) async {
    final cs = Theme.of(context).colorScheme;
    final items = (held['cart_data'] is List) ? held['cart_data'] as List : [];
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400, maxHeight: MediaQuery.sizeOf(context).height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Detail: ${held['label']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                InkWell(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close)),
              ]),
            ),
            const Divider(height: 1),
            Flexible(child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
                final qtyStr = qty == qty.truncateToDouble() ? qty.truncate().toString() : qty.toStringAsFixed(2);
                final name = (item['product'] is Map) ? (item['product']['name']?.toString() ?? '') : (item['product_name']?.toString() ?? '');
                final addonSummary = item['addon_summary']?.toString() ?? '';
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${qtyStr}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (addonSummary.isNotEmpty && addonSummary != '[]')
                        Text(addonSummary, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
                    ])),
                  ]),
                );
              },
            )),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(width: double.infinity, height: 44, child: FilledButton.icon(
                icon: const Icon(Icons.print, size: 18),
                label: const Text('Cetak Tiket Dapur', style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  try {
                    final bytes = await ReceiptGenerator.generateKitchenTicket(
                      cartData: held,
                      customerName: held['label']?.toString() ?? 'Pelanggan',
                    );
                    await PrinterService().printReceipt(bytes);
                    if (mounted) showToast(context, '✅ Tiket Dapur Dicetak');
                  } catch (e) {
                    if (mounted) showToast(context, '❌ Gagal cetak: ${e.toString().replaceFirst("Exception: ", "")}');
                  }
                },
              )),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _deleteHeldCart(int id, String label) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => KayConfirmDialog(
      title: 'Hapus Antrian', message: 'Yakin ingin menghapus antrian "$label"? Semua item akan dihapus.', confirmText: 'Ya, Hapus'));
    if (confirmed != true) return;
    try { await Api.delete('/held-carts/$id'); await _loadHeldCarts(); _loadData(); } catch (_) {}
  }

  Widget _overlay(VoidCallback onTap) => Positioned.fill(child: GestureDetector(onTap: onTap, child: Container(color: Colors.black54)));

  Widget _statCard(String label, String value, Color bg, Color textColor) {
    return Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: textColor)),
      ])));
  }

  /// ── Cashier: Transaction Detail with Item-Level Refund ──
  Future<void> _showKasirTxDetail(Map<String, dynamic> tx) async {
    try {
      final res = await Api.get('/transactions/${tx['id']}');
      var txData = res['transaction'] as Map<String, dynamic>? ?? tx;
      var details = (res['details'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
      if (!mounted) return;
      final cs = Theme.of(context).colorScheme;

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setDState) {
          final status = txData['status']?.toString() ?? 'completed';
          // Check if there are any refundable items left
          final auth = context.read<AuthProvider>();
          final bool canRefund = auth.isAdmin || auth.userName == (txData['cashier_name'] ?? '');
          final hasRefundableItems = canRefund && status != 'voided' && details.any((d) {
            final q = (d['quantity'] as num?)?.toDouble() ?? 0;
            final r = (d['refunded_qty'] as num?)?.toDouble() ?? 0;
            return r < q;
          });
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ── Header ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: BoxDecoration(
                    color: status == 'voided' ? Colors.red.shade50 : cs.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Transaksi #${txData['id']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (status == 'voided') ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)), child: const Text('VOID', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)))]
                        else if (status == 'partial_refund') ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)), child: const Text('PARTIAL REFUND', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)))],
                      ]),
                      const SizedBox(height: 4),
                      Text('${txData['created_at'] ?? ''} • ${txData['cashier_name'] ?? ''}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ])),
                    IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                const Divider(height: 1),
                // ── Item List with Refund Buttons ──
                Flexible(child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: details.length,
                  separatorBuilder: (_, _i) => Divider(height: 16, color: cs.outlineVariant.withValues(alpha: 0.3)),
                  itemBuilder: (_, i) {
                    final d = details[i];
                    final qty = (d['quantity'] as num?)?.toDouble() ?? 0;
                    final refundedQty = (d['refunded_qty'] as num?)?.toDouble() ?? 0;
                    final remainingQty = qty - refundedQty;
                    final soldPrice = (d['sold_price'] as num?)?.toDouble() ?? 0;
                    final discountPct = (d['discount_percent'] as num?)?.toDouble() ?? 0;
                    final effectivePrice = soldPrice * (1 - discountPct / 100);
                    final effectiveSubtotal = effectivePrice * remainingQty;
                    final isFullyRefunded = refundedQty >= qty;

                    return Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d['product_name']?.toString() ?? '-', style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13,
                          decoration: isFullyRefunded ? TextDecoration.lineThrough : null,
                          color: isFullyRefunded ? Colors.grey : null)),
                        Row(children: [
                          Text('${qty.round()} pcs × ${fmtPrice(soldPrice)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          if (refundedQty > 0) Text('  (refund: ${refundedQty.round()})', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade600)),
                        ]),
                      ])),
                      Text(fmtPrice(effectiveSubtotal), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                        decoration: isFullyRefunded ? TextDecoration.lineThrough : null,
                        color: isFullyRefunded ? Colors.grey : null)),
                      // Refund button
                      if (canRefund && remainingQty > 0 && status != 'voided')
                        Padding(padding: const EdgeInsets.only(left: 8), child: SizedBox(width: 30, height: 30,
                          child: IconButton(padding: EdgeInsets.zero, iconSize: 16,
                            icon: Icon(Icons.undo, color: Colors.red.shade400),
                            tooltip: 'Refund',
                            onPressed: () async {
                              final maxQty = remainingQty.round();
                              final qtyCtrl = TextEditingController(text: maxQty.toString());
                              final confirmed = await showDialog<bool>(context: ctx, builder: (dlgCtx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Text('Refund: ${d['product_name']}', style: const TextStyle(fontSize: 15)),
                                content: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text('Maks: $maxQty pcs', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 10),
                                  TextField(controller: qtyCtrl,
                                    onChanged: (v) {
                                      final n = int.tryParse(v) ?? 0;
                                      if (n > maxQty) { qtyCtrl.text = maxQty.toString(); qtyCtrl.selection = TextSelection.fromPosition(TextPosition(offset: qtyCtrl.text.length)); }
                                    },
                                    decoration: InputDecoration(
                                    labelText: 'Jumlah refund', isDense: true, suffixText: 'pcs',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ), keyboardType: const TextInputType.numberWithOptions(decimal: false)),
                                  const SizedBox(height: 8),
                                  ListenableBuilder(listenable: qtyCtrl, builder: (_, __) {
                                    final rQty = double.tryParse(qtyCtrl.text) ?? 0;
                                    if (rQty <= 0) return const SizedBox.shrink();
                                    return Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                                      child: Text('Pengembalian: ${fmtPrice(effectivePrice * rQty)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700)));
                                  }),
                                ]),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Batal')),
                                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                    onPressed: () => Navigator.pop(dlgCtx, true), child: const Text('Konfirmasi Refund')),
                                ],
                              ));
                              if (confirmed != true) return;
                              final rQty = double.tryParse(qtyCtrl.text) ?? 0;
                              if (rQty <= 0 || rQty > remainingQty) return;
                              try {
                                await Api.post('/transactions/${txData['id']}/refund', body: {
                                  'items': [{'detail_id': d['id'], 'qty_to_refund': rQty}],
                                  'refunded_by': auth.userName,
                                });
                                // Reload dialog data
                                final newRes = await Api.get('/transactions/${txData['id']}');
                                setDState(() {
                                  txData = newRes['transaction'] as Map<String, dynamic>? ?? txData;
                                  details = (newRes['details'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? details;
                                });
                                // Refresh parent data
                                _loadData(); _loadHistory(); _loadDashboard(); _loadStockAlerts();
                                if (mounted) showToast(context, '✅ Refund berhasil');
                              } catch (e) {
                                if (mounted) showToast(context, '❌ ${e.toString().replaceFirst("Exception: ", "")}');
                              }
                            },
                          ),
                        )),
                    ]);
                  },
                )),
                const Divider(height: 1),
                // ── Footer Totals + Refund Semua ──
                Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Total', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
                    Text(fmtPrice(txData['total_amount'] ?? 0), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: status == 'voided' ? cs.error : cs.primary)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Bayar', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    Text(fmtPrice(txData['paid_amount'] ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  // ── Refund Semua Button ──
                  if (hasRefundableItems) ...[
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, height: 40, child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('Refund Semua (Void Transaksi)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () async {
                        final ok = await showDialog<bool>(context: ctx, builder: (dlgCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Konfirmasi Void', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          content: const Text('Refund SEMUA item dalam transaksi ini?\n\nStok bahan akan dikembalikan dan transaksi akan di-void.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Batal')),
                            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(dlgCtx, true), child: const Text('Ya, Void Semua')),
                          ],
                        ));
                        if (ok != true) return;
                        try {
                          final payload = details.where((d) {
                            final q = (d['quantity'] as num?)?.toDouble() ?? 0;
                            final r = (d['refunded_qty'] as num?)?.toDouble() ?? 0;
                            return r < q;
                          }).map((d) => {
                            'detail_id': d['id'],
                            'qty_to_refund': ((d['quantity'] as num?)?.toDouble() ?? 0) - ((d['refunded_qty'] as num?)?.toDouble() ?? 0),
                          }).toList();
                          await Api.post('/transactions/${txData['id']}/refund', body: {
                            'items': payload,
                            'refunded_by': auth.userName,
                          });
                          final newRes = await Api.get('/transactions/${txData['id']}');
                          setDState(() {
                            txData = newRes['transaction'] as Map<String, dynamic>? ?? txData;
                            details = (newRes['details'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? details;
                          });
                          _loadData(); _loadHistory(); _loadDashboard(); _loadStockAlerts();
                          if (mounted) showToast(context, '✅ Transaksi berhasil di-void');
                        } catch (e) {
                          if (mounted) showToast(context, '❌ ${e.toString().replaceFirst("Exception: ", "")}');
                        }
                      },
                    )),
                  ],
                ])),
              ]),
            ),
          );
        }),
      );
    } catch (e) {
      if (mounted) showToast(context, 'Gagal memuat detail: $e');
    }
  }

  Future<void> _reprintReceipt(dynamic txId) async {
    try {
      final res = await Api.get('/transactions/$txId');
      if (mounted) {
        showDialog(context: context, builder: (_) => ReceiptModal(
          transaction: res['transaction'] ?? res,
          details: List<Map<String, dynamic>>.from(res['details'] ?? [])),
        );
      }
    } catch (e) { if (mounted) showToast(context, 'Gagal memuat nota: $e'); }
  }

  Future<void> _saveName() async {
    try {
      final name = _nameCtrl.text.trim();
      if (name.isEmpty || name == context.read<AuthProvider>().userName) { setState(() => profileMsg = 'Tidak ada perubahan nama'); return; }
      await Api.put('/auth/profile', body: {'name': name});
      context.read<AuthProvider>().updateUserName(name);
      setState(() => profileMsg = '✅ Nama berhasil diubah!');
    } catch (e) { setState(() => profileMsg = '❌ ${e.toString().replaceFirst("Exception: ", "")}'); }
  }

  Future<void> _savePassword() async {
    try {
      if (_newPasswordCtrl.text.isEmpty) { setState(() => profileMsg = 'Password baru wajib diisi'); return; }
      await Api.put('/auth/profile', body: {'old_password': _oldPasswordCtrl.text, 'new_password': _newPasswordCtrl.text, 'confirm_password': _confirmPasswordCtrl.text});
      _oldPasswordCtrl.clear(); _newPasswordCtrl.clear(); _confirmPasswordCtrl.clear();
      setState(() => profileMsg = '✅ Password berhasil diubah!');
    } catch (e) { setState(() => profileMsg = '❌ ${e.toString().replaceFirst("Exception: ", "")}'); }
  }

  Future<void> _savePin() async {
    try {
      if (_newPinCtrl.text.isEmpty) { setState(() => profileMsg = 'PIN baru wajib diisi'); return; }
      await Api.put('/auth/profile', body: {'old_pin': _oldPinCtrl.text, 'new_pin': _newPinCtrl.text, 'confirm_pin': _confirmPinCtrl.text});
      _oldPinCtrl.clear(); _newPinCtrl.clear(); _confirmPinCtrl.clear();
      setState(() => profileMsg = '✅ PIN berhasil diubah!');
    } catch (e) { setState(() => profileMsg = '❌ ${e.toString().replaceFirst("Exception: ", "")}'); }
  }

  Widget _sectionBox(String title, List<Widget> fields, String btnLabel, Color btnBg, Color btnFg, VoidCallback onSave) {
    final cs = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: cs.surfaceContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        ...fields,
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 36, child: FilledButton(onPressed: onSave,
          style: FilledButton.styleFrom(backgroundColor: btnBg, foregroundColor: btnFg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: Text(btnLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
      ]));
  }

  Widget _field(TextEditingController ctrl, String hint, bool obscure, {bool isPin = false}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(height: 40, child: TextField(
      controller: ctrl, obscureText: obscure,
      keyboardType: isPin ? TextInputType.number : TextInputType.text,
      inputFormatters: isPin ? [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ] : null,
      textAlign: isPin ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: 14, color: cs.onSurface, letterSpacing: 0),
      decoration: InputDecoration(hintText: hint, filled: true, fillColor: cs.surfaceContainer, isDense: true,
        hintStyle: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, letterSpacing: 0),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ));
  }

  Widget _toolbarBtn(IconData icon, String label, {Color? color, Color? textColor, String? badge, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: color ?? Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: textColor ?? cs.onSurfaceVariant),
                if (badge != null)
                  Positioned(
                    right: -6, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: cs.secondary, borderRadius: BorderRadius.circular(10)),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(child: Text(badge, style: TextStyle(color: cs.onSecondary, fontSize: 9, fontWeight: FontWeight.bold))),
                    ),
                  ),
              ],
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor ?? cs.onSurfaceVariant)),
            ]
          ],
        ),
      ),
    );
  }
}
