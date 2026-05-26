import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String pin = '';
  String error = '';
  bool loading = false;
  int attempts = 0;
  static const maxAttempts = 3;
  final _focusNode = FocusNode();
  final _pinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() { _focusNode.dispose(); _pinCtrl.dispose(); super.dispose(); }

  Future<void> _handleUnlock() async {
    if (pin.length != 6) return;
    setState(() { loading = true; error = ''; });
    final auth = context.read<AuthProvider>();
    final ok = await auth.unlock(pin);
    if (!ok) {
      attempts++;
      if (attempts >= maxAttempts) {
        auth.logout();
        if (mounted) context.go('/login');
        return;
      }
      setState(() { error = 'PIN salah ($attempts/$maxAttempts)'; pin = ''; });
      _pinCtrl.clear();
      _focusNode.requestFocus();
    }
    if (mounted) setState(() => loading = false);
  }

  void _handleInput(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    setState(() => pin = digits.length > 6 ? digits.substring(0, 6) : digits);
    if (pin.length == 6) _handleUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(child: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Lock icon
        Container(width: 64, height: 64, decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
          child: Icon(Icons.lock, size: 28, color: cs.primary)),
        const SizedBox(height: 16),
        Text('Layar Terkunci', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text(auth.userName, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text('Masukkan PIN 6 digit', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
        const SizedBox(height: 20),
        if (error.isNotEmpty) Container(
          width: double.infinity, padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
          child: Text(error, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onErrorContainer), textAlign: TextAlign.center)),
        // PIN dots
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(6, (i) => Container(
          width: 16, height: 16, margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: i < pin.length ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4)),
        ))),
        const SizedBox(height: 16),
        // Hidden input
        SizedBox(height: 56, child: TextField(
          controller: _pinCtrl,
          focusNode: _focusNode,
          onChanged: _handleInput,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          obscureText: true,
          textAlign: TextAlign.center,
          enabled: !loading,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 12, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: '● ● ● ● ● ●', filled: true, fillColor: cs.surfaceContainer,
          ),
        )),
        if (loading) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Memverifikasi...', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 44, child: FilledButton(
          onPressed: () { auth.logout(); context.go('/login'); },
          style: FilledButton.styleFrom(backgroundColor: cs.errorContainer.withValues(alpha: 0.5), foregroundColor: cs.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Ganti Akun / Login Ulang', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)))),
      ]))),
    );
  }
}
