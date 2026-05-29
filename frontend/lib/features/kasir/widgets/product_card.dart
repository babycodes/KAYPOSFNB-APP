import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../../../core/helpers.dart';

class ProductCard extends StatefulWidget {
  final dynamic product;
  final double bookedQty;
  final int discountPercent;
  final String? promoName;
  final int effectiveStock;
  final int baseStock;
  final Function(dynamic) onSelect;
  const ProductCard({super.key, required this.product, required this.bookedQty, this.discountPercent = 0, this.promoName, this.effectiveStock = -1, this.baseStock = -1, required this.onSelect});

  // Safe num parser — never crashes
  static double _safeDouble(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  @override
  State<ProductCard> createState() => _ProductCardState();

  static Future<dynamic> Function(String)? _apiGetter;
  static void setApiGetter(Future<dynamic> Function(String) getter) {
    _apiGetter = getter;
  }
}

class _ProductCardState extends State<ProductCard> {
  // Unique key to restart TweenAnimationBuilder on each flash
  int _flashKey = 0;
  bool _shouldFlash = false;

  @override
  void didUpdateWidget(covariant ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Detect stock change from EXTERNAL source (shared ingredient deduction)
    // Only flash when stock DECREASES and we're not sold out
    if (widget.effectiveStock != -1 &&
        oldWidget.effectiveStock != -1 &&
        widget.effectiveStock < oldWidget.effectiveStock &&
        widget.effectiveStock > 0) {
      _shouldFlash = true;
      _flashKey++;
    } else {
      _shouldFlash = false;
    }
  }

