import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme_provider.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});
  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => tp.toggle(),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(color: cs.surfaceContainer, shape: BoxShape.circle),
        child: Icon(tp.isDark ? Icons.wb_sunny : Icons.dark_mode, size: 22, color: tp.isDark ? Colors.amber : cs.onSurfaceVariant),
      ),
    );
  }
}
