import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../../../core/helpers.dart';

class ProductCard extends StatelessWidget {
  final dynamic product;
  final double bookedQty;
  final int discountPercent;
  final String? promoName;
  final int effectiveStock;
  final Function(dynamic) onSelect;
  const ProductCard({super.key, required this.product, required this.bookedQty, this.discountPercent = 0, this.promoName, this.effectiveStock = -1, required this.onSelect});

  // Safe num parser — never crashes
  static double _safeDouble(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  Color _categoryColor(String name, ColorScheme cs) {
    if (name.isEmpty) return cs.primary;
    final hash = name.hashCode.abs();
    final hues = [210, 260, 330, 170, 30, 190, 290, 140, 350, 50];
    final hue = hues[hash % hues.length].toDouble();
    return HSLColor.fromAHSL(1, hue, 0.5, 0.55).toColor();
  }

  @override
  Widget build(BuildContext context) {
    // === EXTREME FAIL-SAFE: catch ANY error inside build ===
    try {
      return _buildCard(context);
    } catch (e) {
      // RED ERROR CARD — visible debug info on release builds
      return Container(
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red, width: 2),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 20),
            const SizedBox(height: 4),
            Text('CRASH: ${e.toString().length > 80 ? e.toString().substring(0, 80) : e}',
              style: const TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold),
              maxLines: 3, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text('Data: ${product?.toString().substring(0, (product?.toString().length ?? 0).clamp(0, 60))}',
              style: const TextStyle(fontSize: 7, color: Colors.black54),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String categoryIcon = (product is Map ? product['category_icon'] : null)?.toString() ?? '📦';
    final String categoryName = (product is Map ? product['category_name'] : null)?.toString() ?? '';
    final String productName = (product is Map ? product['name'] : null)?.toString() ?? 'Produk';

    final double baseUnitPrice = _safeDouble(product is Map ? product['price'] : 0.0);

    final dynamic rawPortions = product is Map ? product['available_portions'] : null;
    final bool isPaket = (product is Map ? (product['is_paket'] as num?)?.toInt() : 0) == 1;
    // For packages: available_portions is null (dynamically computed via effectiveStock).
    // hasRecipe = true if the product has stock tracking (regular: rawPortions != null, paket: effectiveStock != -1)
    final bool hasRecipe = isPaket ? (effectiveStock != -1) : (rawPortions != null);
    final int absolutePortions = rawPortions != null ? (rawPortions as num).toInt() : (isPaket ? effectiveStock : -1);
    final bool isHabis = hasRecipe && absolutePortions <= 0 && bookedQty == 0;
    // DI KERANJANG: only when THIS product's own cart qty > 0 AND effective stock hit 0
    final bool isBooked = hasRecipe && !isHabis && bookedQty > 0 && effectiveStock <= 0;
    final bool soldOut = isHabis || isBooked;

    return Opacity(
      opacity: soldOut ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: (hasRecipe && effectiveStock == 0) ? null : () => onSelect(product),
          onLongPress: () => isPaket ? _showPaketDetails(context) : _showRecipeDetails(context),
          borderRadius: BorderRadius.circular(8),
          splashColor: (isDark ? Colors.deepPurpleAccent : cs.primary).withValues(alpha: 0.2),
          hoverColor: (isDark ? Colors.deepPurpleAccent : cs.primary).withValues(alpha: 0.08),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDark ? Colors.deepPurpleAccent.withValues(alpha: 0.15) : cs.primary.withValues(alpha: 0.05),
              border: Border.all(color: isDark ? Colors.deepPurpleAccent.withValues(alpha: 0.5) : cs.primary.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Stack(clipBehavior: Clip.none, children: [
              Row(children: [
                // Icon
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.deepPurpleAccent.withValues(alpha: 0.2) : cs.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: buildCategoryIcon(categoryIcon, size: 16),
                ),
                const SizedBox(width: 8),
                // Text Content
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        alignment: Alignment.centerLeft,
                        child: AutoSizeText(
                          toTitleCase(productName),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: MediaQuery.sizeOf(context).width < 768 ? 12 : 14, color: isDark ? Colors.white : cs.onSurface, height: 1.1),
                          maxLines: 1,
                          minFontSize: 8,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            if (discountPercent > 0) ...[
                              Text(fmtPrice(baseUnitPrice), style: TextStyle(fontSize: 10, decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant)),
                              const SizedBox(width: 4),
                              Text(fmtPrice(baseUnitPrice * (1 - discountPercent / 100)), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.yellowAccent : Colors.orange)),
                            ] else
                              Text(fmtPrice(baseUnitPrice), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.greenAccent : cs.primary, height: 1.1)),
                            if (hasRecipe) ...[
                              const SizedBox(width: 6),
                              Text('· ${effectiveStock >= 0 ? effectiveStock : absolutePortions} porsi', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: soldOut ? cs.error : ((effectiveStock >= 0 ? effectiveStock : absolutePortions) <= 5 ? Colors.amber[700] : cs.onSurfaceVariant))),
                            ],
                          ]
                        )
                      ),
                    ),
                  ],
                )),
              ]),

              // Badges
              if (soldOut) Positioned(top: -2, right: -2,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: isHabis ? cs.error : Colors.orange[800], borderRadius: BorderRadius.circular(4)),
                    child: Text(isHabis ? 'HABIS' : 'DI KERANJANG', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ]),
              )
              else if (isPaket) Positioned(top: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Colors.deepOrange, Colors.deepPurple]),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
                  ),
                  child: const Text('PAKET', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              )
              else if (discountPercent > 0) Positioned(top: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(color: Colors.amberAccent, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))]),
                  child: Text('-$discountPercent%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black)),
                )
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showBottleneck(BuildContext context) async {
    final productId = product is Map ? product['id'] : null;
    if (productId == null) return;
    try {
      final data = await _fetchBottleneck(productId);
      if (!context.mounted) return;
      final cs = Theme.of(context).colorScheme;
      final items = (data['items'] as List?) ?? [];
      final isPaketProduct = data['is_paket'] == true;
      
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.info, color: cs.error, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Detail Stok Habis', style: TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(
          width: 360,
          child: items.isEmpty
            ? const Text('Tidak ada detail yang tersedia.')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(isPaketProduct ? 'Produk isi paket yang habis:' : 'Bahan baku yang tidak mencukupi:', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      if (isPaketProduct) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text("Produk: ${item['name']} (Sisa: ${item['available']}, Butuh: ${item['needed']})", style: const TextStyle(fontSize: 13)),
                        );
                      } else {
                        final stock = _safeDouble(item['stock']).toStringAsFixed(0);
                        final needed = _safeDouble(item['qty_needed']).toStringAsFixed(0);
                        final unit = item['unit'] ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text("Bahan: ${item['name']} (Sisa: $stock $unit, Butuh: $needed $unit)", style: const TextStyle(fontSize: 13)),
                        );
                      }
                    },
                  ),
                ),
              ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _fetchBottleneck(dynamic productId) async {
    // Import would be circular, so we use a direct DB call pattern
    // This accesses the API layer which is already imported in the app
    try {
      final dynamic result = await _callApi('/products/$productId/bottleneck');
      return result is Map<String, dynamic> ? result : {};
    } catch (_) { return {}; }
  }

  Future<void> _showPaketDetails(BuildContext context) async {
    final productId = product is Map ? product['id'] : null;
    final productName = product is Map ? product['name'] : 'Paket';
    if (productId == null) return;
    try {
      final data = await _callApi('/paket-items/$productId');
      if (!context.mounted) return;
      final cs = Theme.of(context).colorScheme;
      final items = (data as List?) ?? [];
      
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Detail Isi Paket: $productName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Container(
          width: 360,
          constraints: const BoxConstraints(maxHeight: 400),
          child: items.isEmpty
            ? const Text('Tidak ada detail yang tersedia.')
            : ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final qty = _safeDouble(item['qty']).toStringAsFixed(0);
                  final name = item['product_name'] ?? '-';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(" - ${qty}x $name", style: const TextStyle(fontSize: 13)),
                  );
                },
              ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ));
    } catch (_) {}
  }

  Future<void> _showRecipeDetails(BuildContext context) async {
    final productId = product is Map ? product['id'] : null;
    final productName = product is Map ? product['name'] : 'Produk';
    if (productId == null) return;
    try {
      final data = await _callApi('/resep/$productId');
      if (!context.mounted) return;
      final items = (data as List?) ?? [];
      
      showDialog(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Resep: $productName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Container(
          width: 360,
          constraints: const BoxConstraints(maxHeight: 400),
          child: items.isEmpty
            ? const Text('Produk ini tidak memiliki resep.')
            : ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final item = items[i];
                  final qtyNeeded = _safeDouble(item['qty_needed']).toStringAsFixed(0);
                  final unit = item['bahan_unit']?.toString() ?? '';
                  final name = item['bahan_name']?.toString() ?? '-';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(" - $qtyNeeded $unit $name", style: const TextStyle(fontSize: 13)),
                  );
                },
              ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ));
    } catch (_) {}
  }

  static Future<dynamic> _callApi(String path) async {
    // Lazy import pattern - we call the static Api.get
    // The Api class is accessible via the app's import tree
    return await _apiGetter?.call(path);
  }

  static Future<dynamic> Function(String)? _apiGetter;
  static void setApiGetter(Future<dynamic> Function(String) getter) {
    _apiGetter = getter;
  }
}
