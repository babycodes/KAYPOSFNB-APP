import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../../../core/helpers.dart';

class ProductCard extends StatelessWidget {
  final dynamic product;
  final double bookedQty;
  final int discountPercent;
  final String? promoName;
  final Function(dynamic) onSelect;
  const ProductCard({super.key, required this.product, required this.bookedQty, this.discountPercent = 0, this.promoName, required this.onSelect});

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

    // Bottleneck: available portions from BOM
    final dynamic rawPortions = product is Map ? product['available_portions'] : null;
    final bool hasRecipe = rawPortions != null;
    final int availablePortions = hasRecipe ? (rawPortions as num).toInt() : -1; // -1 = no recipe
    final bool soldOut = hasRecipe && availablePortions <= 0;

    return Opacity(
      opacity: soldOut ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: soldOut ? null : () => onSelect(product),
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
                              Text('· $availablePortions porsi', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: availablePortions <= 0 ? cs.error : (availablePortions <= 5 ? Colors.amber[700] : cs.onSurfaceVariant))),
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
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(4)),
                  child: const Text('HABIS', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: Colors.white)),
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
}