  /// Maps master unit to recipe display unit for human-readable output
  static String _recipeDisplayUnit(String masterUnit) {
    final lower = masterUnit.toLowerCase();
    if (lower == 'kg') return 'gram';
    if (lower == 'liter' || lower == 'l') return 'ml';
    return masterUnit;
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
            Text('Data: ${widget.product?.toString().substring(0, (widget.product?.toString().length ?? 0).clamp(0, 60))}',
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
    final product = widget.product;

    final String categoryIcon = (product is Map ? product['category_icon'] : null)?.toString() ?? '📦';
    final String productName = (product is Map ? product['name'] : null)?.toString() ?? 'Produk';

    final double baseUnitPrice = ProductCard._safeDouble(product is Map ? product['price'] : 0.0);

    final bool isPaket = (product is Map ? (product['is_paket'] as num?)?.toInt() : 0) == 1;
    // hasRecipe = true when this product has stock tracking (effectiveStock != -1)
    final bool hasRecipe = widget.effectiveStock != -1;
    // soldOut = stock is at 0 and product has tracking
    final bool soldOut = hasRecipe && widget.effectiveStock <= 0;
    // HABIS = DB stock truly at 0 (baseStock <= 0). DI PESAN = reserved (baseStock > 0 but effectiveStock <= 0)
    final bool isHabis = soldOut && widget.baseStock <= 0;

    // Base border color
    final Color baseBorderColor = isDark ? Colors.deepPurpleAccent.withValues(alpha: 0.5) : cs.primary.withValues(alpha: 0.3);

    // Build the card content (shared between flash and non-flash)
    Widget cardContent = Stack(clipBehavior: Clip.none, children: [
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
                    if (widget.discountPercent > 0) ...[
                      Text(fmtPrice(baseUnitPrice), style: TextStyle(fontSize: 10, decoration: TextDecoration.lineThrough, color: cs.onSurfaceVariant)),
                      const SizedBox(width: 4),
                      Text(fmtPrice(baseUnitPrice * (1 - widget.discountPercent / 100)), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.yellowAccent : Colors.orange)),
                    ] else
                      Text(fmtPrice(baseUnitPrice), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.greenAccent : cs.primary, height: 1.1)),
                    if (hasRecipe) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Porsi berbagi bahan baku dapur',
                        child: Icon(Icons.link, size: 12, color: isDark ? Colors.white54 : cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(width: 2),
                      Text('Maks ${widget.effectiveStock}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: soldOut ? cs.error : (widget.effectiveStock <= 5 ? Colors.amber[700] : cs.onSurfaceVariant))),
                    ],
                  ]
                )
              ),
            ),
          ],
        )),
      ]),

      // Badges — render in a Row to support multiple simultaneous badges
      if (soldOut || isPaket || widget.discountPercent > 0)
        Positioned(top: -4, right: -4,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Sold-out badge (highest priority, exclusive)
            if (soldOut) Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: isHabis ? cs.error : Colors.orange[800], borderRadius: BorderRadius.circular(4)),
              child: Text(isHabis ? 'HABIS' : 'DI PESAN', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            // Discount badge (left side when paired with PAKET)
            if (!soldOut && widget.discountPercent > 0) Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(color: Colors.amberAccent, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))]),
              child: Text('-${widget.discountPercent}%', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black)),
            ),
            // Spacing between discount and paket badges
            if (!soldOut && widget.discountPercent > 0 && isPaket) const SizedBox(width: 4),
            // Paket badge (right side)
            if (!soldOut && isPaket) Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.deepOrange, Colors.deepPurple]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
              ),
              child: const Text('PAKET', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ]),
        ),
    ]);

    // Wrap card in border-flash animation when stock changes from shared deduction
    Widget cardContainer;
    if (_shouldFlash) {
      cardContainer = TweenAnimationBuilder<double>(
        key: ValueKey(_flashKey),
        tween: Tween(begin: 1.0, end: 0.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (_, flashValue, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDark ? Colors.deepPurpleAccent.withValues(alpha: 0.15) : cs.primary.withValues(alpha: 0.05),
              border: Border.all(
                color: Color.lerp(baseBorderColor, Colors.amber, flashValue)!,
                width: 1.0 + flashValue,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: child,
          );
        },
        child: cardContent,
      );
    } else {
      cardContainer = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isDark ? Colors.deepPurpleAccent.withValues(alpha: 0.15) : cs.primary.withValues(alpha: 0.05),
          border: Border.all(color: baseBorderColor),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: cardContent,
      );
    }

    return Opacity(
      opacity: soldOut ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: (hasRecipe && widget.effectiveStock == 0) ? null : () => widget.onSelect(product),
          onLongPress: () => isPaket ? _showPaketDetails(context) : _showRecipeDetails(context),
          borderRadius: BorderRadius.circular(8),
          splashColor: (isDark ? Colors.deepPurpleAccent : cs.primary).withValues(alpha: 0.2),
          hoverColor: (isDark ? Colors.deepPurpleAccent : cs.primary).withValues(alpha: 0.08),
          child: cardContainer,
        ),
      ),
    );
  }

  void _showPaketDetails(BuildContext context) async {
    final productId = widget.product is Map ? widget.product['id'] : null;
    final productName = widget.product is Map ? widget.product['name'] : 'Paket';
    if (productId == null) return;
    try {
      final data = await _callApi('/paket-items/$productId');
      if (!context.mounted) return;
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
                  final qty = ProductCard._safeDouble(item['qty']).toStringAsFixed(0);
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
    final productId = widget.product is Map ? widget.product['id'] : null;
    final productName = widget.product is Map ? widget.product['name'] : 'Produk';
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
                  final qtyNeeded = ProductCard._safeDouble(item['qty_needed']).toStringAsFixed(0);
                  // Normalize: show gram/ml instead of Kg/Liter for recipe display
                  final rawUnit = item['bahan_unit']?.toString() ?? '';
                  final displayUnit = _recipeDisplayUnit(rawUnit);
                  final name = item['bahan_name']?.toString() ?? '-';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(" - $qtyNeeded $displayUnit $name", style: const TextStyle(fontSize: 13)),
                  );
                },
              ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ));
    } catch (_) {}
  }

  static Future<dynamic> _callApi(String path) async {
    return await ProductCard._apiGetter?.call(path);
  }
}
