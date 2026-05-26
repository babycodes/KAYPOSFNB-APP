import 'package:flutter/material.dart';

class KayConfirmDialog extends StatelessWidget {
  final String title, message, confirmText;
  const KayConfirmDialog({super.key, required this.title, required this.message, this.confirmText = 'Hapus'});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 384),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.errorContainer, shape: BoxShape.circle),
              child: Icon(Icons.warning_amber, size: 20, color: cs.error)),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
          ]),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: SizedBox(height: 48, child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600))))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: SizedBox(height: 48, child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: cs.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.bold))))),
          ]),
        ]))),
    );
  }
}
